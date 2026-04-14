import 'local_lorebook_builder.dart';

class LocalTransitionBuilder {
  const LocalTransitionBuilder();

  List<Map<String, dynamic>> build({
    required List<Map<String, dynamic>> events,
    required List<String> sentences,
    required LocalLorebookBuildResult lorebook,
  }) {
    final protagonist = _resolveProtagonist(lorebook.characters);
    final characterNames = _namesById(lorebook.characters);

    return events.map((event) {
      final range = (event['sentence_range'] as List<dynamic>? ?? const [])
          .whereType<num>()
          .map((value) => value.toInt())
          .toList();
      final eventText = range.length == 2
          ? _rangeText(sentences, range.first, range.last)
          : '';

      final matchedCharacters = _matchEntries(
        lorebook.characters,
        eventText,
        primaryKeys: const <String>['name'],
        aliasKeys: const <String>['aliases'],
      );
      final matchedLocations = _matchEntries(
        lorebook.locations,
        eventText,
        primaryKeys: const <String>['name'],
        aliasKeys: const <String>['aliases'],
      );
      final matchedItems = _matchEntries(
        lorebook.items,
        eventText,
        primaryKeys: const <String>['name'],
        aliasKeys: const <String>['aliases'],
      );
      final matchedKnowledge = _matchEntries(
        lorebook.knowledge,
        eventText,
        primaryKeys: const <String>['name'],
      );

      final holders = matchedCharacters
          .map((entry) => _stringValue(entry['name']))
          .where((name) => name.isNotEmpty)
          .toSet()
          .toList();
      if (holders.isEmpty && protagonist.isNotEmpty) {
        holders.add(protagonist);
      }

      final preconditions = <Map<String, dynamic>>[];
      final seen = <String>{};

      for (final location in matchedLocations.take(2)) {
        final locationName = _stringValue(location['name']);
        if (locationName.isEmpty) {
          continue;
        }
        for (final holder in holders.take(2)) {
          _addCondition(
            target: preconditions,
            seen: seen,
            condition: <String, dynamic>{
              'name': holder,
              'type': 'character',
              'attribute': '\u5730\u70b9',
              'from': locationName,
              'granularity': 'named',
            },
          );
        }
      }

      final defaultHolder = holders.isNotEmpty ? holders.first : protagonist;
      for (final item in matchedItems.take(2)) {
        final itemName = _stringValue(item['name']);
        if (itemName.isEmpty || defaultHolder.isEmpty) {
          continue;
        }
        _addCondition(
          target: preconditions,
          seen: seen,
          condition: <String, dynamic>{
            'name': itemName,
            'type': 'item',
            'attribute': '\u6301\u6709\u8005',
            'from': defaultHolder,
            'granularity': 'named',
          },
        );
      }

      for (final knowledge in matchedKnowledge.take(2)) {
        final knowledgeName = _stringValue(knowledge['name']);
        if (knowledgeName.isEmpty) {
          continue;
        }
        final initialHolders =
            (knowledge['initial_holders'] as List<dynamic>? ?? const [])
                .whereType<String>()
                .map((id) => characterNames[id]?.trim() ?? '')
                .where((name) => name.isNotEmpty)
                .toList();
        final holder = initialHolders.isNotEmpty
            ? initialHolders.first
            : defaultHolder;
        if (holder.isEmpty) {
          continue;
        }
        _addCondition(
          target: preconditions,
          seen: seen,
          condition: <String, dynamic>{
            'name': knowledgeName,
            'type': 'information',
            'attribute': '\u77e5\u6653\u8005',
            'from': holder,
            'granularity': 'named',
          },
        );
      }

      return <String, dynamic>{
        'event_id': event['id'] as String? ?? '',
        'preconditions': preconditions,
        'effects': const <Map<String, dynamic>>[],
      };
    }).toList();
  }

  String _resolveProtagonist(List<Map<String, dynamic>> characters) {
    for (final character in characters) {
      if (_stringValue(character['importance']) == 'protagonist') {
        return _stringValue(character['name']);
      }
    }
    return characters.isEmpty ? '' : _stringValue(characters.first['name']);
  }

  Map<String, String> _namesById(List<Map<String, dynamic>> entries) {
    return <String, String>{
      for (final entry in entries)
        if (_stringValue(entry['id']).isNotEmpty)
          _stringValue(entry['id']): _stringValue(entry['name']),
    };
  }

  List<Map<String, dynamic>> _matchEntries(
    List<Map<String, dynamic>> entries,
    String text, {
    required List<String> primaryKeys,
    List<String> aliasKeys = const <String>[],
  }) {
    final normalizedText = _normalizeText(text);
    if (normalizedText.isEmpty) {
      return const <Map<String, dynamic>>[];
    }

    final matches = <_ScoredMatch>[];
    for (final entry in entries) {
      var score = 0;
      for (final key in primaryKeys) {
        score += _matchScore(normalizedText, entry[key]);
      }
      for (final key in aliasKeys) {
        score += _matchScore(normalizedText, entry[key]);
      }
      if (score > 0) {
        matches.add(_ScoredMatch(entry: entry, score: score));
      }
    }

    matches.sort((left, right) {
      final byScore = right.score.compareTo(left.score);
      if (byScore != 0) {
        return byScore;
      }

      final byImportance = _importanceRank(
        right.entry,
      ).compareTo(_importanceRank(left.entry));
      if (byImportance != 0) {
        return byImportance;
      }

      return _stringValue(
        left.entry['name'],
      ).length.compareTo(_stringValue(right.entry['name']).length);
    });
    return matches.map((match) => match.entry).toList();
  }

  int _matchScore(String normalizedText, Object? candidate) {
    if (candidate is String) {
      return _stringMatchScore(normalizedText, candidate);
    }
    if (candidate is List<dynamic>) {
      return candidate.whereType<String>().fold<int>(
        0,
        (score, value) => score + _stringMatchScore(normalizedText, value),
      );
    }
    return 0;
  }

  int _stringMatchScore(String normalizedText, String value) {
    final normalizedValue = _normalizeText(value);
    if (normalizedValue.isEmpty) {
      return 0;
    }
    if (!normalizedText.contains(normalizedValue)) {
      return 0;
    }
    return 12;
  }

  String _rangeText(List<String> sentences, int start, int end) {
    final startIndex = start < 1 ? 0 : start - 1;
    final endIndex = end > sentences.length ? sentences.length : end;
    if (startIndex >= endIndex) {
      return '';
    }
    return sentences.sublist(startIndex, endIndex).join(' ');
  }

  String _normalizeText(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _stringValue(Object? value) {
    return value?.toString().trim() ?? '';
  }

  void _addCondition({
    required List<Map<String, dynamic>> target,
    required Set<String> seen,
    required Map<String, dynamic> condition,
  }) {
    final key = [
      _stringValue(condition['name']),
      _stringValue(condition['type']),
      _stringValue(condition['attribute']),
      _stringValue(condition['from']),
    ].join('|');
    if (key.replaceAll('|', '').isEmpty || seen.contains(key)) {
      return;
    }
    seen.add(key);
    target.add(condition);
  }

  int _importanceRank(Map<String, dynamic> entry) {
    return switch (_stringValue(entry['importance'])) {
      'protagonist' => 3,
      'key' => 2,
      'normal' => 1,
      _ => 0,
    };
  }
}

class _ScoredMatch {
  const _ScoredMatch({required this.entry, required this.score});

  final Map<String, dynamic> entry;
  final int score;
}
