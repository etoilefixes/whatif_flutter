import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_client/src/models.dart';
import 'package:flutter_client/src/services/config_store.dart';
import 'package:flutter_client/src/services/integrated_llm_client.dart';
import 'package:flutter_client/src/services/local_backend_paths.dart';
import 'package:flutter_client/src/services/local_deviation_agent.dart';
import 'package:flutter_client/src/services/local_game_engine.dart';
import 'package:flutter_client/src/services/local_narrative_generator.dart';
import 'package:flutter_client/src/services/local_scene_adaptation.dart';
import 'package:flutter_client/src/services/local_worldpkg.dart';

void main() {
  test(
    'local game engine sends scene adaptation guidance into narrative generation',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'whatif_scene_adaptation_',
      );
      addTearDown(() async {
        if (tempRoot.existsSync()) {
          await tempRoot.delete(recursive: true);
        }
      });

      final worldFile = File('${tempRoot.path}\\adaptation_story.wpkg')
        ..writeAsBytesSync(_buildSceneAdaptationWorldPkg());
      final world = LocalWorldPkg.load(worldFile);

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
      final engine = LocalGameEngine(
        savesDir: Directory('${tempRoot.path}\\saves'),
        narrativeGenerator: generator,
        deviationAgent: _FixedDeviationAgent(
          store: store,
          loadConfig: loadConfig,
        ),
        sceneAdaptationPlanner: LocalSceneAdaptationPlanner(
          store: store,
          llmClient: IntegratedLlmClient(),
          loadConfig: loadConfig,
        ),
      );
      engine.setWorld(world);

      await engine.startGame(lang: 'en-US').toList();
      await engine.continueGame(lang: 'en-US').toList();
      await engine.submitAction('set the hall ablaze', lang: 'en-US').toList();

      final request = generator.requests.last;
      expect(request.phase, 'resolution');
      expect(request.adaptationPlanText, isNotNull);
      expect(request.adaptationPlanText, contains('<adaptation_plan>'));
      expect(request.adaptationPlanText, contains('delta-001'));
      expect(request.phaseSource, contains('already on fire'));
      expect(request.fallbackText, contains('already on fire'));
    },
  );

  test(
    'local game engine adapts fallback resolution text when no writer is available',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'whatif_scene_adaptation_fallback_',
      );
      addTearDown(() async {
        if (tempRoot.existsSync()) {
          await tempRoot.delete(recursive: true);
        }
      });

      final worldFile = File('${tempRoot.path}\\adaptation_story.wpkg')
        ..writeAsBytesSync(_buildSceneAdaptationWorldPkg());
      final world = LocalWorldPkg.load(worldFile);

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
      final engine = LocalGameEngine(
        savesDir: Directory('${tempRoot.path}\\saves'),
        deviationAgent: _FixedDeviationAgent(
          store: store,
          loadConfig: loadConfig,
        ),
        sceneAdaptationPlanner: LocalSceneAdaptationPlanner(
          store: store,
          llmClient: IntegratedLlmClient(),
          loadConfig: loadConfig,
        ),
      );
      engine.setWorld(world);

      await engine.startGame(lang: 'en-US').toList();
      await engine.continueGame(lang: 'en-US').toList();
      final events = await engine
          .submitAction('set the hall ablaze', lang: 'en-US')
          .toList();
      final text = events
          .where((event) => event.type == 'chunk')
          .map((event) => event.text ?? '')
          .join();

      expect(text, contains('already on fire'));
      expect(text, contains('altered reality'));
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

class _FixedDeviationAgent extends LocalDeviationAgent {
  _FixedDeviationAgent({required super.store, required super.loadConfig})
    : super(llmClient: IntegratedLlmClient());

  @override
  Future<LocalDeviationAnalysis> analyze(LocalDeviationRequest request) async {
    return const LocalDeviationAnalysis(
      scratch: 'fixed',
      isDeviation: true,
      hasWorldChange: true,
      persistenceCount: 1,
      release: true,
      guidanceMethod: 'consequence_foreshadow',
      guidanceTone: 'fateful',
      guidanceHint: 'The hall has changed for good.',
      deltaFact: 'The council hall is already on fire.',
      deltaIntensity: 4,
    );
  }
}

List<int> _buildSceneAdaptationWorldPkg() {
  final archive = Archive()
    ..addFile(
      _jsonFile('metadata.json', <String, dynamic>{
        'title': 'Adaptation Story',
        'source_file': 'adaptation.txt',
        'total_characters': 180,
        'total_sentences': 3,
        'event_count': 1,
        'character_count': 1,
        'location_count': 1,
        'item_count': 0,
        'knowledge_count': 0,
        'transition_count': 0,
        'created_at': DateTime.now().toIso8601String(),
      }),
    )
    ..addFile(
      _jsonFile('source/sentences.json', <String, dynamic>{
        'total_sentences': 3,
        'total_characters': 180,
        'sentences': <Map<String, dynamic>>[
          <String, dynamic>{
            'index': 1,
            'text': 'Rain taps the council hall windows.',
            'start': 0,
            'end': 35,
          },
          <String, dynamic>{
            'index': 2,
            'text': 'The council waits in silence for your answer.',
            'start': 36,
            'end': 82,
          },
          <String, dynamic>{
            'index': 3,
            'text': 'A verdict settles over the hall.',
            'start': 83,
            'end': 116,
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
            'goal': 'Secure the council hall',
            'sentence_range': <int>[1, 3],
            'importance': 'key',
            'decision_text': 'Decide how to secure the council hall.',
            'phases': <String, dynamic>{
              'setup': <String, dynamic>{
                'sentence_range': <int>[1, 1],
                'description': '',
                'decision_text': 'Rain taps the council hall windows.',
              },
              'confrontation': <String, dynamic>{
                'sentence_range': <int>[2, 2],
                'description': '',
                'decision_text':
                    'The council waits in silence for your answer.',
              },
              'resolution': <String, dynamic>{
                'sentence_range': <int>[3, 3],
                'description': '',
                'decision_text': 'A verdict settles over the hall.',
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
            'id': 'protagonist',
            'name': 'Aren',
            'aliases': <String>['Aren'],
            'importance': 'protagonist',
            'identity': <String, dynamic>{'role': 'Envoy'},
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
            'id': 'council_hall',
            'name': 'council hall',
            'aliases': <String>['hall'],
            'importance': 'key',
            'type': 'building',
            'parent_location': null,
            'description': <String, dynamic>{
              'overview': 'A stone hall for council debates.',
            },
            'connected_to': <List<dynamic>>[],
          },
        ],
      }),
    )
    ..addFile(
      _jsonFile('lorebook/items.json', <String, dynamic>{
        'items': <Map<String, dynamic>>[],
      }),
    )
    ..addFile(
      _jsonFile('lorebook/knowledge.json', <String, dynamic>{
        'knowledge': <Map<String, dynamic>>[],
      }),
    )
    ..addFile(
      _jsonFile('transitions/transitions.json', <String, dynamic>{
        'transitions': <Map<String, dynamic>>[],
      }),
    );

  return ZipEncoder().encode(archive);
}

ArchiveFile _jsonFile(String name, Map<String, dynamic> json) {
  final bytes = utf8.encode(jsonEncode(json));
  return ArchiveFile(name, bytes.length, bytes);
}
