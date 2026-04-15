import 'dart:convert';

enum AppPage { start, library, settings, gameplay }

enum AppReadyState { loading, needsConfig, ready, offline }

class VoiceConfig {
  const VoiceConfig({required this.enabled, required this.voice});

  final bool enabled;
  final String voice;

  factory VoiceConfig.defaults([String locale = 'zh-CN']) {
    return VoiceConfig(enabled: false, voice: defaultVoiceForLocale(locale));
  }

  factory VoiceConfig.fromJson(Map<String, dynamic> json) {
    return VoiceConfig(
      enabled: _asBool(json['enabled']) ?? false,
      voice:
          _asString(json['voice']) ??
          defaultVoiceForLocale(_asString(json['locale']) ?? 'zh-CN'),
    );
  }

  static String defaultVoiceForLocale(String locale) {
    return locale.startsWith('en')
        ? 'en-US-JennyNeural'
        : 'zh-CN-XiaoxiaoNeural';
  }

  Map<String, dynamic> toJson() {
    return {'enabled': enabled, 'voice': voice};
  }

  VoiceConfig copyWith({bool? enabled, String? voice}) {
    return VoiceConfig(
      enabled: enabled ?? this.enabled,
      voice: voice ?? this.voice,
    );
  }
}

class VoiceInfo {
  const VoiceInfo({
    required this.name,
    required this.gender,
    required this.friendlyName,
  });

  final String name;
  final String gender;
  final String friendlyName;

  factory VoiceInfo.fromJson(Map<String, dynamic> json) {
    return VoiceInfo(
      name: json['name'] as String? ?? '',
      gender: json['gender'] as String? ?? '',
      friendlyName: json['friendlyName'] as String? ?? '',
    );
  }
}

class LastPkg {
  const LastPkg({required this.filename, required this.name});

  final String filename;
  final String name;

  factory LastPkg.fromJson(Map<String, dynamic> json) {
    return LastPkg(
      filename: _asString(json['filename']) ?? '',
      name: _asString(json['name']) ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {'filename': filename, 'name': name};
  }
}

class WorldPkgInfo {
  const WorldPkgInfo({
    required this.name,
    required this.filename,
    required this.size,
    required this.hasCover,
  });

  final String name;
  final String filename;
  final int size;
  final bool hasCover;

  factory WorldPkgInfo.fromJson(Map<String, dynamic> json) {
    return WorldPkgInfo(
      name: json['name'] as String? ?? 'Unknown Package',
      filename: json['filename'] as String? ?? '',
      size: (json['size'] as num?)?.toInt() ?? 0,
      hasCover: json['hasCover'] as bool? ?? false,
    );
  }
}

class SaveInfo {
  const SaveInfo({
    required this.slot,
    required this.saveTime,
    required this.playerName,
    required this.currentPhase,
    required this.currentEventId,
    required this.totalTurns,
    required this.description,
    required this.worldpkgTitle,
  });

  final int slot;
  final String saveTime;
  final String playerName;
  final String? currentPhase;
  final String? currentEventId;
  final int totalTurns;
  final String description;
  final String worldpkgTitle;

  factory SaveInfo.fromJson(Map<String, dynamic> json) {
    return SaveInfo(
      slot: (json['slot'] as num?)?.toInt() ?? 0,
      saveTime: _asString(json['saveTime']) ?? '',
      playerName: _asString(json['playerName']) ?? '',
      currentPhase: _asString(json['currentPhase']),
      currentEventId: _asString(json['currentEventId']),
      totalTurns: (json['totalTurns'] as num?)?.toInt() ?? 0,
      description: _asString(json['description']) ?? '',
      worldpkgTitle: _asString(json['worldpkgTitle']) ?? '',
    );
  }
}

class LoadGameResponse {
  const LoadGameResponse({
    required this.text,
    required this.phase,
    required this.eventId,
    required this.turn,
  });

  final String text;
  final String? phase;
  final String? eventId;
  final int turn;

  factory LoadGameResponse.fromJson(Map<String, dynamic> json) {
    return LoadGameResponse(
      text: json['text'] as String? ?? '',
      phase: json['phase'] as String?,
      eventId: json['eventId'] as String?,
      turn: (json['turn'] as num?)?.toInt() ?? 0,
    );
  }
}

class EventInfo {
  const EventInfo({
    required this.id,
    required this.decisionText,
    required this.goal,
    required this.importance,
    required this.type,
    required this.hasImage,
  });

