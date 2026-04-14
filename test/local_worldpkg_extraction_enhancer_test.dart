import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_client/src/models.dart';
import 'package:flutter_client/src/services/config_store.dart';
import 'package:flutter_client/src/services/integrated_llm_client.dart';
import 'package:flutter_client/src/services/local_lorebook_builder.dart';
import 'package:flutter_client/src/services/local_worldpkg_extraction_enhancer.dart';

void main() {
  test('local LLM extraction enhancer refines events and lorebook', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'api_keys': '{"dashscope":"test-key"}',
    });
    final prefs = await SharedPreferences.getInstance();
    final store = ConfigStore(prefs);
    final fakeClient = _FakeLlmClient();

    final enhancer = LocalLlmWorldPkgExtractionEnhancer(
      store: store,
      llmClient: fakeClient,
      loadConfig: () async => const LlmConfigMap(
        extractors: <String, LlmSlotConfig>{
          'event_extractor': LlmSlotConfig(
            model: 'dashscope/event-model',
            temperature: 0.2,
            thinkingBudget: 0,
          ),
          'decision_text_extractor': LlmSlotConfig(
            model: 'dashscope/decision-model',
            temperature: 0.2,
            thinkingBudget: 0,
          ),
          'lorebook_extractor': LlmSlotConfig(
            model: 'dashscope/lore-model',
            temperature: 0.2,
            thinkingBudget: 0,
          ),
        },
        agents: <String, LlmSlotConfig>{},
      ),
    );

    final heuristicLorebook = LocalLorebookBuildResult(
      characters: <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'protagonist',
          'name': 'Protagonist',
          'aliases': <String>[],
          'importance': 'protagonist',
          'identity': <String, dynamic>{'role': 'Story Protagonist'},
          'relationships': <List<dynamic>>[],
          'dialogue_examples': <List<dynamic>>[],
        },
      ],
      locations: const <Map<String, dynamic>>[],
      items: const <Map<String, dynamic>>[],
      knowledge: const <Map<String, dynamic>>[],
    );

    final heuristicEvents = <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 'event_1',
        'type': 'interactive',
        'goal': 'Original goal',
        'sentence_range': <int>[1, 4],
        'importance': 'normal',
        'decision_text': 'Original decision',
        'phases': <String, dynamic>{
          'setup': <String, dynamic>{
            'sentence_range': <int>[1, 1],
            'description': '',
            'decision_text': 'Setup original',
          },
          'confrontation': <String, dynamic>{
            'sentence_range': <int>[2, 3],
            'description': '',
            'decision_text': 'Confrontation original',
          },
          'resolution': <String, dynamic>{
            'sentence_range': <int>[4, 4],
            'description': '',
            'decision_text': 'Resolution original',
          },
        },
      },
    ];

    final result = await enhancer.enhance(
      locale: 'en-US',
      title: 'Test Story',
      fullText:
          'Captain Mira gripped the silver key at Iron Gate. Jon shouted from Black Tower that the rebels would arrive by dawn.',
      sentences: const <String>[
        'Captain Mira gripped the silver key at Iron Gate.',
        'Jon shouted from Black Tower that the rebels would arrive by dawn.',
        'Mira warned Jon that the gate must stay closed.',
        'Smoke rose beyond Iron Gate as enemy drums rolled.',
      ],
      heuristicEvents: heuristicEvents,
      heuristicLorebook: heuristicLorebook,
    );

    expect(result, isNotNull);
    expect(result!.events, hasLength(1));
    expect(result.events.first['goal'], 'Protect Iron Gate before dawn.');
    expect(result.events.first['importance'], 'key');
    expect(result.events.first['decision_text'], 'Compressed summary 1');
    expect(result.events.first['soft_guide_hints'], isNotEmpty);

    final phases = result.events.first['phases'] as Map<String, dynamic>;
    expect(
      (phases['setup'] as Map<String, dynamic>)['decision_text'],
      'Compressed summary 2',
    );
    expect(
      (phases['confrontation'] as Map<String, dynamic>)['decision_text'],
      'Compressed summary 3',
    );
    expect(
      (phases['resolution'] as Map<String, dynamic>)['decision_text'],
      'Compressed summary 4',
    );

    expect(
      result.lorebook.characters
          .map((entry) => entry['name'] as String)
          .toSet(),
      containsAll(<String>{'Mira', 'Jon'}),
    );
    expect(
      result.lorebook.locations.map((entry) => entry['name'] as String).toSet(),
      contains('Iron Gate'),
    );
    expect(
      result.lorebook.items.map((entry) => entry['name'] as String).toSet(),
      contains('silver key'),
    );
    expect(result.lorebook.knowledge, isNotEmpty);
  });

  test(
    'local LLM extraction enhancer accepts changed segmentation and normalizes malformed phases',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'api_keys': '{"dashscope":"test-key"}',
      });
      final prefs = await SharedPreferences.getInstance();
      final store = ConfigStore(prefs);
      final client = _SequenceLlmClient(<String, List<String>>{
        'dashscope/event-model': <String>[
          '''
{"events":[{"id":"Arrival At Gate","type":"narrative","goal":"Introduce the defenders at the gate.","sentence_range":[1,2],"importance":"normal","decision_text":"Arrival raw summary","narrative":"The defenders gather as the threat becomes visible."},{"id":"The Siege","type":"interactive","goal":"Choose how to defend Iron Gate.","sentence_range":[3,5],"importance":"key","soft_guide_hints":["If the player stalls, reinforce that the wall will not hold for long."],"phases":{"setup":{"sentence_range":[3,3],"description":"The first alarms echo over the wall.","decision_text":"Setup raw"},"confrontation":{"description":"The commander must commit to a risky defense."},"resolution":{"sentence_range":[5,5],"description":"The city lives or falls with the choice.","decision_text":"Resolution raw"}}}]}
''',
        ],
        'dashscope/decision-model': <String>[
          'Segment summary 1',
          'Segment summary 2',
          'Segment summary 3',
          'Segment summary 4',
          'Segment summary 5',
        ],
      });

      final enhancer = LocalLlmWorldPkgExtractionEnhancer(
        store: store,
        llmClient: client,
        loadConfig: () async => const LlmConfigMap(
          extractors: <String, LlmSlotConfig>{
            'event_extractor': LlmSlotConfig(
              model: 'dashscope/event-model',
              temperature: 0.2,
              thinkingBudget: 0,
            ),
            'decision_text_extractor': LlmSlotConfig(
              model: 'dashscope/decision-model',
              temperature: 0.2,
              thinkingBudget: 0,
            ),
          },
          agents: <String, LlmSlotConfig>{},
        ),
      );

      final result = await enhancer.enhance(
        locale: 'en-US',
        title: 'Iron Gate',
        fullText:
            'Captain Mira reached Iron Gate before dawn. Jon saw fires beyond the hills. The first ram hit the wall. Mira ordered the archers to hold. The city waited for her next command.',
        sentences: const <String>[
          'Captain Mira reached Iron Gate before dawn.',
          'Jon saw fires beyond the hills.',
          'The first ram hit the wall.',
          'Mira ordered the archers to hold.',
          'The city waited for her next command.',
        ],
        heuristicEvents: <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'event_1',
            'type': 'interactive',
            'goal': 'Original heuristic goal',
            'sentence_range': <int>[1, 5],
            'importance': 'key',
            'decision_text': 'Original heuristic decision',
            'phases': <String, dynamic>{
              'setup': <String, dynamic>{
                'sentence_range': <int>[1, 2],
                'description': '',
                'decision_text': 'Setup heuristic',
              },
              'confrontation': <String, dynamic>{
                'sentence_range': <int>[3, 4],
                'description': '',
                'decision_text': 'Confrontation heuristic',
              },
              'resolution': <String, dynamic>{
                'sentence_range': <int>[5, 5],
                'description': '',
                'decision_text': 'Resolution heuristic',
              },
            },
          },
        ],
        heuristicLorebook: const LocalLorebookBuildResult(
          characters: <Map<String, dynamic>>[],
          locations: <Map<String, dynamic>>[],
          items: <Map<String, dynamic>>[],
          knowledge: <Map<String, dynamic>>[],
        ),
      );

      expect(result, isNotNull);
      expect(result!.events, hasLength(2));

      final firstEvent = result.events.first;
      expect(firstEvent['id'], 'arrival_at_gate');
      expect(firstEvent['type'], 'narrative');
      expect(firstEvent['sentence_range'], <int>[1, 2]);
      expect(firstEvent['decision_text'], 'Segment summary 1');

      final secondEvent = result.events[1];
      expect(secondEvent['id'], 'the_siege');
      expect(secondEvent['type'], 'interactive');
      expect(secondEvent['sentence_range'], <int>[3, 5]);
      expect(secondEvent['decision_text'], 'Segment summary 2');
      expect(secondEvent['soft_guide_hints'], isNotEmpty);

      final phases = secondEvent['phases'] as Map<String, dynamic>;
      expect((phases['setup'] as Map<String, dynamic>)['sentence_range'], <int>[
        3,
        3,
      ]);
      expect(
        (phases['confrontation'] as Map<String, dynamic>)['sentence_range'],
        <int>[4, 4],
      );
      expect(
        (phases['resolution'] as Map<String, dynamic>)['sentence_range'],
        <int>[5, 5],
      );
      expect(
        (phases['setup'] as Map<String, dynamic>)['decision_text'],
        'Segment summary 3',
      );
      expect(
        (phases['confrontation'] as Map<String, dynamic>)['decision_text'],
        'Segment summary 4',
      );
      expect(
        (phases['resolution'] as Map<String, dynamic>)['decision_text'],
        'Segment summary 5',
      );
    },
  );

  test(
    'local LLM extraction enhancer falls back to heuristic events when segmentation is invalid',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'api_keys': '{"dashscope":"test-key"}',
      });
      final prefs = await SharedPreferences.getInstance();
      final store = ConfigStore(prefs);
      final client = _SequenceLlmClient(<String, List<String>>{
        'dashscope/event-model': <String>[
          '''
{"events":[{"id":"broken_1","type":"interactive","goal":"Broken","sentence_range":[1,3],"importance":"key"},{"id":"broken_2","type":"interactive","goal":"Broken","sentence_range":[3,4],"importance":"key"}]}
''',
        ],
      });

      final enhancer = LocalLlmWorldPkgExtractionEnhancer(
        store: store,
        llmClient: client,
        loadConfig: () async => const LlmConfigMap(
          extractors: <String, LlmSlotConfig>{
            'event_extractor': LlmSlotConfig(
              model: 'dashscope/event-model',
              temperature: 0.2,
              thinkingBudget: 0,
            ),
          },
          agents: <String, LlmSlotConfig>{},
        ),
      );

      final heuristicEvents = <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'event_1',
          'type': 'interactive',
          'goal': 'Hold the gate',
          'sentence_range': <int>[1, 2],
          'importance': 'key',
          'decision_text': 'Hold the gate now.',
          'phases': <String, dynamic>{
            'setup': <String, dynamic>{
              'sentence_range': <int>[1, 1],
              'description': '',
              'decision_text': 'Setup',
            },
            'confrontation': <String, dynamic>{
              'sentence_range': <int>[2, 2],
              'description': '',
              'decision_text': 'Confrontation',
            },
            'resolution': <String, dynamic>{
              'sentence_range': null,
              'description': '',
              'decision_text': 'Resolution',
            },
          },
        },
        <String, dynamic>{
          'id': 'event_2',
          'type': 'interactive',
          'goal': 'Survive the breach',
          'sentence_range': <int>[3, 4],
          'importance': 'key',
          'decision_text': 'Face the breach.',
          'phases': <String, dynamic>{
            'setup': <String, dynamic>{
              'sentence_range': <int>[3, 3],
              'description': '',
              'decision_text': 'Setup two',
            },
            'confrontation': <String, dynamic>{
              'sentence_range': <int>[4, 4],
              'description': '',
              'decision_text': 'Confrontation two',
            },
            'resolution': <String, dynamic>{
              'sentence_range': null,
              'description': '',
              'decision_text': 'Resolution two',
            },
          },
        },
      ];

      final result = await enhancer.enhance(
        locale: 'en-US',
        title: 'Fallback Story',
        fullText: 'One. Two. Three. Four.',
        sentences: const <String>['One.', 'Two.', 'Three.', 'Four.'],
        heuristicEvents: heuristicEvents,
        heuristicLorebook: const LocalLorebookBuildResult(
          characters: <Map<String, dynamic>>[],
          locations: <Map<String, dynamic>>[],
          items: <Map<String, dynamic>>[],
          knowledge: <Map<String, dynamic>>[],
        ),
      );

      expect(result, isNotNull);
      expect(result!.events, equals(heuristicEvents));
    },
  );
}

