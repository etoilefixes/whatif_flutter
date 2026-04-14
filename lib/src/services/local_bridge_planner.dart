import 'dart:convert';

import '../models.dart';
import 'config_store.dart';
import 'integrated_llm_client.dart';
import 'local_delta_state.dart';
import 'local_worldpkg.dart';

class LocalBridgeConflict {
  const LocalBridgeConflict({
    required this.deltaId,
    required this.deltaFact,
    required this.deltaIntensity,
    required this.conflictingPremise,
    required this.conflictReason,
  });

  final String deltaId;
  final String deltaFact;
  final int deltaIntensity;
  final String conflictingPremise;
  final String conflictReason;
}

class LocalDeltaEvolution {
  const LocalDeltaEvolution({
    required this.originalDeltaId,
    required this.evolutionRationale,
    required this.evolvedFact,
    required this.evolvedIntensity,
  });

  final String originalDeltaId;
  final String evolutionRationale;
  final String evolvedFact;
  final int evolvedIntensity;

  factory LocalDeltaEvolution.fromJson(Map<String, dynamic> json) {
    return LocalDeltaEvolution(
      originalDeltaId: json['originalDeltaId'] as String? ?? '',
      evolutionRationale: json['evolutionRationale'] as String? ?? '',
      evolvedFact: json['evolvedFact'] as String? ?? '',
      evolvedIntensity: (json['evolvedIntensity'] as num?)?.toInt() ?? 1,
    );
  }
}

class LocalBridgePlan {
  const LocalBridgePlan({
    required this.conflicts,
    required this.deltaEvolutions,
    required this.bridgeNarrative,
  });

  final List<LocalBridgeConflict> conflicts;
  final List<LocalDeltaEvolution> deltaEvolutions;
  final String bridgeNarrative;
}

class LocalBridgePlanner {
  LocalBridgePlanner({
    required this.store,
    required this.llmClient,
    required this.loadConfig,
  });

  final ConfigStore store;
  final IntegratedLlmClient llmClient;
  final Future<LlmConfigMap> Function() loadConfig;

  Future<LocalBridgePlan?> plan({
    required String locale,
    required LocalDeltaStateManager deltaState,
    required LocalWorldEvent nextEvent,
    required String nextPhaseSource,
    required List<LocalTransitionCondition> preconditions,
    required String previousEvent,
  }) async {
    final conflicts = _detectConflicts(
      deltaState: deltaState,
      nextEvent: nextEvent,
      nextPhaseSource: nextPhaseSource,
      preconditions: preconditions,
    );
    if (conflicts.isEmpty) {
      return null;
    }

    final llmPlan = await _tryLlmPlan(
      locale: locale,
      conflicts: conflicts,
      nextPhaseSource: nextPhaseSource,
      preconditions: preconditions,
      previousEvent: previousEvent,
    );
    if (llmPlan != null) {
      return llmPlan;
    }
    return _heuristicPlan(
      locale: locale,
      conflicts: conflicts,
      nextEvent: nextEvent,
      nextPhaseSource: nextPhaseSource,
      preconditions: preconditions,
      previousEvent: previousEvent,
    );
  }

  List<LocalBridgeConflict> _detectConflicts({
    required LocalDeltaStateManager deltaState,
    required LocalWorldEvent nextEvent,
    required String nextPhaseSource,
    required List<LocalTransitionCondition> preconditions,
  }) {
    final query = <String>[
      nextEvent.goal,
      nextEvent.decisionText,
      nextPhaseSource,
      ...preconditions.map((condition) => condition.name),
      ...preconditions.map((condition) => condition.fromValue ?? ''),
    ].where((value) => value.trim().isNotEmpty).join('\n');
    final queryTokens = _tokens(query);

    final conflicts = <LocalBridgeConflict>[];
    for (final delta in deltaState.active) {
      final deltaTokens = _tokens(delta.fact);
      final overlap = deltaTokens.intersection(queryTokens);
      if (overlap.isEmpty) {
        continue;
      }

      final premise = preconditions.isNotEmpty
          ? preconditions
                .map(
                  (condition) =>
                      '${condition.name} / ${condition.attribute} / ${condition.fromValue ?? ''}',
                )
                .join('; ')
          : nextPhaseSource;
      conflicts.add(
        LocalBridgeConflict(
          deltaId: delta.id,
          deltaFact: delta.fact,
          deltaIntensity: delta.intensity,
          conflictingPremise: premise,
          conflictReason:
              'Shared entities or states appear in both the active delta and the next event.',
        ),
      );
    }
    return conflicts;
  }