  final String id;
  final String decisionText;
  final String goal;
  final String importance;
  final String type;
  final bool hasImage;

  factory EventInfo.fromJson(Map<String, dynamic> json) {
    return EventInfo(
      id: json['id'] as String? ?? '',
      decisionText: json['decisionText'] as String? ?? '',
      goal: json['goal'] as String? ?? '',
      importance: json['importance'] as String? ?? 'normal',
      type: json['type'] as String? ?? 'interactive',
      hasImage: json['hasImage'] as bool? ?? false,
    );
  }
}

class GameState {
  const GameState({
    required this.phase,
    required this.event,
    required this.turn,
    required this.playerName,
    required this.awaitingNextEvent,
    required this.gameEnded,
  });

  final String? phase;
  final EventInfo? event;
  final int turn;
  final String? playerName;
  final bool awaitingNextEvent;
  final bool gameEnded;

  factory GameState.fromJson(Map<String, dynamic> json) {
    return GameState(
      phase: json['phase'] as String?,
      event: json['event'] is Map<String, dynamic>
          ? EventInfo.fromJson(json['event'] as Map<String, dynamic>)
          : null,
      turn: (json['turn'] as num?)?.toInt() ?? 0,
      playerName: json['playerName'] as String?,
      awaitingNextEvent: json['awaitingNextEvent'] as bool? ?? false,
      gameEnded: json['gameEnded'] as bool? ?? false,
    );
  }
}

class GameStateData {
  const GameStateData({
    required this.phase,
    required this.eventId,
    required this.turn,
    required this.awaitingNextEvent,
    required this.gameEnded,
    required this.eventHasImage,
  });

  final String? phase;
  final String? eventId;
  final int turn;
  final bool awaitingNextEvent;
  final bool gameEnded;
  final bool eventHasImage;

  factory GameStateData.fromJson(Map<String, dynamic> json) {
    return GameStateData(
      phase: json['phase'] as String?,
      eventId: json['eventId'] as String?,
      turn: (json['turn'] as num?)?.toInt() ?? 0,
      awaitingNextEvent: json['awaitingNextEvent'] as bool? ?? false,
      gameEnded: json['gameEnded'] as bool? ?? false,
      eventHasImage: json['eventHasImage'] as bool? ?? false,
    );
  }
}

class GameResumeState {
  const GameResumeState({
    required this.text,
    required this.phase,
    required this.eventId,
    required this.turn,
    required this.awaitingNextEvent,
    required this.gameEnded,
    required this.eventHasImage,
  });

  final String text;
  final String? phase;
  final String? eventId;
  final int turn;
  final bool awaitingNextEvent;
  final bool gameEnded;
  final bool eventHasImage;
}

class WorldPkgListResponse {
  const WorldPkgListResponse({required this.packages, required this.current});

  final List<WorldPkgInfo> packages;
  final String? current;

