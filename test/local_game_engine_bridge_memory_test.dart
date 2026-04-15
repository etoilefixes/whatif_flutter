import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_client/src/models.dart';
import 'package:flutter_client/src/services/config_store.dart';
import 'package:flutter_client/src/services/integrated_llm_client.dart';
import 'package:flutter_client/src/services/local_backend_paths.dart';
import 'package:flutter_client/src/services/local_bridge_planner.dart';
import 'package:flutter_client/src/services/local_deviation_agent.dart';
import 'package:flutter_client/src/services/local_game_engine.dart';
import 'package:flutter_client/src/services/local_memory_compression.dart';
import 'package:flutter_client/src/services/local_narrative_generator.dart';
import 'package:flutter_client/src/services/local_worldpkg.dart';

void main() {
  test(
    'local game engine bridges conflicting next event and recalls compressed memory',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'whatif_bridge_memory_test_',
      );
      addTearDown(() async {
        if (tempRoot.existsSync()) {
          await tempRoot.delete(recursive: true);
        }
      });

      final wpkgFile = File('${tempRoot.path}\\bridge_story.wpkg')
        ..writeAsBytesSync(_buildBridgeWorldPkg());
      final world = LocalWorldPkg.load(wpkgFile);

      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final store = await ConfigStore.open(
        legacyPrefs: prefs,
        useInMemoryDatabase: true,
      );
      Future<LlmConfigMap> loadConfig() async => const LlmConfigMap(
        extractors: <String, LlmSlotConfig>{},
        agents: <String, LlmSlotConfig>{},
      );
      final generator = _RecordingNarrativeGenerator(
        store: store,
        paths: LocalBackendPaths(
          rootDir: tempRoot,
          outputDir: Directory('${tempRoot.path}\\output'),
          savesDir: Directory('${tempRoot.path}\\saves'),
          llmConfigFile: null,
        ),
      );
      final deviationAgent = LocalDeviationAgent(
        store: store,
        llmClient: IntegratedLlmClient(),
        loadConfig: loadConfig,
      );
      final memoryCompression = LocalMemoryCompressionManager(
        store: store,
        llmClient: IntegratedLlmClient(),
        loadConfig: loadConfig,
      );
      final bridgePlanner = LocalBridgePlanner(
        store: store,
        llmClient: IntegratedLlmClient(),
        loadConfig: loadConfig,
      );
      final engine = LocalGameEngine(
        savesDir: Directory('${tempRoot.path}\\saves'),
        narrativeGenerator: generator,
        deviationAgent: deviationAgent,
        memoryCompression: memoryCompression,
        bridgePlanner: bridgePlanner,
      );
      engine.setWorld(world);

      await engine.startGame(lang: 'en-US').toList();
      await engine.continueGame(lang: 'en-US').toList();
      await engine
          .submitAction('burn Iron Gate and leave', lang: 'en-US')
          .toList();

      final bridgeEvents = await engine.continueGame(lang: 'en-US').toList();
      final bridgeText = bridgeEvents
          .where((event) => event.type == 'chunk')
          .map((event) => event.text ?? '')
          .join();

      expect(bridgeText, contains('Iron Gate'));
      expect(memoryCompression.l0Summaries, hasLength(1));
      await engine.waitForPrefetch();
      expect(generator.requests, hasLength(4));
      final prefetchedConfrontation = generator.requests.last;
      expect(prefetchedConfrontation.eventId, 'event_2');
      expect(prefetchedConfrontation.memoryContext, contains('event_1'));
      expect(prefetchedConfrontation.memoryContext, contains('Iron Gate'));

      await engine.continueGame(lang: 'en-US').toList();
      expect(generator.requests, hasLength(4));
    },
  );
}

class _RecordingNarrativeGenerator extends LocalNarrativeGenerator {
  _RecordingNarrativeGenerator({required super.store, required super.paths})
    : super(
        llmClient: IntegratedLlmClient(),
        loadConfig: () async => const LlmConfigMap(
          extractors: <String, LlmSlotConfig>{},
          agents: <String, LlmSlotConfig>{},
        ),
      );

  final List<LocalNarrativeRequest> requests = <LocalNarrativeRequest>[];

  @override
  Future<String?> generate(LocalNarrativeRequest request) async {
    requests.add(request);
    return 'Narrated ${request.phase} for ${request.eventId}';
  }
}

