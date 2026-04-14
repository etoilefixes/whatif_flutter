import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_client/src/models.dart';
import 'package:flutter_client/src/services/config_store.dart';
import 'package:flutter_client/src/services/integrated_llm_client.dart';
import 'package:flutter_client/src/services/local_backend_paths.dart';
import 'package:flutter_client/src/services/local_game_engine.dart';
import 'package:flutter_client/src/services/local_narrative_generator.dart';
import 'package:flutter_client/src/services/local_worldpkg.dart';

void main() {
  test(
    'local game engine enriches narrative requests with lorebook and history context',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'whatif_engine_context_test_',
      );
      addTearDown(() async {
        if (tempRoot.existsSync()) {
          await tempRoot.delete(recursive: true);
        }
      });

      final wpkgFile = File('${tempRoot.path}\\context_story.wpkg')
        ..writeAsBytesSync(_buildContextWorldPkg());
      final world = LocalWorldPkg.load(wpkgFile);

      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final store = ConfigStore(prefs);
      final generator = _RecordingNarrativeGenerator(
        store: store,
        paths: LocalBackendPaths(
          rootDir: tempRoot,
          outputDir: Directory('${tempRoot.path}\\output'),
          savesDir: Directory('${tempRoot.path}\\saves'),
          llmConfigFile: null,
        ),
      );

      final engine = LocalGameEngine(
        savesDir: Directory('${tempRoot.path}\\saves'),
        narrativeGenerator: generator,
      );
      engine.setWorld(world);

      await engine.startGame(lang: 'en-US').toList();
      await engine.waitForPrefetch();
      expect(generator.requests, hasLength(2));
      final setupRequest = generator.requests[0];
      expect(setupRequest.entityContext, contains('Mira'));
      expect(setupRequest.entityContext, contains('Iron Gate'));
      expect(setupRequest.entityContext, contains('silver key'));
      expect(
        setupRequest.preconditionsText,
        contains('Mira (character) must have location = Iron Gate'),
      );
      expect(setupRequest.historyContext, isEmpty);

      await engine.continueGame(lang: 'en-US').toList();
      expect(generator.requests, hasLength(2));
      final confrontationRequest = generator.requests[1];
      expect(
        confrontationRequest.historyContext,
        contains('Narrated setup for event_1'),
      );
      expect(confrontationRequest.entityContext, contains('Iron Gate'));

      await engine
          .submitAction('Hold Iron Gate with the silver key', lang: 'en-US')
          .toList();
      expect(generator.requests, hasLength(3));
      final resolutionRequest = generator.requests[2];
      expect(
        resolutionRequest.historyContext,
        contains('&gt; Hold Iron Gate with the silver key'),
      );
      expect(resolutionRequest.entityContext, contains('silver key'));
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

List<int> _buildContextWorldPkg() {
  final archive = Archive()
    ..addFile(
      _jsonFile('metadata.json', <String, dynamic>{
        'title': 'Context Story',
        'source_file': 'context.txt',
        'total_characters': 100,
        'total_sentences': 4,
        'event_count': 1,
        'character_count': 1,
        'location_count': 1,
        'item_count': 1,
        'knowledge_count': 1,
        'transition_count': 0,
        'created_at': DateTime.now().toIso8601String(),
      }),
    )
    ..addFile(
      _jsonFile('source/sentences.json', <String, dynamic>{
        'total_sentences': 4,
        'total_characters': 100,
        'sentences': <Map<String, dynamic>>[
          <String, dynamic>{
            'index': 1,
            'text': 'Captain Mira reached Iron Gate before dawn.',
            'start': 0,
            'end': 43,
          },
          <String, dynamic>{
            'index': 2,
            'text': 'She gripped the silver key and studied the walls.',
            'start': 44,
            'end': 96,
          },
          <String, dynamic>{
            'index': 3,
            'text': 'Enemy drums rolled closer through the mist.',
            'start': 97,
            'end': 139,
          },
          <String, dynamic>{
            'index': 4,
            'text': 'The city waited for Mira to make the next command.',
            'start': 140,
            'end': 193,
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
            'goal': 'Hold Iron Gate against the siege',
            'sentence_range': <int>[1, 4],
            'importance': 'key',
            'decision_text': 'Decide how to defend Iron Gate.',
            'phases': <String, dynamic>{
              'setup': <String, dynamic>{
                'sentence_range': <int>[1, 2],
                'description': '',
                'decision_text':
                    'Captain Mira reached Iron Gate with the silver key.',
              },
              'confrontation': <String, dynamic>{
                'sentence_range': <int>[3, 3],
                'description': '',
                'decision_text': 'Enemy drums rolled closer.',
              },
              'resolution': <String, dynamic>{
                'sentence_range': <int>[4, 4],
                'description': '',
                'decision_text': 'The city waits for the result.',
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
              'overview': 'The main defensive gate of the city.',
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
            'description': <String, dynamic>{
              'appearance': 'A bright silver key.',
            },
            'function': <String, dynamic>{'primary_use': 'Open the inner gate'},
            'significance': <String, dynamic>{
              'narrative_role': 'Can decide whether the city survives.',
            },
          },
        ],
      }),
    )
    ..addFile(
      _jsonFile('lorebook/knowledge.json', <String, dynamic>{
        'knowledge': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'siege_at_dawn',
            'name': 'The siege will hit before dawn',
            'initial_holders': <String>['mira'],
            'description': 'The enemy will strike Iron Gate before dawn.',
          },
        ],
      }),
    );
  archive.addFile(
    _jsonFile('transitions/transitions.json', <String, dynamic>{
      'transitions': <Map<String, dynamic>>[
        <String, dynamic>{
          'event_id': 'event_1',
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
