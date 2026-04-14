import 'dart:convert';

import '../models.dart';
import 'config_store.dart';
import 'integrated_llm_client.dart';
import 'local_delta_state.dart';
import 'local_worldpkg.dart';

class LocalSceneAdaptationItem {
  const LocalSceneAdaptationItem({
    required this.strategies,
    required this.target,
    required this.deltaSource,
    required this.original,
    required this.plan,
    required this.nearestStateReasoning,
    required this.intensityGuidance,
  });

  final List<String> strategies;
  final String target;
  final String deltaSource;
  final String? original;
  final String plan;
  final String nearestStateReasoning;
  final String intensityGuidance;

  factory LocalSceneAdaptationItem.fromJson(Map<String, dynamic> json) {
    final strategies =
        (json['strategies'] as List<dynamic>? ?? const <dynamic>[])
            .map((value) => value.toString().trim())
            .where((value) => value.isNotEmpty)
            .toList();
    return LocalSceneAdaptationItem(
      strategies: strategies.isEmpty ? const <String>['rewrite'] : strategies,
      target: json['target'] as String? ?? '',
      deltaSource: json['delta_source'] as String? ?? '',
      original: json['original'] as String?,
      plan: json['plan'] as String? ?? '',
      nearestStateReasoning:
          json['nearest_state_reasoning'] as String? ?? '',
      intensityGuidance: json['intensity_guidance'] as String? ?? '',
    );
  }
}

class LocalSceneAdaptationPlan {
  const LocalSceneAdaptationPlan({
    required this.deltaImpactSummary,
    required this.adaptations,
  });

  final String deltaImpactSummary;
  final List<LocalSceneAdaptationItem> adaptations;

  String renderPlanTags() {
    final parts = <String>['<adaptation_plan>'];
    for (final item in adaptations) {
      final strategy = item.strategies.join('+');
      parts.add(
        '<adaptation strategy="$strategy" intensity="${_xmlEscape(item.intensityGuidance)}" delta_source="${_xmlEscape(item.deltaSource)}">',
      );
      parts.add('  <target>${_xmlEscape(item.target)}</target>');
      if (item.original != null && item.original!.trim().isNotEmpty) {
        parts.add('  <original>${_xmlEscape(item.original!.trim())}</original>');
      }
      parts.add('  <plan>${_xmlEscape(item.plan)}</plan>');
      parts.add('</adaptation>');
    }
    parts.add('</adaptation_plan>');
    return parts.join('\n');
  }
}

class LocalSceneAdaptationResult {
  const LocalSceneAdaptationResult({
    required this.plan,
    required this.adaptedPhaseSource,
    required this.adaptedFallbackText,
  });

  final LocalSceneAdaptationPlan plan;
  final String adaptedPhaseSource;
  final String adaptedFallbackText;

  String get adaptationPlanText => plan.renderPlanTags();
}

class LocalSceneAdaptationPlanner {
  LocalSceneAdaptationPlanner({
    required this.store,
    required this.llmClient,
    required this.loadConfig,
  });

  final ConfigStore store;
  final IntegratedLlmClient llmClient;
  final Future<LlmConfigMap> Function() loadConfig;

  Future<LocalSceneAdaptationResult?> adapt({
    required String locale,
    required String phase,
    required LocalWorldEvent event,
    required String phaseSource,
    required String fallbackText,
    required LocalDeltaStateManager deltaState,
  }) async {
    final selection = _selectRelevantDeltas(
      event: event,
      phaseSource: phaseSource,
      fallbackText: fallbackText,
      deltaState: deltaState,
    );
    if (selection.isEmpty) {
      return null;
    }

    final plan =
        await _tryLlmPlan(
          locale: locale,
          phase: phase,
          event: event,
          phaseSource: phaseSource,
          selection: selection,
        ) ??
        _heuristicPlan(
          locale: locale,
          phase: phase,
          event: event,
          phaseSource: phaseSource,
          selection: selection,
        );
    if (plan.adaptations.isEmpty) {
      return null;
    }

    return LocalSceneAdaptationResult(
      plan: plan,
      adaptedPhaseSource: _adaptText(
        locale: locale,
        phase: phase,
        summary: plan.deltaImpactSummary,
        original: phaseSource,
      ),
      adaptedFallbackText: _adaptText(
        locale: locale,
        phase: phase,
        summary: plan.deltaImpactSummary,
        original: fallbackText,
      ),
    );
  }

