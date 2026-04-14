import 'dart:io';
import 'dart:convert';

import '../models.dart';
import 'config_store.dart';
import 'integrated_llm_client.dart';
import 'local_backend_paths.dart';

class LocalNarrativeRequest {
  const LocalNarrativeRequest({
    required this.locale,
    required this.phase,
    required this.worldTitle,
    required this.eventId,
    required this.eventType,
    required this.eventGoal,
    required this.turn,
    required this.phaseSource,
    required this.fallbackText,
    this.eventDecisionText,
    this.playerAction,
    this.playerName,
    this.previousStory,
    this.historyContext,
    this.memoryContext,
    this.entityContext,
    this.preconditionsText,
    this.deltaContext,
    this.agentNotes,
    this.adaptationPlanText,
  });

  final String locale;
  final String phase;
  final String worldTitle;
  final String eventId;
  final String eventType;
  final String eventGoal;
  final int turn;
  final String phaseSource;
  final String fallbackText;
  final String? eventDecisionText;
  final String? playerAction;
  final String? playerName;
  final String? previousStory;
  final String? historyContext;
  final String? memoryContext;
  final String? entityContext;
  final String? preconditionsText;
  final String? deltaContext;
  final String? agentNotes;
  final String? adaptationPlanText;
}

class LocalNarrativeGenerator {
  LocalNarrativeGenerator({
    required this.store,
    required this.paths,
    required this.llmClient,
    required this.loadConfig,
  });

  final ConfigStore store;
  final LocalBackendPaths paths;
  final IntegratedLlmClient llmClient;
  final Future<LlmConfigMap> Function() loadConfig;

  String? _cachedWriterPrompt;

  Future<String?> generate(LocalNarrativeRequest request) async {
    final config = await loadConfig();
    final writerSlot = config.agents['unified_writer'];
    if (writerSlot == null) {
      return null;
    }

    final guidance = await _buildGuidance(request, config);
    final writerAccess = _slotAccess(writerSlot);
    if (writerAccess == null) {
      return null;
    }

    final systemPrompt = _writerSystemPrompt(
      locale: request.locale,
      protagonistName: request.playerName,
    );
    final userPrompt = _buildWriterPrompt(request, guidance);

    try {
      final generated = await llmClient.completeChat(
        provider: writerAccess.provider,
        apiKey: writerAccess.apiKey,
        model: writerSlot.model,
        temperature: writerSlot.temperature,
        apiBase: writerSlot.apiBase,
        extraParams: writerSlot.extraParams,
        messages: <Map<String, String>>[
          <String, String>{'role': 'system', 'content': systemPrompt},
          <String, String>{'role': 'user', 'content': userPrompt},
        ],
      );
      final normalized = generated.trim();
      return normalized.isEmpty ? null : normalized;
    } catch (_) {
      return null;
    }
  }

  Future<void> testProvider(String provider, String key) async {
    final config = await loadConfig();
    final slot = _slotForProvider(config, provider);
    await llmClient.testProvider(
      provider,
      key,
      apiBase: slot?.apiBase,
      model: slot?.model,
    );
  }

  Future<String> _buildGuidance(
    LocalNarrativeRequest request,
    LlmConfigMap config,
  ) async {
    final fallbackGuidance = _fallbackWritingGuidance(request);
    final plannerSlot = config.agents[_plannerSlotName(request.phase)];
    if (plannerSlot == null) {
      return fallbackGuidance;
    }

    final plannerAccess = _slotAccess(plannerSlot);
    if (plannerAccess == null) {
      return fallbackGuidance;
    }

    try {
      final response = await llmClient.completeChat(
        provider: plannerAccess.provider,
        apiKey: plannerAccess.apiKey,
        model: plannerSlot.model,
        temperature: plannerSlot.temperature,
        apiBase: plannerSlot.apiBase,
        extraParams: plannerSlot.extraParams,
        messages: <Map<String, String>>[
          <String, String>{
            'role': 'system',
            'content': _plannerSystemPrompt(request.locale),
          },
          <String, String>{
            'role': 'user',
            'content': _buildPlannerPrompt(request, fallbackGuidance),
          },
        ],
      );
      return _parsePlannerGuidance(response) ?? fallbackGuidance;
    } catch (_) {
      return fallbackGuidance;
    }
  }

