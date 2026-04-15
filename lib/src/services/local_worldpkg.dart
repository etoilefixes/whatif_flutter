import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import '../models.dart';

class LocalWorldPkg {
  LocalWorldPkg._({
    required this.file,
    required this.title,
    required this.size,
    required this.hasCover,
    required Archive archive,
    required Map<int, String> sentences,
    required List<LocalWorldEvent> orderedEvents,
    required Map<String, LocalWorldEvent> eventIndex,
    required Map<String, LocalEventTransition> transitionIndex,
    required List<LocalWorldCharacter> characters,
    required List<LocalLorebookEntry> lorebookEntries,
    required this.coverEntryName,
  }) : _archive = archive,
       _sentences = sentences,
       _orderedEvents = orderedEvents,
       _eventIndex = eventIndex,
       _transitionIndex = transitionIndex,
       _characters = characters,
       _lorebookEntries = lorebookEntries;

  final File file;
  final String title;
  final int size;
  final bool hasCover;
  final String? coverEntryName;
  final Archive _archive;
  final Map<int, String> _sentences;
  final List<LocalWorldEvent> _orderedEvents;
  final Map<String, LocalWorldEvent> _eventIndex;
  final Map<String, LocalEventTransition> _transitionIndex;
  final List<LocalWorldCharacter> _characters;
  final List<LocalLorebookEntry> _lorebookEntries;

  String get filename =>
      file.uri.pathSegments.isEmpty ? file.path : file.uri.pathSegments.last;

  static const Map<String, String> _coverNames = <String, String>{
    'cover.png': 'image/png',
    'cover.jpg': 'image/jpeg',
    'cover.jpeg': 'image/jpeg',
    'cover.webp': 'image/webp',
  };

  static LocalWorldPkgIndex inspect(File file) {
    final archive = ZipDecoder().decodeBytes(file.readAsBytesSync());
    final metadata = _jsonEntry(archive, 'metadata.json') ?? const {};
    final coverEntryName = _coverNames.keys.cast<String?>().firstWhere(
      (name) => name != null && _findEntry(archive, name) != null,
      orElse: () => null,
    );

    return LocalWorldPkgIndex(
      title: metadata['title'] as String? ?? filenameFromFile(file),
      size: file.lengthSync(),
      hasCover: coverEntryName != null,
    );
  }

  static LocalWorldPkg load(File file) {
    final archive = ZipDecoder().decodeBytes(file.readAsBytesSync());
    final metadata = _jsonEntry(archive, 'metadata.json') ?? const {};
    final sentencesJson =
        _jsonEntry(archive, 'source/sentences.json')?['sentences']
            as List<dynamic>? ??
        const [];
    final eventsJson =
        _jsonEntry(archive, 'events/events.json')?['events']
            as List<dynamic>? ??
        const [];
    final transitionsJson =
        _jsonEntry(archive, 'transitions/transitions.json')?['transitions']
            as List<dynamic>? ??
        const [];
    final charactersJson =
        _jsonEntry(archive, 'lorebook/characters.json')?['characters']
            as List<dynamic>? ??
        const [];
    final locationsJson =
        _jsonEntry(archive, 'lorebook/locations.json')?['locations']
            as List<dynamic>? ??
        const [];
    final itemsJson =
        _jsonEntry(archive, 'lorebook/items.json')?['items']
            as List<dynamic>? ??
        const [];
    final knowledgeJson =
        _jsonEntry(archive, 'lorebook/knowledge.json')?['knowledge']
            as List<dynamic>? ??
        const [];

    final sentences = <int, String>{};
    for (final raw in sentencesJson.whereType<Map<String, dynamic>>()) {
      final index = (raw['index'] as num?)?.toInt();
      final text = raw['text'] as String?;
      if (index != null && text != null) {
        sentences[index] = text;
      }
    }

    final orderedEvents =
        eventsJson
            .whereType<Map<String, dynamic>>()
            .map(LocalWorldEvent.fromJson)
            .toList()
          ..sort((left, right) {
            final leftStart = left.sentenceRange.isEmpty
                ? 1 << 30
                : left.sentenceRange.first;
            final rightStart = right.sentenceRange.isEmpty
                ? 1 << 30
                : right.sentenceRange.first;
            return leftStart.compareTo(rightStart);
          });

    final eventIndex = <String, LocalWorldEvent>{
      for (final event in orderedEvents) event.id: event,
    };
    final transitionIndex = <String, LocalEventTransition>{
      for (final transition
          in transitionsJson.whereType<Map<String, dynamic>>().map(
            LocalEventTransition.fromJson,
          ))
        transition.eventId: transition,
    };

    final characters = charactersJson
        .whereType<Map<String, dynamic>>()
        .map(LocalWorldCharacter.fromJson)
        .toList();
    final lorebookEntries = <LocalLorebookEntry>[
      ...charactersJson.whereType<Map<String, dynamic>>().map(
        (entry) => LocalLorebookEntry.fromJson('character', entry),
      ),
      ...locationsJson.whereType<Map<String, dynamic>>().map(
        (entry) => LocalLorebookEntry.fromJson('location', entry),
      ),
      ...itemsJson.whereType<Map<String, dynamic>>().map(
        (entry) => LocalLorebookEntry.fromJson('item', entry),
      ),
      ...knowledgeJson.whereType<Map<String, dynamic>>().map(
        (entry) => LocalLorebookEntry.fromJson('knowledge', entry),
      ),
    ];

    final coverEntryName = _coverNames.keys.cast<String?>().firstWhere(
      (name) => name != null && _findEntry(archive, name) != null,
      orElse: () => null,
    );

    return LocalWorldPkg._(
      file: file,
      title: metadata['title'] as String? ?? filenameFromFile(file),
      size: file.lengthSync(),
      hasCover: coverEntryName != null,
      archive: archive,
      sentences: sentences,
      orderedEvents: orderedEvents,
      eventIndex: eventIndex,
      transitionIndex: transitionIndex,
      characters: characters,
      lorebookEntries: lorebookEntries,
      coverEntryName: coverEntryName,
    );
  }