class _FakeLlmClient extends IntegratedLlmClient {
  int _decisionCounter = 0;

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
    if (model == 'dashscope/event-model') {
      return '''
{"events":[{"id":"event_1","type":"interactive","goal":"Protect Iron Gate before dawn.","importance":"key","decision_text":"Refined decision text","soft_guide_hints":["If the player hesitates, emphasize the danger at the gate."],"phases":{"setup":{"description":"The defenders realize the gate is in immediate danger.","decision_text":"Refined setup"},"confrontation":{"description":"Mira and Jon argue over how to respond.","decision_text":"Refined confrontation"},"resolution":{"description":"The choice will decide whether the gate holds.","decision_text":"Refined resolution"}}}]}
''';
    }

    if (model == 'dashscope/lore-model') {
      return '''
{"characters":[{"id":"protagonist","name":"Mira","aliases":["Captain Mira"],"importance":"protagonist","identity":{"role":"Captain"},"relationships":[],"dialogue_examples":["Mira warned Jon that the gate must stay closed."]},{"id":"character_1","name":"Jon","aliases":[],"importance":"supporting","identity":{"role":"Scout"},"relationships":[],"dialogue_examples":["Jon shouted from Black Tower that the rebels would arrive by dawn."]}],"locations":[{"id":"location_1","name":"Iron Gate","aliases":[],"importance":"key","type":"building","parent_location":null,"description":{"overview":"Iron Gate is the critical defensive chokepoint.","atmosphere":null,"visual_details":null,"sounds":null,"smells":null,"notable_features":null},"connected_to":[]}],"items":[{"id":"item_1","name":"silver key","aliases":[],"importance":"key","category":"key_item","description":{"appearance":"A silver key Mira keeps ready at the gate.","material":null,"size":null},"function":{"primary_use":"Unlocking progress","special_abilities":null,"limitations":null},"significance":{"narrative_role":"Controls access to the gate.","symbolic_meaning":null}}],"knowledge":[{"id":"knowledge_1","name":"The rebels will arrive by dawn","initial_holders":["character_1"],"description":"Jon shouted from Black Tower that the rebels would arrive by dawn."}]}
''';
    }

    if (model == 'dashscope/decision-model') {
      _decisionCounter += 1;
      return 'Compressed summary $_decisionCounter';
    }

    throw StateError('Unexpected model: $model');
  }
}

class _SequenceLlmClient extends IntegratedLlmClient {
  _SequenceLlmClient(this._responses);

  final Map<String, List<String>> _responses;

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
    final queue = _responses[model];
    if (queue == null || queue.isEmpty) {
      throw StateError('Unexpected model: $model');
    }
    return queue.removeAt(0);
  }
}
