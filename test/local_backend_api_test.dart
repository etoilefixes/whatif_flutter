import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_client/src/services/config_store.dart';
import 'package:flutter_client/src/services/local_backend_api.dart';
import 'package:flutter_client/src/services/local_backend_paths.dart';

void main() {
  test(
    'local backend drives gameplay and persists agent state in saves',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'whatif_local_test_',
      );
      addTearDown(() async {
        if (tempRoot.existsSync()) {
          await tempRoot.delete(recursive: true);
        }
      });

      final outputDir = Directory('${tempRoot.path}\\output')..createSync();
      final savesDir = Directory('${tempRoot.path}\\saves')..createSync();
      final llmConfigFile = File('${tempRoot.path}\\llm_config.yaml')
        ..writeAsStringSync(_sampleLlmConfig);

      final wpkgFile = File('${outputDir.path}\\test_story.wpkg');
      wpkgFile.writeAsBytesSync(_buildSampleWorldPkg());

      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await SharedPreferences.getInstance();
      final store = await ConfigStore.open(
        legacyPrefs: prefs,
        useInMemoryDatabase: true,
      );
      final backend = await LocalBackendApi.create(
        store: store,
        paths: LocalBackendPaths(
          rootDir: tempRoot,
          outputDir: outputDir,
          savesDir: savesDir,
          llmConfigFile: llmConfigFile,
        ),
      );
      addTearDown(backend.dispose);

      expect(await backend.checkHealth(), isTrue);

      final llmConfig = await backend.getLlmConfig();
      expect(
        llmConfig.extractors['event_extractor']?.model,
        'dashscope/qwen3.5-plus',
      );

      final packages = await backend.getWorldPkgs();
      expect(packages.packages, hasLength(1));
      expect(packages.packages.first.name, 'Test Story');
      expect(await backend.getWorldPkgCover('test_story.wpkg'), isNotNull);

      await backend.loadWorldPkg('test_story.wpkg');

      final startEvents = await backend.startGameStream(lang: 'en-US').toList();
      expect(
        startEvents
            .where((event) => event.type == 'chunk')
            .map((event) => event.text)
            .join(),
        contains('Midnight clouds press over the mountain gate.'),
      );
      expect(
        startEvents.where((event) => event.type == 'state').last.state?.phase,
        'setup',
      );

      final continueEvents = await backend
          .continueGameStream(lang: 'en-US')
          .toList();
      expect(
        continueEvents
            .where((event) => event.type == 'state')
            .last
            .state
            ?.phase,
        'confrontation',
      );

      final actionEvents = await backend
          .submitActionStream('burn the gate and leave', lang: 'en-US')
          .toList();
      final actionText = actionEvents
          .where((event) => event.type == 'chunk')
          .map((event) => event.text)
          .join();
      expect(actionText, contains('burn the gate and leave'));
      expect(
        actionEvents.where((event) => event.type == 'state').last.state?.phase,
        'resolution',
      );
      expect(await backend.getEventImage('event_1'), isNotNull);

      final saveMessage = await backend.saveGame(1, '');
      expect(saveMessage, contains('slot 1'));

      final stateFile = File('${savesDir.path}\\save_001\\state.json');
      final state =
          jsonDecode(stateFile.readAsStringSync()) as Map<String, dynamic>;
      final deltaState = state['deltaState'] as Map<String, dynamic>;
      final activeDeltas = deltaState['active'] as List<dynamic>;
      final deviationHistory =
          state['currentDeviationHistory'] as List<dynamic>;
      expect(activeDeltas, hasLength(1));
      expect(deviationHistory, hasLength(1));
      expect(
        (activeDeltas.first as Map<String, dynamic>)['fact'] as String,
        contains('burn the gate and leave'),
      );

      final saves = await backend.getSaves();
      expect(saves, hasLength(1));
      expect(saves.first.worldpkgTitle, 'Test Story');

      final loaded = await backend.loadGame(1);
      expect(loaded.text, contains('> burn the gate and leave'));

      final gameState = await backend.getGameState();
      expect(gameState.phase, 'resolution');
      expect(gameState.event?.id, 'event_1');
    },
  );

  test('local backend can build a playable world package from text', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'whatif_local_build_test_',
    );
    addTearDown(() async {
      if (tempRoot.existsSync()) {
        await tempRoot.delete(recursive: true);
      }
    });

    final outputDir = Directory('${tempRoot.path}\\output')..createSync();
    final savesDir = Directory('${tempRoot.path}\\saves')..createSync();
    final llmConfigFile = File('${tempRoot.path}\\llm_config.yaml')
      ..writeAsStringSync(_sampleLlmConfig);
    final novelFile = File('${tempRoot.path}\\novel.txt')
      ..writeAsStringSync(
        [
          'Chapter 1',
          '',
          'Captain Mira gripped the silver key at Iron Gate.',
          'Jon shouted from Black Tower that the rebels would arrive by dawn.',
          'Mira warned Jon that the gate must stay closed.',
          'Smoke rose beyond Iron Gate as enemy drums rolled.',
        ].join('\n'),
      );

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final store = await ConfigStore.open(
      legacyPrefs: prefs,
      useInMemoryDatabase: true,
    );
    final backend = await LocalBackendApi.create(
      store: store,
      paths: LocalBackendPaths(
        rootDir: tempRoot,
        outputDir: outputDir,
        savesDir: savesDir,
        llmConfigFile: llmConfigFile,
      ),
    );
    addTearDown(backend.dispose);

    expect(backend.supportsLocalWorldPkgBuild, isTrue);

    await backend.buildWorldPkgFromText(novelFile.path);
    final packages = await backend.getWorldPkgs();
    expect(packages.packages, hasLength(1));
    expect(packages.packages.first.name, 'novel');
    expect(packages.packages.first.filename, endsWith('.wpkg'));

    final builtFile = File(
      '${outputDir.path}\\${packages.packages.first.filename}',
    );
    final archive = ZipDecoder().decodeBytes(builtFile.readAsBytesSync());
    final events =
        _readArchiveJson(archive, 'events/events.json')['events']
            as List<dynamic>;
    final transitions =
        _readArchiveJson(archive, 'transitions/transitions.json')['transitions']
            as List<dynamic>;
    final characters =
        _readArchiveJson(archive, 'lorebook/characters.json')['characters']
            as List<dynamic>;
    final locations =
        _readArchiveJson(archive, 'lorebook/locations.json')['locations']
            as List<dynamic>;
    final items =
        _readArchiveJson(archive, 'lorebook/items.json')['items']
            as List<dynamic>;
    final knowledge =
        _readArchiveJson(archive, 'lorebook/knowledge.json')['knowledge']
            as List<dynamic>;

    expect(
      characters
          .whereType<Map<String, dynamic>>()
          .map((entry) => entry['name'] as String)
          .toSet(),
      containsAll(<String>{'Mira', 'Jon'}),
    );
    expect(
      locations
          .whereType<Map<String, dynamic>>()
          .map((entry) => entry['name'] as String)
          .toSet(),
      containsAll(<String>{'Iron Gate', 'Black Tower'}),
    );
    expect(
      items
          .whereType<Map<String, dynamic>>()
          .map((entry) => entry['name'] as String)
          .toSet(),
      contains('silver key'),
    );
    expect(knowledge, isNotEmpty);
    expect(events, hasLength(1));
    expect(
      ((events.first as Map<String, dynamic>)['sentence_range']
              as List<dynamic>)
          .cast<int>(),
      <int>[1, 4],
    );
    final phases =
        (events.first as Map<String, dynamic>)['phases']
            as Map<String, dynamic>;
    expect(
      ((phases['setup'] as Map<String, dynamic>)['sentence_range']
              as List<dynamic>)
          .cast<int>(),
      <int>[1, 1],
    );
    expect(
      ((phases['confrontation'] as Map<String, dynamic>)['sentence_range']
              as List<dynamic>)
          .cast<int>(),
      <int>[2, 3],
    );
    expect(
      ((phases['resolution'] as Map<String, dynamic>)['sentence_range']
              as List<dynamic>)
          .cast<int>(),
      <int>[4, 4],
    );
    expect(transitions, hasLength(1));
    final preconditions =
        ((transitions.first as Map<String, dynamic>)['preconditions']
                    as List<dynamic>? ??
                const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .toList();
    expect(preconditions, isNotEmpty);
    expect(
      preconditions.map((entry) => entry['name'] as String).toSet(),
      contains('Mira'),
    );
    expect(
      preconditions.map((entry) => entry['from'] as String).toSet(),
      contains('Iron Gate'),
    );

    await backend.loadWorldPkg(packages.packages.first.filename);

    final startEvents = await backend.startGameStream(lang: 'en-US').toList();
    final startText = startEvents
        .where((event) => event.type == 'chunk')
        .map((event) => event.text)
        .join();
    expect(
      startText,
      contains('Captain Mira gripped the silver key at Iron Gate.'),
    );

    final continueEvents = await backend
        .continueGameStream(lang: 'en-US')
        .toList();
    expect(
      continueEvents.where((event) => event.type == 'state').last.state?.phase,
      'confrontation',
    );
  });
}