  factory WorldPkgListResponse.fromJson(Map<String, dynamic> json) {
    final packages = (json['packages'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(WorldPkgInfo.fromJson)
        .toList();
    return WorldPkgListResponse(
      packages: packages,
      current: json['current'] as String?,
    );
  }
}

class ModelProvider {
  const ModelProvider({
    required this.name,
    required this.apiKey,
    this.apiUrl,
    this.models = const <String>[],
    this.enabled = true,
  });

  final String name;
  final String apiKey;
  final String? apiUrl;
  final List<String> models;
  final bool enabled;

  bool get hasKey => apiKey.trim().isNotEmpty;
  bool get isUsable => enabled && hasKey;

  static const Map<String, String> defaultApiUrls = <String, String>{
    'openai': 'https://api.openai.com/v1',
    'deepseek': 'https://api.deepseek.com/v1',
    'siliconflow': 'https://api.siliconflow.cn/v1',
    'dashscope': 'https://dashscope.aliyuncs.com/compatible-mode/v1',
    'anthropic': 'https://api.anthropic.com/v1',
    'gemini': 'https://generativelanguage.googleapis.com/v1beta/openai',
    'volcengine': 'https://ark.cn-beijing.volces.com/api/coding/v3',
    'nvidia': 'https://integrate.api.nvidia.com/v1',
  };

  static const Map<String, List<String>> defaultModels = <String, List<String>>{
    'openai': <String>['gpt-4o-mini', 'gpt-4o', 'gpt-4.1-mini', 'gpt-4.1'],
    'deepseek': <String>['deepseek-chat', 'deepseek-reasoner'],
    'siliconflow': <String>[
      'deepseek-ai/DeepSeek-V3.2',
      'Qwen/Qwen3-Coder-30B-A3B-Instruct',
      'moonshotai/Kimi-K2.5',
    ],
    'dashscope': <String>['qwen3.5-flash', 'qwen3.5-plus', 'qwen-max'],
    'anthropic': <String>[
      'claude-sonnet-4-20250514',
      'claude-3-5-haiku-20241022',
    ],
    'gemini': <String>['gemini-2.0-flash', 'gemini-2.5-pro-preview-05-06'],
    'volcengine': <String>[
      'ark-code-latest',
      'doubao-seed-1.6',
      'deepseek-v3.2',
    ],
    'nvidia': <String>[
      'nvidia/llama-3.1-nemotron-nano-8b-v1',
      'meta/llama-3.1-8b-instruct',
    ],
  };

  static const Map<String, String> displayNames = <String, String>{
    'openai': 'OpenAI',
    'deepseek': 'DeepSeek',
    'siliconflow': 'SiliconFlow',
    'dashscope': 'DashScope',
    'anthropic': 'Anthropic',
    'gemini': 'Google Gemini',
    'volcengine': 'Volcengine Ark',
    'nvidia': 'NVIDIA',
    'custom': 'Custom',
  };

  static const List<String> knownProviders = <String>[
    'openai',
    'deepseek',
    'siliconflow',
    'dashscope',
    'anthropic',
    'gemini',
    'volcengine',
    'nvidia',
  ];

  static const List<String> presetProviderOrder = <String>[
    'openai',
    'deepseek',
    'siliconflow',
    'volcengine',
    'nvidia',
    'dashscope',
    'anthropic',
    'gemini',
    'custom',
  ];

  static String canonicalProviderName(String name) {
    return name.trim().toLowerCase();
  }

  static bool usesManagedApiUrl(String providerName) {
    return defaultApiUrls.containsKey(canonicalProviderName(providerName));
  }

  static String? fixedApiUrlFor(String providerName) {
    return defaultApiUrls[canonicalProviderName(providerName)];
  }

  static List<String> suggestedModelsFor(String providerName) {
    return defaultModels[canonicalProviderName(providerName)] ??
        const <String>[];
  }

  static String displayNameFor(String providerName) {
    final normalized = canonicalProviderName(providerName);
    return displayNames[normalized] ?? providerName.trim();
  }

  factory ModelProvider.fromJson(Map<String, dynamic> json) {
    final models = json['models'];
    return ModelProvider(
      name: _asString(json['name']) ?? '',
      apiKey: _asString(json['apiKey']) ?? '',
      apiUrl: _asString(json['apiUrl']),
      models: _asStringList(models),
      enabled: _asBool(json['enabled']) ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'apiKey': apiKey,
      if (apiUrl != null && apiUrl!.trim().isNotEmpty) 'apiUrl': apiUrl,
      if (models.isNotEmpty) 'models': models,
      'enabled': enabled,
    };
  }

  ModelProvider copyWith({
    String? name,
    String? apiKey,
    String? apiUrl,
    List<String>? models,
    bool? enabled,
  }) {
    return ModelProvider(
      name: name ?? this.name,
      apiKey: apiKey ?? this.apiKey,
      apiUrl: apiUrl ?? this.apiUrl,
      models: models ?? this.models,
      enabled: enabled ?? this.enabled,
    );
  }
}

class LlmSlotConfig {
  const LlmSlotConfig({
    required this.model,
    required this.temperature,
    required this.thinkingBudget,
    this.apiBase,
    this.extraParams = const <String, dynamic>{},
  });

  final String model;
  final double temperature;
  final int thinkingBudget;
  final String? apiBase;
  final Map<String, dynamic> extraParams;

  factory LlmSlotConfig.fromJson(Map<String, dynamic> json) {
    return LlmSlotConfig(
      model: _asString(json['model']) ?? '',
      temperature: (json['temperature'] as num?)?.toDouble() ?? 0,
      thinkingBudget: (json['thinking_budget'] as num?)?.toInt() ?? 0,
      apiBase: _asString(json['api_base']),
      extraParams: _asStringKeyedMap(json['extra_params']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'model': model,
      'temperature': temperature,
      'thinking_budget': thinkingBudget,
      if (apiBase != null && apiBase!.trim().isNotEmpty) 'api_base': apiBase,
      if (extraParams.isNotEmpty) 'extra_params': extraParams,
    };
  }

  LlmSlotConfig copyWith({
    String? model,
    double? temperature,
    int? thinkingBudget,
    String? apiBase,
    Map<String, dynamic>? extraParams,
  }) {
    return LlmSlotConfig(
      model: model ?? this.model,
      temperature: temperature ?? this.temperature,
      thinkingBudget: thinkingBudget ?? this.thinkingBudget,
      apiBase: apiBase ?? this.apiBase,
      extraParams: extraParams ?? this.extraParams,
    );
  }
}

class LlmConfigMap {
  const LlmConfigMap({required this.extractors, required this.agents});

  final Map<String, LlmSlotConfig> extractors;
  final Map<String, LlmSlotConfig> agents;

  factory LlmConfigMap.fromJson(Map<String, dynamic> json) {
    Map<String, LlmSlotConfig> parseSection(String key) {
      final section = _asStringKeyedMap(json[key]);
      return section.map(
        (name, value) =>
            MapEntry(name, LlmSlotConfig.fromJson(_asStringKeyedMap(value))),
      );
    }

    return LlmConfigMap(
      extractors: parseSection('extractors'),
      agents: parseSection('agents'),
    );
  }

  Map<String, dynamic> toJson() {
    Map<String, dynamic> encodeSection(Map<String, LlmSlotConfig> section) {
      return section.map((name, value) => MapEntry(name, value.toJson()));
    }

    return {
      'extractors': encodeSection(extractors),
      'agents': encodeSection(agents),
    };
  }

  LlmConfigMap copyWith({
    Map<String, LlmSlotConfig>? extractors,
    Map<String, LlmSlotConfig>? agents,
  }) {
    return LlmConfigMap(
      extractors: extractors ?? this.extractors,
      agents: agents ?? this.agents,
    );
  }

  LlmConfigMap updateSlot(
    String section,
    String slotName,
    LlmSlotConfig config,
  ) {
    if (section == 'extractors') {
      return copyWith(extractors: {...extractors, slotName: config});
    }
    return copyWith(agents: {...agents, slotName: config});
  }

  LlmConfigMap applyPreset(String model) {
    Map<String, LlmSlotConfig> apply(Map<String, LlmSlotConfig> section) {
      return section.map(
        (name, config) => MapEntry(name, config.copyWith(model: model)),
      );
    }

    return LlmConfigMap(extractors: apply(extractors), agents: apply(agents));
  }
}

class SseEvent {
  const SseEvent._({
    required this.type,
    this.text,
    this.message,
    this.state,
    this.audio,
    this.audioIndex,
  });

  final String type;
  final String? text;
  final String? message;
  final GameStateData? state;
  final String? audio;
  final int? audioIndex;

  const SseEvent.chunk(String text) : this._(type: 'chunk', text: text);

  const SseEvent.audio(String audio, int index)
    : this._(type: 'audio', audio: audio, audioIndex: index);

  const SseEvent.error(String message)
    : this._(type: 'error', message: message);

  const SseEvent.state(GameStateData state)
    : this._(type: 'state', state: state);

  const SseEvent.done() : this._(type: 'done');
}

Map<String, dynamic>? decodeJsonObject(String? raw) {
  if (raw == null || raw.isEmpty) {
    return null;
  }

  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return decoded.map((key, value) => MapEntry(key.toString(), value));
    }
  } catch (_) {
    return null;
  }
  return null;
}

String? _asString(Object? value) {
  if (value == null) {
    return null;
  }
  return value.toString();
}

bool? _asBool(Object? value) {
  if (value is bool) {
    return value;
  }
  if (value is num) {
    return value != 0;
  }
  if (value is String) {
    final normalized = value.trim().toLowerCase();
    if (normalized == 'true' || normalized == '1') {
      return true;
    }
    if (normalized == 'false' || normalized == '0') {
      return false;
    }
  }
  return null;
}

List<String> _asStringList(Object? value) {
  if (value is! List) {
    return const <String>[];
  }
  return value.map((item) => item.toString()).toList();
}

Map<String, dynamic> _asStringKeyedMap(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map(
      (key, nestedValue) => MapEntry(key.toString(), nestedValue),
    );
  }
  return const <String, dynamic>{};
}