  List<_SelectedDelta> _selectRelevantDeltas({
    required LocalWorldEvent event,
    required String phaseSource,
    required String fallbackText,
    required LocalDeltaStateManager deltaState,
  }) {
    final query = <String>[
      event.goal,
      event.decisionText,
      phaseSource,
      fallbackText,
    ].where((value) => value.trim().isNotEmpty).join('\n');
    final queryTokens = _tokens(query);
    final selected = <_SelectedDelta>[];

    for (final entry in deltaState.active) {
      final score = _matchScore(entry.fact, queryTokens);
      if (score <= 0) {
        continue;
      }
      selected.add(
        _SelectedDelta(
          id: entry.id,
          fact: entry.fact,
          intensity: entry.intensity,
          status: entry.status,
          score: score,
        ),
      );
    }

    for (final entry in deltaState.archived) {
      final fact = (entry.archivedSummary ?? entry.fact).trim();
      final score = _matchScore(fact, queryTokens);
      if (score <= 0) {
        continue;
      }
      selected.add(
        _SelectedDelta(
          id: entry.id,
          fact: fact,
          intensity: 1,
          status: entry.status,
          score: score,
        ),
      );
    }

    selected.sort((left, right) {
      final byScore = right.score.compareTo(left.score);
      if (byScore != 0) {
        return byScore;
      }
      return right.intensity.compareTo(left.intensity);
    });
    return selected.take(4).toList();
  }

  Future<LocalSceneAdaptationPlan?> _tryLlmPlan({
    required String locale,
    required String phase,
    required LocalWorldEvent event,
    required String phaseSource,
    required List<_SelectedDelta> selection,
  }) async {
    final config = await loadConfig();
    final slot = config.agents['scene_adapter'];
    final access = slot == null ? null : _slotAccess(slot);
    if (slot == null || access == null) {
      return null;
    }

    try {
      final response = await llmClient.completeChat(
        provider: access.provider,
        apiKey: access.apiKey,
        model: slot.model,
        temperature: slot.temperature,
        apiBase: slot.apiBase,
        extraParams: slot.extraParams,
        messages: <Map<String, String>>[
          <String, String>{'role': 'system', 'content': _systemPrompt(locale)},
          <String, String>{
            'role': 'user',
            'content': _prompt(
              locale: locale,
              phase: phase,
              event: event,
              phaseSource: phaseSource,
              selection: selection,
            ),
          },
        ],
      );
      return _parsePlan(response);
    } catch (_) {
      return null;
    }
  }

  LocalSceneAdaptationPlan _heuristicPlan({
    required String locale,
    required String phase,
    required LocalWorldEvent event,
    required String phaseSource,
    required List<_SelectedDelta> selection,
  }) {
    final summary = _buildSummary(
      locale: locale,
      phase: phase,
      event: event,
      selection: selection,
    );
    final adaptations = selection.map((delta) {
      final strategies = delta.intensity >= 4
          ? const <String>['rewrite', 'addition']
          : const <String>['rewrite'];
      final target = locale.startsWith('en')
          ? '$phase scene details for ${event.goal}'
          : '${event.goal}的$phase场景细节';
      final plan = locale.startsWith('en')
          ? 'Keep the original beat of "${event.goal}", but make the narration acknowledge that ${delta.fact}.'
          : '保留“${event.goal}”这条原始事件节拍，同时让叙事明确体现：${delta.fact}。';
      final reasoning = locale.startsWith('en')
          ? 'Preserve the existing scene purpose and tension, then shift only the local detail needed to stay compatible with the changed world state.'
          : '先保留现有场景的目的与张力，再只调整那些必须顺应世界变化的局部细节。';
      return LocalSceneAdaptationItem(
        strategies: strategies,
        target: target,
        deltaSource: delta.id,
        original: _trimWithEllipsis(phaseSource.trim(), 180),
        plan: plan,
        nearestStateReasoning: reasoning,
        intensityGuidance: _intensityGuidance(locale, delta.intensity),
      );
    }).toList();

    return LocalSceneAdaptationPlan(
      deltaImpactSummary: summary,
      adaptations: adaptations,
    );
  }