  Future<LocalBridgePlan?> _tryLlmPlan({
    required String locale,
    required List<LocalBridgeConflict> conflicts,
    required String nextPhaseSource,
    required List<LocalTransitionCondition> preconditions,
    required String previousEvent,
  }) async {
    final config = await loadConfig();
    final slot = config.agents['bridge_planner'];
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
              conflicts: conflicts,
              nextPhaseSource: nextPhaseSource,
              preconditions: preconditions,
              previousEvent: previousEvent,
            ),
          },
        ],
      );
      return _parsePlan(response, conflicts: conflicts);
    } catch (_) {
      return null;
    }
  }

  LocalBridgePlan _heuristicPlan({
    required String locale,
    required List<LocalBridgeConflict> conflicts,
    required LocalWorldEvent nextEvent,
    required String nextPhaseSource,
    required List<LocalTransitionCondition> preconditions,
    required String previousEvent,
  }) {
    final evolutions = conflicts.map((conflict) {
      final intensity = conflict.deltaIntensity > 1
          ? conflict.deltaIntensity - 1
          : 1;
      return LocalDeltaEvolution(
        originalDeltaId: conflict.deltaId,
        evolutionRationale: locale.startsWith('en')
            ? 'Keep the consequence active, but reshape it so the next event can still begin.'
            : '保留后果影响，但把它改写成能接入下一事件的状态。',
        evolvedFact: locale.startsWith('en')
            ? 'The aftermath of "${conflict.deltaFact}" still affects how "${nextEvent.goal}" unfolds.'
            : '“${conflict.deltaFact}”的余波仍在持续影响“${nextEvent.goal}”的展开。',
        evolvedIntensity: intensity,
      );
    }).toList();

    final bridgeNarrative = _heuristicNarrative(
      locale: locale,
      previousEvent: previousEvent,
      nextPhaseSource: nextPhaseSource,
      preconditions: preconditions,
      evolutions: evolutions,
    );
    return LocalBridgePlan(
      conflicts: conflicts,
      deltaEvolutions: evolutions,
      bridgeNarrative: bridgeNarrative,
    );
  }

  LocalBridgePlan? _parsePlan(
    String raw, {
    required List<LocalBridgeConflict> conflicts,
  }) {
    final decoded = _parseJsonObject(raw);
    if (decoded == null) {
      return null;
    }
    final bridgeNarrative =
        decoded['bridge_narrative']?.toString().trim() ?? '';
    if (bridgeNarrative.isEmpty) {
      return null;
    }

    final validIds = conflicts.map((entry) => entry.deltaId).toSet();
    final evolutions =
        (decoded['delta_evolutions'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map((entry) {
              final normalized = <String, dynamic>{
                'originalDeltaId':
                    entry['originalDeltaId'] ?? entry['original_delta_id'],
                'evolutionRationale':
                    entry['evolutionRationale'] ?? entry['evolution_rationale'],
                'evolvedFact': entry['evolvedFact'] ?? entry['evolved_fact'],
                'evolvedIntensity':
                    entry['evolvedIntensity'] ?? entry['evolved_intensity'],
              };
              return LocalDeltaEvolution.fromJson(normalized);
            })
            .where(
              (entry) =>
                  entry.originalDeltaId.isNotEmpty &&
                  validIds.contains(entry.originalDeltaId) &&
                  entry.evolvedFact.trim().isNotEmpty,
            )
            .toList();
    if (evolutions.isEmpty) {
      return null;
    }

    return LocalBridgePlan(
      conflicts: conflicts,
      deltaEvolutions: evolutions,
      bridgeNarrative: bridgeNarrative,
    );
  }

  String _heuristicNarrative({
    required String locale,
    required String previousEvent,
    required String nextPhaseSource,
    required List<LocalTransitionCondition> preconditions,
    required List<LocalDeltaEvolution> evolutions,
  }) {
    final previous = _trimWithEllipsis(
      previousEvent.replaceAll(RegExp(r'\s+'), ' ').trim(),
      180,
    );
    final preconditionHint = preconditions.isEmpty
        ? ''
        : preconditions
              .map((condition) => condition.fromValue ?? condition.name)
              .where((value) => value.trim().isNotEmpty)
              .take(2)
              .join(', ');
    final effects = evolutions
        .map((entry) => entry.evolvedFact)
        .take(2)
        .join(' ');

    if (locale.startsWith('en')) {
      final previousLine = previous.isEmpty ? '' : '$previous ';
      final preconditionLine = preconditionHint.isEmpty
          ? ''
          : 'What follows must still lead you back toward $preconditionHint. ';
      return '$previousLine$effects $preconditionLine$nextPhaseSource'.trim();
    }

    final previousLine = previous.isEmpty ? '' : '$previous ';
    final preconditionLine = preconditionHint.isEmpty
        ? ''
        : '接下来的变化仍会把你带回$preconditionHint。';
    return '$previousLine$effects $preconditionLine$nextPhaseSource'.trim();
  }

  _SlotAccess? _slotAccess(LlmSlotConfig slot) {
    final provider = _provider(slot.model);
    final creds = provider == null
        ? null
        : store.getProviderCredentials(provider);
    if (provider == null ||
        creds == null ||
        creds.apiKey.isEmpty ||
        !llmClient.supportsProvider(provider, apiBase: slot.apiBase ?? creds.apiUrl)) {
      return null;
    }
    return _SlotAccess(provider: provider, apiKey: creds.apiKey);
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
You are a bridge planner for a local interactive fiction runtime.
$language
Resolve conflicts between active world-change deltas and the next event preconditions.
Return only valid JSON:
{"delta_evolutions":[{"original_delta_id":"delta-001","evolution_rationale":"...","evolved_fact":"...","evolved_intensity":3}],"bridge_narrative":"..."}
''';
  }

  String _prompt({
    required List<LocalBridgeConflict> conflicts,
    required String nextPhaseSource,
    required List<LocalTransitionCondition> preconditions,
    required String previousEvent,
  }) {
    return '''
<conflicts>
${jsonEncode(conflicts.map((entry) => <String, dynamic>{'delta_id': entry.deltaId, 'delta_fact': entry.deltaFact, 'delta_intensity': entry.deltaIntensity, 'conflicting_premise': entry.conflictingPremise, 'conflict_reason': entry.conflictReason}).toList())}
</conflicts>
<preconditions>
${jsonEncode(preconditions.map((entry) => <String, dynamic>{'name': entry.name, 'type': entry.type, 'attribute': entry.attribute, 'from': entry.fromValue, 'granularity': entry.granularity}).toList())}
</preconditions>
<previous_event>
$previousEvent
</previous_event>
<next_phase_source>
$nextPhaseSource
</next_phase_source>
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

class _SlotAccess {
  const _SlotAccess({required this.provider, required this.apiKey});

  final String provider;
  final String apiKey;
}
