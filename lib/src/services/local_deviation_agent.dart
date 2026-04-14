import 'dart:convert';

import '../models.dart';
import 'config_store.dart';
import 'integrated_llm_client.dart';
import 'local_delta_state.dart';

class LocalDeviationHistoryEntry {
  const LocalDeviationHistoryEntry({
    required this.playerAction,
    this.responseSummary,
    this.analysis,
  });

  final String playerAction;
  final String? responseSummary;
  final LocalDeviationAnalysis? analysis;

  factory LocalDeviationHistoryEntry.fromJson(Map<String, dynamic> json) {
    return LocalDeviationHistoryEntry(
      playerAction: json['playerAction'] as String? ?? '',
      responseSummary: json['responseSummary'] as String?,
      analysis: _mapValue(json['analysis']) == null
          ? null
          : LocalDeviationAnalysis.fromJson(_mapValue(json['analysis'])!),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'playerAction': playerAction,
      if (responseSummary != null) 'responseSummary': responseSummary,
      if (analysis != null) 'analysis': analysis!.toJson(),
    };
  }

  LocalDeviationHistoryEntry copyWith({
    String? playerAction,
    String? responseSummary,
    LocalDeviationAnalysis? analysis,
  }) {
    return LocalDeviationHistoryEntry(
      playerAction: playerAction ?? this.playerAction,
      responseSummary: responseSummary ?? this.responseSummary,
      analysis: analysis ?? this.analysis,
    );
  }
}

class LocalDeviationAnalysis {
  const LocalDeviationAnalysis({
    required this.scratch,
    required this.isDeviation,
    required this.hasWorldChange,
    required this.persistenceCount,
    required this.release,
    required this.guidanceMethod,
    required this.guidanceTone,
    required this.guidanceHint,
    this.deltaFact,
    this.deltaIntensity,
  });

  final String scratch;
  final bool isDeviation;
  final bool hasWorldChange;
  final int persistenceCount;
  final bool release;
  final String guidanceMethod;
  final String guidanceTone;
  final String guidanceHint;
  final String? deltaFact;
  final int? deltaIntensity;

  factory LocalDeviationAnalysis.fromJson(Map<String, dynamic> json) {
    return LocalDeviationAnalysis(
      scratch: json['scratch'] as String? ?? '',
      isDeviation: json['isDeviation'] as bool? ?? false,
      hasWorldChange: json['hasWorldChange'] as bool? ?? false,
      persistenceCount: (json['persistenceCount'] as num?)?.toInt() ?? 0,
      release: json['release'] as bool? ?? false,
      guidanceMethod: json['guidanceMethod'] as String? ?? 'none',
      guidanceTone: json['guidanceTone'] as String? ?? 'neutral',
      guidanceHint: json['guidanceHint'] as String? ?? '',
      deltaFact: json['deltaFact'] as String?,
      deltaIntensity: (json['deltaIntensity'] as num?)?.toInt(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'scratch': scratch,
      'isDeviation': isDeviation,
      'hasWorldChange': hasWorldChange,
      'persistenceCount': persistenceCount,
      'release': release,
      'guidanceMethod': guidanceMethod,
      'guidanceTone': guidanceTone,
      'guidanceHint': guidanceHint,
      if (deltaFact != null) 'deltaFact': deltaFact,
      if (deltaIntensity != null) 'deltaIntensity': deltaIntensity,
    };
  }

  String asPromptNote({required String locale}) {
    final lines = <String>[
      locale.startsWith('en') ? '[Action analysis]' : '[行动分析]',
      '- isDeviation: $isDeviation',
      '- hasWorldChange: $hasWorldChange',
      '- persistenceCount: $persistenceCount',
      '- guidanceMethod: $guidanceMethod',
      '- guidanceTone: $guidanceTone',
      '- guidanceHint: $guidanceHint',
    ];
    if (deltaFact != null && deltaFact!.trim().isNotEmpty) {
      lines.add('- deltaFact: ${deltaFact!.trim()}');
    }
    if (deltaIntensity != null) {
      lines.add('- deltaIntensity: $deltaIntensity');
    }
    return lines.join('\n');
  }
}

class LocalDeviationRequest {
  const LocalDeviationRequest({
    required this.locale,
    required this.eventId,
    required this.eventGoal,
    required this.importance,
    required this.playerAction,
    required this.currentHistory,
    required this.deltaState,
  });

  final String locale;
  final String eventId;
  final String eventGoal;
  final String importance;
  final String playerAction;
  final List<LocalDeviationHistoryEntry> currentHistory;
  final LocalDeltaStateManager deltaState;
}

class LocalDeviationAgent {
  LocalDeviationAgent({
    required this.store,
    required this.llmClient,
    required this.loadConfig,
  });

  final ConfigStore store;
  final IntegratedLlmClient llmClient;
  final Future<LlmConfigMap> Function() loadConfig;

  Future<LocalDeviationAnalysis> analyze(LocalDeviationRequest request) async {
    final llmAnalysis = await _tryLlmAnalysis(request);
    return llmAnalysis ?? _heuristicAnalysis(request);
  }