  static String filenameFromFile(File file) {
    return file.uri.pathSegments.isEmpty
        ? file.path
        : file.uri.pathSegments.last;
  }

  WorldPkgInfo toInfo() {
    return WorldPkgInfo(
      name: title,
      filename: filename,
      size: size,
      hasCover: hasCover,
    );
  }

  LocalWorldEvent? getEvent(String? eventId) {
    if (eventId == null || eventId.isEmpty) {
      return null;
    }
    return _eventIndex[eventId];
  }

  LocalWorldEvent? getFirstEvent() {
    return _orderedEvents.isEmpty ? null : _orderedEvents.first;
  }

  String? getNextEventId(String? currentEventId) {
    if (currentEventId == null || currentEventId.isEmpty) {
      return null;
    }

    for (var index = 0; index < _orderedEvents.length; index += 1) {
      if (_orderedEvents[index].id == currentEventId) {
        return index + 1 < _orderedEvents.length
            ? _orderedEvents[index + 1].id
            : null;
      }
    }
    return null;
  }

  LocalWorldCharacter? getProtagonist() {
    for (final character in _characters) {
      if (character.importance == 'protagonist') {
        return character;
      }
    }
    return null;
  }

  List<LocalLorebookEntry> searchLorebook(String query, {int limit = 4}) {
    final normalizedQuery = _normalizeSearchText(query);
    if (normalizedQuery.isEmpty || _lorebookEntries.isEmpty || limit <= 0) {
      return const <LocalLorebookEntry>[];
    }

    final queryTokens = _extractSearchTokens(query);
    final scored = <_LorebookSearchResult>[];
    for (final entry in _lorebookEntries) {
      final score = _scoreLorebookEntry(
        entry,
        normalizedQuery: normalizedQuery,
        queryTokens: queryTokens,
      );
      if (score > 0) {
        scored.add(_LorebookSearchResult(entry: entry, score: score));
      }
    }

    scored.sort((left, right) => right.score.compareTo(left.score));
    return scored.take(limit).map((result) => result.entry).toList();
  }

  List<LocalTransitionCondition> getPreconditions(String eventId) {
    return _transitionIndex[eventId]?.preconditions ??
        const <LocalTransitionCondition>[];
  }

  String? getEventTextFull(String eventId) {
    final event = getEvent(eventId);
    if (event == null) {
      return null;
    }
    return _rangeText(event.sentenceRange);
  }

  String? getPhaseTextFull(String eventId, String phaseName) {
    final phase = getEvent(eventId)?.phases[phaseName];
    if (phase == null) {
      return null;
    }

    if (phase.sentenceRange != null && phase.sentenceRange!.length == 2) {
      final text = _rangeText(phase.sentenceRange!);
      if (text != null && text.trim().isNotEmpty) {
        return text;
      }
    }

    if (phase.description.trim().isNotEmpty) {
      return phase.description.trim();
    }

    if (phase.decisionText.trim().isNotEmpty) {
      return phase.decisionText.trim();
    }

    return null;
  }

  String? getPhaseDecisionText(String eventId, String phaseName) {
    final decisionText = getEvent(
      eventId,
    )?.phases[phaseName]?.decisionText.trim();
    if (decisionText == null || decisionText.isEmpty) {
      return null;
    }
    return decisionText;
  }

