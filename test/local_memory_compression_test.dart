import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_client/src/models.dart';
import 'package:flutter_client/src/services/config_store.dart';
import 'package:flutter_client/src/services/integrated_llm_client.dart';
import 'package:flutter_client/src/services/local_memory_compression.dart';

void main() {
  test(
    'local memory compression creates l1 bundles and recalls relevant memory',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final store = await ConfigStore.open(
        legacyPrefs: prefs,
        useInMemoryDatabase: true,
      );
      final manager = LocalMemoryCompressionManager(
        store: store,
        llmClient: IntegratedLlmClient(),
        loadConfig: () async => const LlmConfigMap(
          extractors: <String, LlmSlotConfig>{},
          agents: <String, LlmSlotConfig>{},
        ),
      );

      for (var index = 1; index <= 10; index += 1) {
        await manager.compressEvent(
          locale: 'en-US',
          eventId: 'event_$index',
          eventContent:
              'Captain Mira holds Iron Gate during siege step $index. The silver key remains in her hand.',
        );
      }

      expect(manager.l0Summaries, hasLength(10));
      expect(manager.l1Summaries, hasLength(1));
      expect(manager.l1Summaries.first.covers, 'event_1-event_10');

      final context = manager.buildRecallContext(
        query: 'How did Mira defend Iron Gate with the silver key?',
        currentEventId: 'event_10',
      );
      expect(context, contains('<event id="event_1"'));
      expect(context, contains('Iron Gate'));
    },
  );
}
