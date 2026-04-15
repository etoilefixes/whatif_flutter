import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_client/src/models.dart';
import 'package:flutter_client/src/services/config_store.dart';
import 'package:flutter_client/src/services/integrated_llm_client.dart';
import 'package:flutter_client/src/services/local_backend_paths.dart';
import 'package:flutter_client/src/services/local_narrative_generator.dart';

void main() {
  test(
    'local narrative generator includes delta and agent notes in planner and writer prompts',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'api_keys': '{"dashscope":"test-key"}',
      });
      final prefs = await SharedPreferences.getInstance();
      final store = await ConfigStore.open(
        legacyPrefs: prefs,
        useInMemoryDatabase: true,
      );
      final tempRoot = await Directory.systemTemp.createTemp(
        'whatif_narrative_test_',
      );
      addTearDown(() async {
        if (tempRoot.existsSync()) {
          await tempRoot.delete(recursive: true);
        }
      });

      final fakeClient = _FakeLlmClient();
      final generator = LocalNarrativeGenerator(
        store: store,
        paths: LocalBackendPaths(
          rootDir: tempRoot,
          outputDir: Directory('${tempRoot.path}\\output'),
          savesDir: Directory('${tempRoot.path}\\saves'),
          llmConfigFile: null,
        ),
        llmClient: fakeClient,
        loadConfig: () async => const LlmConfigMap(
          extractors: <String, LlmSlotConfig>{},
          agents: <String, LlmSlotConfig>{
            'resolution_orchestrator': LlmSlotConfig(
              model: 'dashscope/qwen3.5-flash',
              temperature: 0.3,
              thinkingBudget: 0,
            ),
            'unified_writer': LlmSlotConfig(
              model: 'dashscope/qwen3.5-plus',
              temperature: 0.7,
              thinkingBudget: 0,
            ),
          },
        ),
      );

      final result = await generator.generate(
        const LocalNarrativeRequest(
          locale: 'en-US',
          phase: 'resolution',
          worldTitle: 'Test Story',
          eventId: 'event_1',
          eventType: 'interactive',
          eventGoal: 'Hold the mountain gate',
          turn: 2,
          phaseSource: 'For one heartbeat, the crisis eases.',
          fallbackText: 'Static fallback text',
          eventDecisionText: 'Hold the gate.',
          playerAction: 'burn the gate and leave',
          playerName: 'Lin Ye',
          previousStory: 'Midnight clouds press over the mountain gate.',
          historyContext:
              '<entry index="1">Earlier scouts reported fire.</entry>',
          memoryContext:
              '<event id="event_1" tags="Iron Gate">Mira once held the gate.</event>',
          entityContext: '<entity id="iron_gate" type="location">{}</entity>',
          preconditionsText:
              '- Lin Ye (character) must have location = mountain gate',
          deltaContext: '[Active world changes]\n- The gate is burning.',
          agentNotes:
              '[Action analysis]\n- hasWorldChange: true\n- guidanceHint: Lean into the irreversible fallout.',
          adaptationPlanText:
              '<adaptation_plan>\n<adaptation strategy="rewrite" intensity="featured beat" delta_source="delta-001">\n  <target>resolution scene details</target>\n  <plan>Reflect that the gate is burning.</plan>\n</adaptation>\n</adaptation_plan>',
        ),
      );

      expect(result, 'Generated final scene.');
      expect(fakeClient.calls, hasLength(2));
      expect(fakeClient.calls.first.provider, 'dashscope');
      expect(fakeClient.calls.first.model, 'dashscope/qwen3.5-flash');
      expect(fakeClient.calls.last.model, 'dashscope/qwen3.5-plus');
      expect(
        fakeClient.calls.first.messages.last['content'],
        contains('<agent_notes>'),
      );
      expect(
        fakeClient.calls.first.messages.last['content'],
        contains('[Active world changes]'),
      );
      expect(
        fakeClient.calls.last.messages.last['content'],
        contains('<player_action>\nburn the gate and leave\n</player_action>'),
      );
      expect(
        fakeClient.calls.last.messages.last['content'],
        contains(
          '<previous_story>\nMidnight clouds press over the mountain gate.\n</previous_story>',
        ),
      );
      expect(
        fakeClient.calls.last.messages.last['content'],
        contains(
          '<history_context>\n<entry index="1">Earlier scouts reported fire.</entry>\n</history_context>',
        ),
      );
      expect(
        fakeClient.calls.last.messages.last['content'],
        contains(
          '<memory_context>\n<event id="event_1" tags="Iron Gate">Mira once held the gate.</event>\n</memory_context>',
        ),
      );
      expect(
        fakeClient.calls.last.messages.last['content'],
        contains(
          '<entity_context>\n<entity id="iron_gate" type="location">{}</entity>\n</entity_context>',
        ),
      );
      expect(
        fakeClient.calls.last.messages.last['content'],
        contains(
          '<preconditions>\n- Lin Ye (character) must have location = mountain gate\n</preconditions>',
        ),
      );
      expect(
        fakeClient.calls.last.messages.last['content'],
        contains(
          '<delta_context>\n[Active world changes]\n- The gate is burning.\n</delta_context>',
        ),
      );
      expect(
        fakeClient.calls.last.messages.last['content'],
        contains(
          '<agent_notes>\n[Action analysis]\n- hasWorldChange: true\n- guidanceHint: Lean into the irreversible fallout.\n</agent_notes>',
        ),
      );
      expect(
        fakeClient.calls.last.messages.last['content'],
        contains('<adaptation_notes>'),
      );
      expect(
        fakeClient.calls.last.messages.last['content'],
        contains('delta-001'),
      );
      expect(
        fakeClient.calls.last.messages.last['content'],
        contains(
          '<writing_guidance>\nPlan a vivid, consequence-heavy resolution.\n</writing_guidance>',
        ),
      );
    },
  );
}

class _FakeLlmClient extends IntegratedLlmClient {
  final List<_RecordedCall> calls = <_RecordedCall>[];

  @override
  bool supportsProvider(String provider, {String? apiBase}) => true;

  @override
  Future<String> completeChat({
    required String provider,
    required String apiKey,
    required String model,
    required double temperature,
    required List<Map<String, String>> messages,
    String? apiBase,
    Map<String, dynamic> extraParams = const <String, dynamic>{},
  }) async {
    calls.add(
      _RecordedCall(provider: provider, model: model, messages: messages),
    );
    if (calls.length == 1) {
      return '{"writing_guidance":"Plan a vivid, consequence-heavy resolution."}';
    }
    return 'Generated final scene.';
  }
}

class _RecordedCall {
  const _RecordedCall({
    required this.provider,
    required this.model,
    required this.messages,
  });

  final String provider;
  final String model;
  final List<Map<String, String>> messages;
}