  String? getEventDecisionText(String eventId) {
    final decisionText = getEvent(eventId)?.decisionText.trim();
    if (decisionText == null || decisionText.isEmpty) {
      return null;
    }
    return decisionText;
  }

  Uint8List? getCoverBytes() {
    if (coverEntryName == null) {
      return null;
    }
    return _entryBytes(coverEntryName!);
  }

  Uint8List? getEventImageBytes(String eventId) {
    final image = getEvent(eventId)?.image;
    if (image == null || image.isEmpty) {
      return null;
    }
    return _entryBytes(image);
  }

  String? _rangeText(List<int> range) {
    if (range.length != 2) {
      return null;
    }

    final parts = <String>[];
    for (var index = range.first; index <= range.last; index += 1) {
      final text = _sentences[index];
      if (text != null && text.isNotEmpty) {
        parts.add(text);
      }
    }

    final joined = parts.join();
    return joined.isEmpty ? null : joined;
  }

  Uint8List? _entryBytes(String name) {
    final entry = _findEntry(_archive, name);
    if (entry == null) {
      return null;
    }

    return Uint8List.fromList(entry.content);
  }

  static ArchiveFile? _findEntry(Archive archive, String name) {
    for (final entry in archive.files) {
      if (entry.name == name) {
        return entry;
      }
    }
    return null;
  }

  static Map<String, dynamic>? _jsonEntry(Archive archive, String name) {
    final entry = _findEntry(archive, name);
    if (entry == null) {
      return null;
    }

    final bytes = Uint8List.fromList(entry.content);
    if (bytes.isEmpty) {
      return null;
    }

    final decoded = jsonDecode(utf8.decode(bytes));
    return decoded is Map<String, dynamic> ? decoded : null;
  }
}

class LocalWorldEvent {
  const LocalWorldEvent({
    required this.id,
    required this.type,
    required this.goal,
    required this.sentenceRange,
    required this.importance,
    required this.decisionText,
    required this.image,
    required this.phases,
  });

  final String id;
  final String type;
  final String goal;
  final List<int> sentenceRange;
  final String importance;
  final String decisionText;
  final String? image;
  final Map<String, LocalWorldPhase> phases;

  factory LocalWorldEvent.fromJson(Map<String, dynamic> json) {
    final rawPhases = json['phases'] as Map<String, dynamic>? ?? const {};
    return LocalWorldEvent(
      id: json['id'] as String? ?? '',
      type: json['type'] as String? ?? 'interactive',
      goal: json['goal'] as String? ?? '',
      sentenceRange: (json['sentence_range'] as List<dynamic>? ?? const [])
          .map((value) => (value as num).toInt())
          .toList(),
      importance: json['importance'] as String? ?? 'normal',
      decisionText: json['decision_text'] as String? ?? '',
      image: json['image'] as String?,
      phases: rawPhases.map(
        (key, value) => MapEntry(
          key,
          LocalWorldPhase.fromJson(value as Map<String, dynamic>),
        ),
      ),
    );
  }
}

class LocalWorldPkgIndex {
  const LocalWorldPkgIndex({
    required this.title,
    required this.size,
    required this.hasCover,
  });

  final String title;
  final int size;
  final bool hasCover;

  WorldPkgInfo toInfo(String filename) {
    return WorldPkgInfo(
      name: title,
      filename: filename,
      size: size,
      hasCover: hasCover,
    );
  }
}

class LocalWorldPhase {
  const LocalWorldPhase({
    required this.sentenceRange,
    required this.description,
    required this.decisionText,
  });

  final List<int>? sentenceRange;
  final String description;
  final String decisionText;

  factory LocalWorldPhase.fromJson(Map<String, dynamic> json) {
    final rawRange = json['sentence_range'] as List<dynamic>?;
    return LocalWorldPhase(
      sentenceRange: rawRange?.map((value) => (value as num).toInt()).toList(),
      description: json['description'] as String? ?? '',
      decisionText: json['decision_text'] as String? ?? '',
    );
  }
}

class LocalWorldCharacter {
  const LocalWorldCharacter({required this.name, required this.importance});

  final String name;
  final String importance;

  factory LocalWorldCharacter.fromJson(Map<String, dynamic> json) {
    return LocalWorldCharacter(
      name: json['name'] as String? ?? '',
      importance: json['importance'] as String? ?? 'supporting',
    );
  }
}

class LocalLorebookEntry {
  const LocalLorebookEntry({
    required this.id,
    required this.type,
    required this.data,
    required this.displayName,
    required this.searchTerms,
  });

