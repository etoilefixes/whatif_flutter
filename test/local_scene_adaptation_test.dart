import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_client/src/models.dart';
import 'package:flutter_client/src/services/config_store.dart';
import 'package:flutter_client/src/services/integrated_llm_client.dart';
import 'package:flutter_client/src/services/local_delta_state.dart';
import 'package:flutter_client/src/services/local_scene_adaptation.dart';
import 'package:flutter_client/src/services/local_worldpkg.dart';

void main() {
  test(
    'local scene adaptation planner builds heuristic plan and adapted text',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final store = ConfigStore(prefs);
      final planner = LocalSceneAdaptationPlanner(
        store: store,
        llmClient: IntegratedLlmClient(),
        loadConfig: () async => const LlmConfigMap(
          extractors: <String, LlmSlotConfig>{},
          agents: <String, LlmSlotConfig>{},
        ),
      );
      final deltaState = LocalDeltaStateManager()
        ..createDelta(
          fact: 'The council hall is already on fire.',
          sourceEventId: 'event_0',
          createdTurn: 1,
          intensity: 4,
        );

      final result = await planner.adapt(
        locale: 'en-US',
        phase: 'resolution',
        event: const LocalWorldEvent(
          id: 'event_1',
          type: 'interactive',
          goal: 'Secure the council hall',
          sentenceRange: <int>[1, 3],
          importance: 'key',
          decisionText: 'Decide how to secure the council hall.',
          image: null,
          phases: <String, LocalWorldPhase>{},
        ),
        phaseSource: 'A verdict settles over the hall.',
        fallbackText: 'You act, and the hall falls silent.',
        deltaState: deltaState,
      );

      expect(result, isNotNull);
      expect(result!.adaptedPhaseSource, contains('altered reality'));
      expect(result.adaptedPhaseSource, contains('council hall is already on fire'));
      expect(result.adaptationPlanText, contains('<adaptation_plan>'));
      expect(result.adaptationPlanText, contains('delta-001'));
      expect(result.adaptationPlanText, contains('Secure the council hall'));
    },
  );
}