const _sampleLlmConfig = '''
extractors:
  event_extractor:
    model: dashscope/qwen3.5-plus
    temperature: 0.2
    thinking_budget: 128
agents:
  unified_writer:
    model: dashscope/qwen3-max
    temperature: 0.7
    thinking_budget: 64
''';

List<int> _buildSampleWorldPkg() {
  final archive = Archive()
    ..addFile(
      _jsonFile('metadata.json', <String, dynamic>{
        'title': 'Test Story',
        'source_file': 'demo.txt',
        'total_characters': 12,
        'total_sentences': 4,
        'event_count': 1,
        'character_count': 1,
        'location_count': 0,
        'item_count': 0,
        'knowledge_count': 0,
        'transition_count': 0,
        'created_at': DateTime.now().toIso8601String(),
      }),
    )
    ..addFile(
      _jsonFile('source/sentences.json', <String, dynamic>{
        'total_sentences': 4,
        'total_characters': 12,
        'sentences': <Map<String, dynamic>>[
          <String, dynamic>{
            'index': 1,
            'text': 'Midnight clouds press over the mountain gate.',
            'start': 0,
            'end': 7,
          },
          <String, dynamic>{
            'index': 2,
            'text': 'Enemy scouts close in.',
            'start': 8,
            'end': 12,
          },
          <String, dynamic>{
            'index': 3,
            'text': 'You must decide now.',
            'start': 13,
            'end': 19,
          },
          <String, dynamic>{
            'index': 4,
            'text': 'For one heartbeat, the crisis eases.',
            'start': 20,
            'end': 27,
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
            'goal': 'Hold the mountain gate',
            'sentence_range': <int>[1, 4],
            'importance': 'key',
            'decision_text': 'Hold the gate.',
            'image': 'images/event_1.png',
            'phases': <String, dynamic>{
              'setup': <String, dynamic>{
                'sentence_range': <int>[1, 1],
                'description': '',
                'decision_text':
                    'Midnight clouds press over the mountain gate.',
              },
              'confrontation': <String, dynamic>{
                'sentence_range': <int>[2, 3],
                'description': '',
                'decision_text': 'Enemy scouts close in, and you must choose.',
              },
              'resolution': <String, dynamic>{
                'sentence_range': <int>[4, 4],
                'description': '',
                'decision_text': 'For one heartbeat, the crisis eases.',
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
            'id': 'hero',
            'name': 'Lin Ye',
            'aliases': <String>[],
            'importance': 'protagonist',
            'identity': <String, dynamic>{'role': 'Gate Warden'},
            'relationships': <List<dynamic>>[],
            'dialogue_examples': <List<dynamic>>[],
          },
        ],
      }),
    )
    ..addFile(ArchiveFile('cover.png', 4, <int>[0, 1, 2, 3]))
    ..addFile(ArchiveFile('images/event_1.png', 4, <int>[4, 5, 6, 7]));

  return ZipEncoder().encode(archive);
}

ArchiveFile _jsonFile(String name, Map<String, dynamic> json) {
  final bytes = utf8.encode(jsonEncode(json));
  return ArchiveFile(name, bytes.length, bytes);
}

Map<String, dynamic> _readArchiveJson(Archive archive, String name) {
  final entry = archive.findFile(name);
  if (entry == null) {
    throw StateError('Missing archive entry: $name');
  }
  final decoded = jsonDecode(utf8.decode(entry.content as List<int>));
  return decoded as Map<String, dynamic>;
}