  _SlotAccess? _slotAccess(LlmSlotConfig slot) {
    final provider = _resolveProvider(slot.model);
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

  LlmSlotConfig? _slotForProvider(LlmConfigMap config, String provider) {
    for (final slot in config.agents.values) {
      if (_resolveProvider(slot.model) == provider) {
        return slot;
      }
    }
    for (final slot in config.extractors.values) {
      if (_resolveProvider(slot.model) == provider) {
        return slot;
      }
    }
    return null;
  }

  String _plannerSlotName(String phase) {
    return switch (phase) {
      'setup' => 'setup_orchestrator',
      'confrontation' => 'confrontation_orchestrator',
      'resolution' => 'resolution_orchestrator',
      _ => 'setup_orchestrator',
    };
  }

  String? _resolveProvider(String model) {
    final slash = model.indexOf('/');
    if (slash <= 0) {
      return null;
    }
    return model.substring(0, slash);
  }

  String _writerSystemPrompt({
    required String locale,
    required String? protagonistName,
  }) {
    final basePrompt = _loadWriterPrompt();
    final protagonist = protagonistName?.trim().isNotEmpty == true
        ? protagonistName!.trim()
        : (locale.startsWith('en') ? 'the protagonist' : '主角');
    final aliases = locale.startsWith('en') ? 'none' : '无';
    return basePrompt
        .replaceAll('{protagonist}', protagonist)
        .replaceAll('{protagonist_aliases}', aliases);
  }

  String _buildWriterPrompt(LocalNarrativeRequest request, String guidance) {
    return '''
<phase>${request.phase}</phase>
<world_title>${request.worldTitle}</world_title>
<event_id>${request.eventId}</event_id>
<event_type>${request.eventType}</event_type>
<event_goal>${request.eventGoal}</event_goal>
<event_decision_text>${request.eventDecisionText ?? ''}</event_decision_text>
<turn>${request.turn}</turn>

<previous_story>
${request.previousStory ?? ''}
</previous_story>

<history_context>
${request.historyContext ?? ''}
</history_context>

<memory_context>
${request.memoryContext ?? ''}
</memory_context>

<entity_context>
${request.entityContext ?? ''}
</entity_context>

<preconditions>
${request.preconditionsText ?? ''}
</preconditions>

<delta_context>
${request.deltaContext ?? ''}
</delta_context>

<agent_notes>
${request.agentNotes ?? ''}
</agent_notes>

<adaptation_notes>
${request.adaptationPlanText ?? ''}
</adaptation_notes>

<phase_source>
${request.phaseSource}
</phase_source>

<player_action>
${request.playerAction ?? ''}
</player_action>

<writing_guidance>
$guidance
</writing_guidance>

<fallback_reference>
${request.fallbackText}
</fallback_reference>
''';
  }

  String _plannerSystemPrompt(String locale) {
    final languageInstruction = locale.startsWith('en')
        ? 'Return JSON using English guidance.'
        : 'Return JSON using Simplified Chinese guidance.';
    return '''
You are the scene orchestrator for WhatIf.
Read the scene context and produce concise writing guidance for the writer model.
$languageInstruction
Return only valid JSON in this shape:
{"writing_guidance":"..."}
''';
  }

  String _buildPlannerPrompt(
    LocalNarrativeRequest request,
    String fallbackGuidance,
  ) {
    return '''
<phase>${request.phase}</phase>
<world_title>${request.worldTitle}</world_title>
<event_id>${request.eventId}</event_id>
<event_type>${request.eventType}</event_type>
<event_goal>${request.eventGoal}</event_goal>
<event_decision_text>${request.eventDecisionText ?? ''}</event_decision_text>
<turn>${request.turn}</turn>

<previous_story>
${request.previousStory ?? ''}
</previous_story>

<history_context>
${request.historyContext ?? ''}
</history_context>

<memory_context>
${request.memoryContext ?? ''}
</memory_context>

<entity_context>
${request.entityContext ?? ''}
</entity_context>

<preconditions>
${request.preconditionsText ?? ''}
</preconditions>

<delta_context>
${request.deltaContext ?? ''}
</delta_context>

<agent_notes>
${request.agentNotes ?? ''}
</agent_notes>

<adaptation_notes>
${request.adaptationPlanText ?? ''}
</adaptation_notes>

<phase_source>
${request.phaseSource}
</phase_source>

<player_action>
${request.playerAction ?? ''}
</player_action>

<fallback_guidance>
$fallbackGuidance
</fallback_guidance>
''';
  }

  String _fallbackWritingGuidance(LocalNarrativeRequest request) {
    final languageInstruction = request.locale.startsWith('en')
        ? 'Write all output in English.'
        : 'Write all output in Simplified Chinese.';

    final phaseInstruction = switch (request.phase) {
      'setup' =>
        'Rewrite the source into an immersive second-person opening. Keep the scene beats, atmosphere, and immediate tension intact. Do not ask for player input yet.',
      'confrontation' =>
        'Write the confrontation so the player clearly feels pressure and available room to act. End at a natural decision point for the player.',
      'resolution' =>
        'Acknowledge the player action, narrate the immediate consequence, and land the scene cleanly without asking another question.',
      _ => 'Write the next scene naturally.',
    };

    return '$languageInstruction $phaseInstruction';
  }

  String? _parsePlannerGuidance(String raw) {
    final text = raw.trim();
    final fenced = text
        .replaceFirst(RegExp(r'^```json\s*'), '')
        .replaceFirst(RegExp(r'^```\s*'), '')
        .replaceFirst(RegExp(r'\s*```$'), '')
        .trim();

    try {
      final decoded = jsonDecode(fenced);
      if (decoded is Map<String, dynamic>) {
        final guidance = decoded['writing_guidance']?.toString().trim();
        if (guidance != null && guidance.isNotEmpty) {
          return guidance;
        }
      }
    } catch (_) {}

    return null;
  }

  String _loadWriterPrompt() {
    if (_cachedWriterPrompt != null) {
      return _cachedWriterPrompt!;
    }

    final file = File(
      '${paths.rootDir.path}${Platform.pathSeparator}backend${Platform.pathSeparator}runtime${Platform.pathSeparator}agents${Platform.pathSeparator}narrative_generation${Platform.pathSeparator}writers${Platform.pathSeparator}prompt.txt',
    );
    if (file.existsSync()) {
      _cachedWriterPrompt = file.readAsStringSync();
      return _cachedWriterPrompt!;
    }

    _cachedWriterPrompt = '''
You are the narrative voice for WhatIf, an interactive fiction game.
Always narrate in second person and keep the player immersed in the scene.
When a source passage is provided, preserve its plot beats while rewriting it as vivid narration.
When a player action is provided, reflect that action and move the scene forward naturally.
''';
    return _cachedWriterPrompt!;
  }
}

class _SlotAccess {
  const _SlotAccess({required this.provider, required this.apiKey});

  final String provider;
  final String apiKey;
}