  final String id;
  final String type;
  final Map<String, dynamic> data;
  final String displayName;
  final List<String> searchTerms;

  factory LocalLorebookEntry.fromJson(String type, Map<String, dynamic> json) {
    final aliases = (json['aliases'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<String>()
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty);
    final terms = <String>{
      json['id']?.toString().trim() ?? '',
      json['name']?.toString().trim() ?? '',
      ...aliases,
    }..removeWhere((value) => value.isEmpty);
    final displayName = json['name']?.toString().trim().isNotEmpty == true
        ? json['name'].toString().trim()
        : json['id']?.toString().trim() ?? type;

    return LocalLorebookEntry(
      id: json['id'] as String? ?? '',
      type: type,
      data: json,
      displayName: displayName,
      searchTerms: terms.toList(),
    );
  }
}

class LocalEventTransition {
  const LocalEventTransition({
    required this.eventId,
    required this.preconditions,
    required this.effects,
  });

  final String eventId;
  final List<LocalTransitionCondition> preconditions;
  final List<LocalTransitionEffect> effects;

  factory LocalEventTransition.fromJson(Map<String, dynamic> json) {
    return LocalEventTransition(
      eventId: json['event_id'] as String? ?? '',
      preconditions: (json['preconditions'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(LocalTransitionCondition.fromJson)
          .toList(),
      effects: (json['effects'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(LocalTransitionEffect.fromJson)
          .toList(),
    );
  }
}

class LocalTransitionCondition {
  const LocalTransitionCondition({
    required this.name,
    required this.type,
    required this.attribute,
    required this.fromValue,
    required this.granularity,
  });

  final String name;
  final String type;
  final String attribute;
  final String? fromValue;
  final String granularity;

  factory LocalTransitionCondition.fromJson(Map<String, dynamic> json) {
    return LocalTransitionCondition(
      name: json['name'] as String? ?? '',
      type: json['type'] as String? ?? '',
      attribute: json['attribute'] as String? ?? '',
      fromValue: json['from'] as String?,
      granularity: json['granularity'] as String? ?? 'named',
    );
  }
}

class LocalTransitionEffect {
  const LocalTransitionEffect({
    required this.name,
    required this.type,
    required this.attribute,
    required this.fromValue,
    required this.toValue,
    required this.granularity,
  });

  final String name;
  final String type;
  final String attribute;
  final String? fromValue;
  final String? toValue;
  final String granularity;

  factory LocalTransitionEffect.fromJson(Map<String, dynamic> json) {
    return LocalTransitionEffect(
      name: json['name'] as String? ?? '',
      type: json['type'] as String? ?? '',
      attribute: json['attribute'] as String? ?? '',
      fromValue: json['from'] as String?,
      toValue: json['to'] as String?,
      granularity: json['granularity'] as String? ?? 'named',
    );
  }
}

class _LorebookSearchResult {
  const _LorebookSearchResult({required this.entry, required this.score});

  final LocalLorebookEntry entry;
  final int score;
}

int _scoreLorebookEntry(
  LocalLorebookEntry entry, {
  required String normalizedQuery,
  required Set<String> queryTokens,
}) {
  var score = 0;
  for (final term in entry.searchTerms) {
    final normalizedTerm = _normalizeSearchText(term);
    if (normalizedTerm.isEmpty) {
      continue;
    }

    if (_queryContainsTerm(normalizedQuery, normalizedTerm)) {
      score += 30 + normalizedTerm.length;
      continue;
    }

    final termTokens = _extractSearchTokens(term);
    if (termTokens.isEmpty) {
      continue;
    }

    final overlap = termTokens.intersection(queryTokens).length;
    if (overlap > 0) {
      score += overlap * 12 + normalizedTerm.length;
    }
  }
  return score;
}

bool _queryContainsTerm(String normalizedQuery, String normalizedTerm) {
  final asciiOnly = RegExp(r'^[a-z0-9_ ]+$');
  if (!asciiOnly.hasMatch(normalizedTerm)) {
    return normalizedQuery.contains(normalizedTerm);
  }

  return RegExp(r'[a-z0-9_]+')
      .allMatches(normalizedQuery)
      .map((match) => match.group(0))
      .contains(normalizedTerm);
}

String _normalizeSearchText(String value) {
  return value.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
}

Set<String> _extractSearchTokens(String value) {
  final tokens = <String>{};
  for (final match in RegExp(
    r'[a-z0-9_]{3,}',
  ).allMatches(value.toLowerCase())) {
    tokens.add(match.group(0)!);
  }
  for (final match in RegExp(r'[\u4e00-\u9fff]{2,}').allMatches(value)) {
    tokens.add(match.group(0)!);
  }
  return tokens;
}