  LocalSceneAdaptationPlan? _parsePlan(String raw) {
    final decoded = _parseJsonObject(raw);
    if (decoded == null) {
      return null;
    }

    final summary = decoded['delta_impact_summary']?.toString().trim() ?? '';
    final adaptations =
        (decoded['adaptations'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(LocalSceneAdaptationItem.fromJson)
            .where(
              (item) =>
                  item.target.trim().isNotEmpty &&
                  item.plan.trim().isNotEmpty,
            )
            .toList();
    if (summary.isEmpty || adaptations.isEmpty) {
      return null;
    }

    return LocalSceneAdaptationPlan(
      deltaImpactSummary: summary,
      adaptations: adaptations,
    );
  }

  String _buildSummary({
    required String locale,
    required String phase,
    required LocalWorldEvent event,
    required List<_SelectedDelta> selection,
  }) {
    final facts = selection
        .map((entry) => entry.fact)
        .where((value) => value.trim().isNotEmpty)
        .take(2)
        .join(' ');
    if (locale.startsWith('en')) {
      return 'The $phase scene around "${event.goal}" should now reflect this changed reality: $facts';
    }
    return '围绕“${event.goal}”的$phase场景现在必须体现这层变化：$facts';
  }

  String _adaptText({
    required String locale,
    required String phase,
    required String summary,
    required String original,
  }) {
    final normalizedSummary = summary.trim();
    final normalizedOriginal = original.trim();
    if (normalizedSummary.isEmpty) {
      return normalizedOriginal;
    }

    final lead = switch (phase) {
      'setup' => locale.startsWith('en')
          ? 'This scene no longer opens in a neutral state.'
          : '这个场景已经不再从一个中性的状态展开。',
      'confrontation' => locale.startsWith('en')
          ? 'The confrontation now carries visible consequences from what changed before.'
          : '这场对峙现在已经带上了先前变化留下的明显后果。',
      'resolution' => locale.startsWith('en')
          ? 'The outcome now has to absorb the altered reality.'
          : '这个结果现在必须吸收已经改变的现实。',
      _ => locale.startsWith('en')
          ? 'The scene should reflect the altered reality.'
          : '这个场景需要体现已经改变的现实。',
    };

    if (normalizedOriginal.isEmpty) {
      return '$lead $normalizedSummary'.trim();
    }
    return '$lead $normalizedSummary\n\n$normalizedOriginal'.trim();
  }

  String _intensityGuidance(String locale, int intensity) {
    if (intensity <= 2) {
      return locale.startsWith('en') ? 'brief pass' : '简要带过';
    }
    if (intensity >= 4) {
      return locale.startsWith('en') ? 'featured beat' : '重点刻画';
    }
    return locale.startsWith('en') ? 'normal detail' : '正常描写';
  }

  _SlotAccess? _slotAccess(LlmSlotConfig slot) {
    final provider = _provider(slot.model);
    final apiKey = provider == null
        ? null
        : store.getApiKeys()[provider]?.trim();
    if (provider == null ||
        apiKey == null ||
        apiKey.isEmpty ||
        !llmClient.supportsProvider(provider, apiBase: slot.apiBase)) {
      return null;
    }
    return _SlotAccess(provider: provider, apiKey: apiKey);
  }

  String? _provider(String model) {
    final slash = model.indexOf('/');
    if (slash <= 0) {
      return null;
    }
    return model.substring(0, slash);
  }

  String _systemPrompt(String locale) {
    final language = locale.startsWith('en')
        ? 'Return concise English JSON.'
        : 'Return concise Simplified Chinese JSON.';
    return '''
You are a scene adaptation planner for a local interactive fiction runtime.
$language
Adjust scene details to reflect active or archived world changes while preserving the original event beat.
Return only valid JSON in this shape:
{"delta_impact_summary":"...","adaptations":[{"strategies":["rewrite"],"target":"...","delta_source":"delta-001","original":"...","plan":"...","nearest_state_reasoning":"...","intensity_guidance":"normal detail"}]}
''';
  }

  String _prompt({
    required String locale,
    required String phase,
    required LocalWorldEvent event,
    required String phaseSource,
    required List<_SelectedDelta> selection,
  }) {
    return '''
<locale>$locale</locale>
<phase>$phase</phase>
<event_id>${event.id}</event_id>
<event_goal>${event.goal}</event_goal>
<event_decision_text>${event.decisionText}</event_decision_text>
<phase_source>
$phaseSource
</phase_source>
<relevant_deltas>
${jsonEncode(selection.map((entry) => entry.toJson()).toList())}
</relevant_deltas>
''';
  }

  Map<String, dynamic>? _parseJsonObject(String raw) {
    final normalized = raw
        .trim()
        .replaceFirst(RegExp(r'^```json\s*'), '')
        .replaceFirst(RegExp(r'^```\s*'), '')
        .replaceFirst(RegExp(r'\s*```$'), '')
        .trim();
    try {
      final decoded = jsonDecode(normalized);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } catch (_) {}
    return null;
  }

  int _matchScore(String text, Set<String> queryTokens) {
    if (text.trim().isEmpty || queryTokens.isEmpty) {
      return 0;
    }
    return _tokens(text).intersection(queryTokens).length;
  }

  Set<String> _tokens(String text) {
    final result = <String>{};
    for (final match in RegExp(
      r'[a-z0-9_]{3,}',
    ).allMatches(text.toLowerCase())) {
      result.add(match.group(0)!);
    }
    for (final match in RegExp(r'[\u4e00-\u9fff]{2,}').allMatches(text)) {
      result.add(match.group(0)!);
    }
    return result;
  }

  String _trimWithEllipsis(String value, int maxLength) {
    if (value.length <= maxLength) {
      return value;
    }
    return '${value.substring(0, maxLength)}...';
  }
}

class _SelectedDelta {
  const _SelectedDelta({
    required this.id,
    required this.fact,
    required this.intensity,
    required this.status,
    required this.score,
  });

  final String id;
  final String fact;
  final int intensity;
  final String status;
  final int score;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'fact': fact,
      'intensity': intensity,
      'status': status,
      'score': score,
    };
  }
}

class _SlotAccess {
  const _SlotAccess({required this.provider, required this.apiKey});

  final String provider;
  final String apiKey;
}

String _xmlEscape(String value) {
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}