List<int> _buildBridgeWorldPkg() {
  final archive = Archive()
    ..addFile(
      _jsonFile('metadata.json', <String, dynamic>{
        'title': 'Bridge Story',
        'source_file': 'bridge.txt',
        'total_characters': 220,
        'total_sentences': 6,
        'event_count': 2,
        'character_count': 1,
        'location_count': 1,
        'item_count': 1,
        'knowledge_count': 0,
        'transition_count': 1,
        'created_at': DateTime.now().toIso8601String(),
      }),
    )
    ..addFile(
      _jsonFile('source/sentences.json', <String, dynamic>{
        'total_sentences': 6,
        'total_characters': 220,
        'sentences': <Map<String, dynamic>>[
          <String, dynamic>{
            'index': 1,
            'text': 'Captain Mira rushed to Iron Gate before dawn.',
            'start': 0,
            'end': 44,
          },
          <String, dynamic>{
            'index': 2,
            'text': 'Enemy scouts gathered below the wall.',
            'start': 45,
            'end': 83,
          },
          <String, dynamic>{
            'index': 3,
            'text': 'The silver key shook in Mira\'s hand.',
            'start': 84,
            'end': 123,
          },
          <String, dynamic>{
            'index': 4,
            'text': 'Smoke rolled across Iron Gate after the fire.',
            'start': 124,
            'end': 171,
          },
          <String, dynamic>{
            'index': 5,
            'text': 'The guards searched the damaged battlements.',
            'start': 172,
            'end': 218,
          },
          <String, dynamic>{
            'index': 6,
            'text': 'Mira had to decide who could still hold the line.',
            'start': 219,
            'end': 272,
          },
        ],
      }),
    )
    ..addFile(
      _jsonFile('events/events.json', <String, dynamic>{
        'events': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'event_1',
            'type': 'interactive',
            'goal': 'Defend Iron Gate',
            'sentence_range': <int>[1, 3],
            'importance': 'key',
            'decision_text': 'Decide how to defend Iron Gate.',
            'phases': <String, dynamic>{
              'setup': <String, dynamic>{
                'sentence_range': <int>[1, 1],
                'description': '',
                'decision_text':
                    'Captain Mira rushed to Iron Gate before dawn.',
              },
              'confrontation': <String, dynamic>{
                'sentence_range': <int>[2, 2],
                'description': '',
                'decision_text': 'Enemy scouts gathered below the wall.',
              },
              'resolution': <String, dynamic>{
                'sentence_range': <int>[3, 3],
                'description': '',
                'decision_text': 'The silver key shook in Mira\'s hand.',
              },
            },
          },
          <String, dynamic>{
            'id': 'event_2',
            'type': 'interactive',
            'goal': 'Rally the survivors at Iron Gate',
            'sentence_range': <int>[4, 6],
            'importance': 'key',
            'decision_text': 'Decide how to rally the damaged gate.',
            'phases': <String, dynamic>{
              'setup': <String, dynamic>{
                'sentence_range': <int>[4, 4],
                'description': '',
                'decision_text':
                    'Smoke rolled across Iron Gate after the fire.',
              },
              'confrontation': <String, dynamic>{
                'sentence_range': <int>[5, 5],
                'description': '',
                'decision_text': 'The guards searched the damaged battlements.',
              },
              'resolution': <String, dynamic>{
                'sentence_range': <int>[6, 6],
                'description': '',
                'decision_text':
                    'Mira had to decide who could still hold the line.',
              },
            },
          },
        ],
      }),
    )
    ..addFile(
      _jsonFile('lorebook/characters.json', <String, dynamic>{
        'characters': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'mira',
            'name': 'Mira',
            'aliases': <String>['Captain Mira'],
            'importance': 'protagonist',
            'identity': <String, dynamic>{'role': 'Captain'},
            'relationships': <List<dynamic>>[],
            'dialogue_examples': <List<dynamic>>[],
          },
        ],
      }),
    )
    ..addFile(
      _jsonFile('lorebook/locations.json', <String, dynamic>{
        'locations': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'iron_gate',
            'name': 'Iron Gate',
            'aliases': <String>[],
            'importance': 'key',
            'type': 'building',
            'parent_location': null,
            'description': <String, dynamic>{
              'overview': 'The city\'s main defensive gate.',
            },
            'connected_to': <List<dynamic>>[],
          },
        ],
      }),
    )
    ..addFile(
      _jsonFile('lorebook/items.json', <String, dynamic>{
        'items': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'silver_key',
            'name': 'silver key',
            'aliases': <String>[],
            'importance': 'key',
            'category': 'key_item',
            'description': <String, dynamic>{'appearance': 'A silver key.'},
            'function': <String, dynamic>{'primary_use': 'Open the gate.'},
            'significance': <String, dynamic>{
              'narrative_role': 'Controls access.',
            },
          },
        ],
      }),
    )
    ..addFile(
      _jsonFile('lorebook/knowledge.json', <String, dynamic>{
        'knowledge': <Map<String, dynamic>>[],
      }),
    )
    ..addFile(
      _jsonFile('transitions/transitions.json', <String, dynamic>{
        'transitions': <Map<String, dynamic>>[
          <String, dynamic>{
            'event_id': 'event_2',
            'preconditions': <Map<String, dynamic>>[
              <String, dynamic>{
                'name': 'Mira',
                'type': 'character',
                'attribute': '\u5730\u70b9',
                'from': 'Iron Gate',
                'granularity': 'named',
              },
            ],
            'effects': <Map<String, dynamic>>[],
          },
        ],
      }),
    );

  return ZipEncoder().encode(archive);
}

ArchiveFile _jsonFile(String name, Map<String, dynamic> json) {
  final bytes = utf8.encode(jsonEncode(json));
  return ArchiveFile(name, bytes.length, bytes);
}