  Future<LocalDeviationAnalysis?> _tryLlmAnalysis(
    LocalDeviationRequest request,
  ) async {
    final config = await loadConfig();
    final slot = config.agents['deviation_controller'];
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
          <String, String>{
            'role': 'system',
            'content': _systemPrompt(request.locale),
          },
          <String, String>{'role': 'user', 'content': _prompt(request)},
        ],
      );
      return _parseAnalysis(response);
    } catch (_) {
      return null;
    }
  }

  LocalDeviationAnalysis _heuristicAnalysis(LocalDeviationRequest request) {
    final action = request.playerAction.trim();
    final normalizedAction = action.toLowerCase();
    final actionKeywords = _keywords(action);
    final goalKeywords = _keywords(request.eventGoal);
    final overlap = actionKeywords.intersection(goalKeywords);

    final worldChangeTriggers = <String>[
      'kill',
      'burn',
      'break',
      'steal',
      'betray',
      'leave',
      'destroy',
      'poison',
      'explode',
      '放火',
      '杀',
      '毁',
      '偷',
      '逃',
      '背叛',
      '烧',
      '炸',
      '毒',
    ];
    final hasWorldChange = worldChangeTriggers.any(
      (keyword) => normalizedAction.contains(keyword.toLowerCase()),
    );

    final isDeviation = hasWorldChange || overlap.isEmpty;
    final persistenceCount =
        request.currentHistory.length + (isDeviation ? 1 : 0);
    final release =
        isDeviation &&
        (hasWorldChange ||
            request.importance != 'key' ||
            persistenceCount >= 2);

    final guidanceHint = !isDeviation
        ? (request.locale.startsWith('en')
              ? 'Keep the response grounded in the original conflict.'
              : '让这一回合继续贴着原始冲突推进。')
        : hasWorldChange
        ? (request.locale.startsWith('en')
              ? 'This choice permanently changes the local reality.'
              : '这个选择会永久改变当前场景的现实。')
        : (request.locale.startsWith('en')
              ? 'The action bends away from the expected path.'
              : '这个行动正在把故事带离原本的路径。');

    final deltaFact = hasWorldChange
        ? _buildDeltaFact(
            locale: request.locale,
            action: action,
            goal: request.eventGoal,
          )
        : null;

    return LocalDeviationAnalysis(
      scratch: 'heuristic-analysis',
      isDeviation: isDeviation,
      hasWorldChange: hasWorldChange,
      persistenceCount: persistenceCount,
      release: release,
      guidanceMethod: hasWorldChange
          ? 'consequence_foreshadow'
          : (isDeviation ? 'character_reaction' : 'none'),
      guidanceTone: hasWorldChange
          ? 'fateful'
          : (isDeviation ? 'urgent' : 'neutral'),
      guidanceHint: guidanceHint,
      deltaFact: deltaFact,
      deltaIntensity: hasWorldChange ? 3 : null,
    );
  }

  String _buildDeltaFact({
    required String locale,
    required String action,
    required String goal,
  }) {
    if (locale.startsWith('en')) {
      return 'Because the player chose "$action", the situation around '
          '"$goal" has changed in a lasting way.';
    }
    return '由于玩家采取了“$action”，围绕“$goal”的局面已经发生了持久变化。';
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
    final languageInstruction = locale.startsWith('en')
        ? 'Return JSON fields in English.'
        : 'Return JSON fields in Simplified Chinese or English, but keep valid JSON.';
    return '''
You analyze whether a player action deviates from the current event
and whether it creates a persistent world change.
$languageInstruction
Return only valid JSON with these fields:
{"scratch":"","isDeviation":true,"hasWorldChange":true,"persistenceCount":1,"release":false,"guidanceMethod":"none","guidanceTone":"neutral","guidanceHint":"","deltaFact":null,"deltaIntensity":null}
''';
  }

  String _prompt(LocalDeviationRequest request) {
    final history = request.currentHistory.isEmpty
        ? '<empty/>'
        : request.currentHistory
              .map(
                (entry) =>
                    '- player: ${entry.playerAction}\n'
                    '  response: ${entry.responseSummary ?? ''}',
              )
              .join('\n');
    final deltaContext = request.deltaState.formatContext(
      locale: request.locale,
    );

    return '''
<event_id>${request.eventId}</event_id>
<goal>${request.eventGoal}</goal>
<importance>${request.importance}</importance>
<player_action>${request.playerAction}</player_action>

<history>
$history
</history>

<delta_context>
${deltaContext.isEmpty ? '<empty/>' : deltaContext}
</delta_context>
''';
  }

  LocalDeviationAnalysis? _parseAnalysis(String raw) {
    final text = raw
        .trim()
        .replaceFirst(RegExp(r'^```json\s*'), '')
        .replaceFirst(RegExp(r'^```\s*'), '')
        .replaceFirst(RegExp(r'\s*```$'), '')
        .trim();

    try {
      final decoded = jsonDecode(text);
      if (decoded is Map<String, dynamic>) {
        return LocalDeviationAnalysis.fromJson(decoded);
      }
      if (decoded is Map) {
        return LocalDeviationAnalysis.fromJson(
          decoded.map((key, value) => MapEntry(key.toString(), value)),
        );
      }
    } catch (_) {}
    return null;
  }

  Set<String> _keywords(String text) {
    final result = <String>{};
    for (final match in RegExp(
      r'[A-Za-z0-9]+',
    ).allMatches(text.toLowerCase())) {
      final word = match.group(0);
      if (word != null && word.length >= 3) {
        result.add(word);
      }
    }
    for (final match in RegExp(r'[\u4E00-\u9FFF]+').allMatches(text)) {
      final run = match.group(0);
      if (run == null || run.isEmpty) {
        continue;
      }
      if (run.length <= 2) {
        result.add(run);
        continue;
      }
      for (var index = 0; index < run.length - 1; index += 1) {
        result.add(run.substring(index, index + 2));
      }
    }
    return result;
  }
}

class _SlotAccess {
  const _SlotAccess({required this.provider, required this.apiKey});

  final String provider;
  final String apiKey;
}

Map<String, dynamic>? _mapValue(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map(
      (key, nestedValue) => MapEntry(key.toString(), nestedValue),
    );
  }
  return null;
}
