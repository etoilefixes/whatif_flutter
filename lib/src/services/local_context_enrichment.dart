import 'dart:convert';

import 'local_worldpkg.dart';

class LocalContextEnrichment {
  const LocalContextEnrichment();

  String buildHistoryContext({
    required String query,
    required List<String> transcriptEntries,
    int maxEntries = 3,
  }) {
    if (transcriptEntries.isEmpty || maxEntries <= 0) {
      return '';
    }

    final normalizedQuery = _normalizeSearchText(query);
    final queryTokens = _extractSearchTokens(query);
    final scored = <_HistoryMatch>[];

    for (var index = 0; index < transcriptEntries.length; index += 1) {
      final text = transcriptEntries[index].trim();
      if (text.isEmpty) {
        continue;
      }

      final score = _scoreHistoryEntry(
        text,
        normalizedQuery: normalizedQuery,
        queryTokens: queryTokens,
        recencyRank: transcriptEntries.length - index,
      );
      if (score > 0) {
        scored.add(_HistoryMatch(index: index, text: text, score: score));
      }
    }

    final selected = scored.isEmpty
        ? _recentEntries(transcriptEntries, maxEntries)
        : _bestMatches(scored, maxEntries);
    if (selected.isEmpty) {
      return '';
    }

    final parts = <String>[];
    for (final match in selected) {
      parts.add('<entry index="${match.index + 1}">');
      parts.add(_xmlEscape(match.text));
      parts.add('</entry>');
    }
    return parts.join('\n');
  }

  String buildEntityContext({
    required LocalWorldPkg world,
    required String query,
    int maxEntries = 4,
  }) {
    final matches = world.searchLorebook(query, limit: maxEntries);
    if (matches.isEmpty) {
      return '';
    }

    const encoder = JsonEncoder.withIndent('  ');
    final parts = <String>[];
    for (final entry in matches) {
      parts.add(
        '<entity id="${_xmlEscape(entry.id)}" type="${_xmlEscape(entry.type)}">',
      );
      parts.add(encoder.convert(entry.data));
      parts.add('</entity>');
    }
    return parts.join('\n');
  }

  List<_HistoryMatch> _bestMatches(
    List<_HistoryMatch> matches,
    int maxEntries,
  ) {
    final selected = matches.toList()
      ..sort((left, right) {
        final byScore = right.score.compareTo(left.score);
        if (byScore != 0) {
          return byScore;
        }
        return right.index.compareTo(left.index);
      });
    final limited = selected.take(maxEntries).toList()
      ..sort((left, right) => left.index.compareTo(right.index));
    return limited;
  }

  List<_HistoryMatch> _recentEntries(List<String> entries, int maxEntries) {
    final start = entries.length > maxEntries ? entries.length - maxEntries : 0;
    final selected = <_HistoryMatch>[];
    for (var index = start; index < entries.length; index += 1) {
      final text = entries[index].trim();
      if (text.isEmpty) {
        continue;
      }
      selected.add(_HistoryMatch(index: index, text: text, score: 1));
    }
    return selected;
  }

  int _scoreHistoryEntry(
    String text, {
    required String normalizedQuery,
    required Set<String> queryTokens,
    required int recencyRank,
  }) {
    final normalizedText = _normalizeSearchText(text);
    if (normalizedText.isEmpty) {
      return 0;
    }

    var score = recencyRank;
    if (normalizedQuery.isNotEmpty &&
        normalizedText.contains(normalizedQuery)) {
      score += 30;
    }

    final textTokens = _extractSearchTokens(text);
    final overlap = textTokens.intersection(queryTokens).length;
    if (overlap > 0) {
      score += overlap * 10;
    }
    return score;
  }
}

class _HistoryMatch {
  const _HistoryMatch({
    required this.index,
    required this.text,
    required this.score,
  });

  final int index;
  final String text;
  final int score;
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

String _xmlEscape(String value) {
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}
