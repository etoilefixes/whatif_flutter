import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_client/src/models.dart';
import 'package:flutter_client/src/services/config_store.dart';
import 'package:flutter_client/src/services/integrated_llm_client.dart';
import 'package:flutter_client/src/services/local_delta_state.dart';
import 'package:flutter_client/src/services/local_deviation_agent.dart';

void main() {
  test(
    'local deviation agent falls back to heuristic world-change analysis',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final store = await ConfigStore.open(
        legacyPrefs: prefs,
        useInMemoryDatabase: true,
      );
      final llmClient = IntegratedLlmClient();
      addTearDown(llmClient.dispose);

      final agent = LocalDeviationAgent(
        store: store,
        llmClient: llmClient,
        loadConfig: () async => const LlmConfigMap(
          extractors: <String, LlmSlotConfig>{},
          agents: <String, LlmSlotConfig>{},
        ),
      );

      final deltaState = LocalDeltaStateManager()
        ..createDelta(
          fact: 'The garrison already distrusts the protagonist.',
          sourceEventId: 'event_0',
          createdTurn: 1,
          intensity: 2,
        );

      final analysis = await agent.analyze(
        LocalDeviationRequest(
          locale: 'en-US',
          eventId: 'event_1',
          eventGoal: 'Hold the mountain gate',
          importance: 'key',
          playerAction: 'burn the gate and leave',
          currentHistory: const <LocalDeviationHistoryEntry>[],
          deltaState: deltaState,
        ),
      );

      expect(analysis.isDeviation, isTrue);
      expect(analysis.hasWorldChange, isTrue);
      expect(analysis.release, isTrue);
      expect(analysis.guidanceMethod, 'consequence_foreshadow');
      expect(analysis.guidanceTone, 'fateful');
      expect(analysis.deltaFact, contains('burn the gate and leave'));
      expect(analysis.asPromptNote(locale: 'en-US'), contains('deltaFact'));
    },
  );
}
