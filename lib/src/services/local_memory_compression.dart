import 'dart:convert';

import '../models.dart';
import 'config_store.dart';
import 'integrated_llm_client.dart';

class LocalL0Summary {
  const LocalL0Summary({
    required this.eventId,
    required this.summary,
    required this.tags,
    required this.charCount,
  });

  final String eventId;
  final String summary;
  final List<String> tags;
  final int charCount;

  factory LocalL0Summary.fromJson(Map<String, dynamic> json) {
    return LocalL0Summary(
      eventId: json['eventId'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      tags: (json['tags'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
      charCount: (json['charCount'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'eventId': eventId,
      'summary': summary,
      'tags': tags,
      'charCount': charCount,
    };
  }
}

class LocalL1Summary {
  const LocalL1Summary({
    required this.id,
    required this.covers,
    required this.summary,
    required this.tags,
    required this.charCount,
    required this.l0Summaries,
  });

  final String id;
  final String covers;
  final String summary;
  final List<String> tags;
  final int charCount;
  final List<LocalL0Summary> l0Summaries;

  factory LocalL1Summary.fromJson(Map<String, dynamic> json) {
    return LocalL1Summary(
      id: json['id'] as String? ?? '',
      covers: json['covers'] as String? ?? '',
      summary: json['summary'] as String? ?? '',
      tags: (json['tags'] as List<dynamic>? ?? const [])
          .whereType<String>()
          .toList(),
      charCount: (json['charCount'] as num?)?.toInt() ?? 0,
      l0Summaries: (json['l0Summaries'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(LocalL0Summary.fromJson)
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'covers': covers,
      'summary': summary,
      'tags': tags,
      'charCount': charCount,
      'l0Summaries': l0Summaries.map((entry) => entry.toJson()).toList(),
    };
  }
}

class LocalMemoryCompressionManager {
  LocalMemoryCompressionManager({
    required this.store,
    required this.llmClient,
    required this.loadConfig,
  });

  static const int l1Threshold = 10;

  final ConfigStore store;
  final IntegratedLlmClient llmClient;
  final Future<LlmConfigMap> Function() loadConfig;

  final List<LocalL0Summary> _l0Summaries = <LocalL0Summary>[];
  final List<LocalL1Summary> _l1Summaries = <LocalL1Summary>[];
  int _l1Counter = 0;

  List<LocalL0Summary> get l0Summaries =>
      List<LocalL0Summary>.unmodifiable(_l0Summaries);
  List<LocalL1Summary> get l1Summaries =>
      List<LocalL1Summary>.unmodifiable(_l1Summaries);

  void reset() {
    _l0Summaries.clear();
    _l1Summaries.clear();
    _l1Counter = 0;
  }

  Future<LocalL0Summary?> compressEvent({
    required String locale,
    required String eventId,
    required String eventContent,
  }) async {
    final normalizedEventId = eventId.trim();
    final normalizedContent = eventContent.trim();
    if (normalizedEventId.isEmpty || normalizedContent.isEmpty) {
      return null;
    }
    if (_l0Summaries.any((entry) => entry.eventId == normalizedEventId)) {
      return null;
    }

    final l0Summary = await _compressL0(
      locale: locale,
      eventId: normalizedEventId,
      eventContent: normalizedContent,
    );
    _l0Summaries.add(l0Summary);
    await _maybeCreateL1(locale: locale);
    return l0Summary;
  }

  String buildRecallContext({
    required String query,
    String? currentEventId,
    int maxEvents = 4,
  }) {
    if (_l0Summaries.isEmpty || maxEvents <= 0) {
      return '';
    }

    final normalizedQuery = _normalizeText(query);
    final queryTokens = _tokens(query);
    final candidateL0s = _candidateL0Summaries(
      normalizedQuery: normalizedQuery,
      queryTokens: queryTokens,
      currentEventId: currentEventId,
    );
    if (candidateL0s.isEmpty) {
      return '';
    }

    final selected = _rankL0Summaries(
      candidateL0s,
      normalizedQuery: normalizedQuery,
      queryTokens: queryTokens,
      maxEvents: maxEvents,
    );
    if (selected.isEmpty) {
      return '';
    }

    final parts = <String>[];
    for (final entry in selected) {
      final tags = entry.tags.join(', ');
      parts.add(
        '<event id="${_xmlEscape(entry.eventId)}" tags="${_xmlEscape(tags)}">',
      );
      parts.add(_xmlEscape(entry.summary));
      parts.add('</event>');
    }
    return parts.join('\n');
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'l0Summaries': _l0Summaries.map((entry) => entry.toJson()).toList(),
      'l1Summaries': _l1Summaries.map((entry) => entry.toJson()).toList(),
      'l1Counter': _l1Counter,
    };
  }

  void restoreFromJson(Map<String, dynamic>? json) {
    reset();
    if (json == null) {
      return;
    }

    _l0Summaries.addAll(
      (json['l0Summaries'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(LocalL0Summary.fromJson),
    );
    _l1Summaries.addAll(
      (json['l1Summaries'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(LocalL1Summary.fromJson),
    );
    _l1Counter = (json['l1Counter'] as num?)?.toInt() ?? 0;
  }

  Future<LocalL0Summary> _compressL0({
    required String locale,
    required String eventId,
    required String eventContent,
  }) async {
    final llmSummary = await _tryLlmL0(
      locale: locale,
      eventId: eventId,
      eventContent: eventContent,
    );
    return llmSummary ??
        _heuristicL0(eventId: eventId, eventContent: eventContent);
  }

  Future<void> _maybeCreateL1({required String locale}) async {
    final l0InL1 = _l1Summaries.fold<int>(
      0,
      (count, summary) => count + summary.l0Summaries.length,
    );
    final pending = _l0Summaries.skip(l0InL1).toList();
    if (pending.length < l1Threshold) {
      return;
    }

    final batch = pending.take(l1Threshold).toList();
    final l1Id = 'L1-${(_l1Counter + 1).toString().padLeft(3, '0')}';
    final l1Summary =
        await _tryLlmL1(locale: locale, l1Id: l1Id, l0Summaries: batch) ??
        _heuristicL1(l1Id: l1Id, l0Summaries: batch);
    _l1Counter += 1;
    _l1Summaries.add(l1Summary);
  }

  Future<LocalL0Summary?> _tryLlmL0({
    required String locale,
    required String eventId,
    required String eventContent,
  }) async {
    final config = await loadConfig();
    final slot = config.agents['l0_compressor'];
    final access = slot == null ? null : _slotAccess(slot);
    if (slot == null || access == null) {
      return null;
    }

    try {
      final response = await llmClient.completeChat(
        provider: access.provider,
        apiKey: access.apiKey,
        model: slot.model,
        temperature: slot.temperature,
        apiBase: slot.apiBase,
        extraParams: slot.extraParams,
        messages: <Map<String, String>>[
          <String, String>{
            'role': 'system',
            'content': _l0SystemPrompt(locale),
          },
          <String, String>{
            'role': 'user',
            'content': _l0Prompt(eventId: eventId, eventContent: eventContent),
          },
        ],
      );
      return _parseL0Summary(
        response,
        eventId: eventId,
        charCount: eventContent.length,
      );
    } catch (_) {
      return null;
    }
  }

  Future<LocalL1Summary?> _tryLlmL1({
    required String locale,
    required String l1Id,
    required List<LocalL0Summary> l0Summaries,
  }) async {
    final config = await loadConfig();
    final slot = config.agents['l1_compressor'];
    final access = slot == null ? null : _slotAccess(slot);
    if (slot == null || access == null) {
      return null;
    }

    try {
      final response = await llmClient.completeChat(
        provider: access.provider,
        apiKey: access.apiKey,
        model: slot.model,
        temperature: slot.temperature,
        apiBase: slot.apiBase,
        extraParams: slot.extraParams,
        messages: <Map<String, String>>[
          <String, String>{
            'role': 'system',
            'content': _l1SystemPrompt(locale),
          },
          <String, String>{
            'role': 'user',
            'content': _l1Prompt(l1Id: l1Id, l0Summaries: l0Summaries),
          },
        ],
      );
      return _parseL1Summary(response, l1Id: l1Id, l0Summaries: l0Summaries);
    } catch (_) {
      return null;
    }
  }

  LocalL0Summary _heuristicL0({
    required String eventId,
    required String eventContent,
  }) {
    final normalized = eventContent.replaceAll(RegExp(r'\s+'), ' ').trim();
    final summary = _trimWithEllipsis(normalized, 240);
    final tags = _extractTags('${eventId.replaceAll('_', ' ')} $normalized');
    return LocalL0Summary(
      eventId: eventId,
      summary: summary,
      tags: tags,
      charCount: eventContent.length,
    );
  }

  LocalL1Summary _heuristicL1({
    required String l1Id,
    required List<LocalL0Summary> l0Summaries,
  }) {
    final summaryParts = l0Summaries.map((entry) => entry.summary).toList();
    final tags = <String>{
      for (final entry in l0Summaries) ...entry.tags,
    }.take(12).toList();
    final firstId = l0Summaries.first.eventId;
    final lastId = l0Summaries.last.eventId;
    return LocalL1Summary(
      id: l1Id,
      covers: '$firstId-$lastId',
      summary: _trimWithEllipsis(summaryParts.join('\n\n'), 420),
      tags: tags,
      charCount: l0Summaries.fold<int>(
        0,
        (count, entry) => count + entry.charCount,
      ),
      l0Summaries: l0Summaries,
    );
  }

  List<LocalL0Summary> _candidateL0Summaries({
    required String normalizedQuery,
    required Set<String> queryTokens,
    required String? currentEventId,
  }) {
    final totalEvents = _l0Summaries.length;
    if (totalEvents < l1Threshold || _l1Summaries.isEmpty) {
      return _l0Summaries
          .where((entry) => entry.eventId != currentEventId)
          .toList();
    }

    final scoredL1 =
        _l1Summaries
            .map(
              (summary) => _ScoredL1Summary(
                summary: summary,
                score: _matchScore(
                  summary.summary,
                  summary.tags,
                  normalizedQuery: normalizedQuery,
                  queryTokens: queryTokens,
                ),
              ),
            )
            .where((entry) => entry.score > 0)
            .toList()
          ..sort((left, right) => right.score.compareTo(left.score));

    final candidates = <LocalL0Summary>[];
    for (final entry in scoredL1.take(2)) {
      candidates.addAll(entry.summary.l0Summaries);
    }

    final l0InL1 = _l1Summaries.fold<int>(
      0,
      (count, summary) => count + summary.l0Summaries.length,
    );
    candidates.addAll(_l0Summaries.skip(l0InL1));
    return candidates
        .where((entry) => entry.eventId != currentEventId)
        .toList();
  }

  List<LocalL0Summary> _rankL0Summaries(
    List<LocalL0Summary> candidates, {
    required String normalizedQuery,
    required Set<String> queryTokens,
    required int maxEvents,
  }) {
    final scored = candidates
        .map(
          (summary) => _ScoredL0Summary(
            summary: summary,
            score: _matchScore(
              summary.summary,
              summary.tags,
              normalizedQuery: normalizedQuery,
              queryTokens: queryTokens,
            ),
          ),
        )
        .toList();

    final filtered = scored.where((entry) => entry.score > 0).toList()
      ..sort((left, right) => right.score.compareTo(left.score));
    final selected = (filtered.isNotEmpty ? filtered : scored.reversed.toList())
        .take(maxEvents)
        .map((entry) => entry.summary)
        .toList();
    return selected.reversed.toList();
  }

  int _matchScore(
    String summary,
    List<String> tags, {
    required String normalizedQuery,
    required Set<String> queryTokens,
  }) {
    var score = 0;
    final normalizedSummary = _normalizeText(summary);
    if (normalizedQuery.isNotEmpty &&
        normalizedSummary.contains(normalizedQuery)) {
      score += 30;
    }
    final summaryTokens = _tokens('$summary ${tags.join(' ')}');
    final overlap = summaryTokens.intersection(queryTokens).length;
    if (overlap > 0) {
      score += overlap * 10;
    }
    return score;
  }

  _SlotAccess? _slotAccess(LlmSlotConfig slot) {
    final provider = _provider(slot.model);
    final apiKey = provider == null
        ? null
        : store.getApiKeys()[provider]?.trim();
    if (provider == null ||
        apiKey == null ||
        apiKey.isEmpty ||
        !llmClient.supportsProvider(provider, apiBase: slot.apiBase)) {
      return null;
    }
    return _SlotAccess(provider: provider, apiKey: apiKey);
  }

  String? _provider(String model) {
    final slash = model.indexOf('/');
    if (slash <= 0) {
      return null;
    }
    return model.substring(0, slash);
  }

  String _l0SystemPrompt(String locale) {
    final language = locale.startsWith('en')
        ? 'Return concise English JSON.'
        : 'Return concise Simplified Chinese JSON.';
    return '''
You compress one completed interactive-fiction event into a portable memory summary.
$language
Return only valid JSON:
{"summary":"...","tags":["..."]}
''';
  }

  String _l0Prompt({required String eventId, required String eventContent}) {
    return '''
<event_id>$eventId</event_id>
<event_content>
$eventContent
</event_content>
''';
  }

  String _l1SystemPrompt(String locale) {
    final language = locale.startsWith('en')
        ? 'Return concise English JSON.'
        : 'Return concise Simplified Chinese JSON.';
    return '''
You compress multiple event summaries into one higher-level memory bundle.
$language
Return only valid JSON:
{"summary":"...","tags":["..."]}
''';
  }

  String _l1Prompt({
    required String l1Id,
    required List<LocalL0Summary> l0Summaries,
  }) {
    return '''
<l1_id>$l1Id</l1_id>
<l0_summaries>
${jsonEncode(l0Summaries.map((entry) => entry.toJson()).toList())}
</l0_summaries>
''';
  }

  LocalL0Summary? _parseL0Summary(
    String raw, {
    required String eventId,
    required int charCount,
  }) {
    final decoded = _parseJsonObject(raw);
    if (decoded == null) {
      return null;
    }
    final summary = decoded['summary']?.toString().trim() ?? '';
    if (summary.isEmpty) {
      return null;
    }
    return LocalL0Summary(
      eventId: eventId,
      summary: summary,
      tags: _normalizeTags(decoded['tags']),
      charCount: charCount,
    );
  }

  LocalL1Summary? _parseL1Summary(
    String raw, {
    required String l1Id,
    required List<LocalL0Summary> l0Summaries,
  }) {
    final decoded = _parseJsonObject(raw);
    if (decoded == null) {
      return null;
    }
    final summary = decoded['summary']?.toString().trim() ?? '';
    if (summary.isEmpty) {
      return null;
    }
    final firstId = l0Summaries.first.eventId;
    final lastId = l0Summaries.last.eventId;
    return LocalL1Summary(
      id: l1Id,
      covers: '$firstId-$lastId',
      summary: summary,
      tags: _normalizeTags(decoded['tags']),
      charCount: l0Summaries.fold<int>(
        0,
        (count, entry) => count + entry.charCount,
      ),
      l0Summaries: l0Summaries,
    );
  }

  Map<String, dynamic>? _parseJsonObject(String raw) {
    final normalized = raw
        .trim()
        .replaceFirst(RegExp(r'^```json\s*'), '')
        .replaceFirst(RegExp(r'^```\s*'), '')
        .replaceFirst(RegExp(r'\s*```$'), '')
        .trim();
    try {
      final decoded = jsonDecode(normalized);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } catch (_) {}
    return null;
  }

  List<String> _normalizeTags(Object? value) {
    if (value is! List<dynamic>) {
      return const <String>[];
    }
    return value
        .whereType<String>()
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .take(12)
        .toList();
  }

  List<String> _extractTags(String text) {
    final tags = <String>[];
    final seen = <String>{};

    for (final match in RegExp(
      r'\b[A-Z][a-z]+(?:\s+[A-Z][a-z]+)*\b',
    ).allMatches(text)) {
      final value = match.group(0)?.trim() ?? '';
      if (value.isNotEmpty && seen.add(value.toLowerCase())) {
        tags.add(value);
      }
      if (tags.length >= 8) {
        return tags;
      }
    }

    for (final match in RegExp(r'[\u4e00-\u9fff]{2,8}').allMatches(text)) {
      final value = match.group(0)?.trim() ?? '';
      if (value.isNotEmpty && seen.add(value)) {
        tags.add(value);
      }
      if (tags.length >= 8) {
        return tags;
      }
    }

    for (final token in _tokens(text)) {
      if (seen.add(token)) {
        tags.add(token);
      }
      if (tags.length >= 8) {
        break;
      }
    }
    return tags;
  }

  Set<String> _tokens(String text) {
    final tokens = <String>{};
    for (final match in RegExp(
      r'[a-z0-9_]{3,}',
    ).allMatches(text.toLowerCase())) {
      tokens.add(match.group(0)!);
    }
    for (final match in RegExp(r'[\u4e00-\u9fff]{2,}').allMatches(text)) {
      tokens.add(match.group(0)!);
    }
    return tokens;
  }

  String _normalizeText(String value) {
    return value.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  String _trimWithEllipsis(String value, int maxLength) {
    if (value.length <= maxLength) {
      return value;
    }
    return '${value.substring(0, maxLength)}...';
  }
}

class _ScoredL0Summary {
  const _ScoredL0Summary({required this.summary, required this.score});

  final LocalL0Summary summary;
  final int score;
}

class _ScoredL1Summary {
  const _ScoredL1Summary({required this.summary, required this.score});

  final LocalL1Summary summary;
  final int score;
}

class _SlotAccess {
  const _SlotAccess({required this.provider, required this.apiKey});

  final String provider;
  final String apiKey;
}

String _xmlEscape(String value) {
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}
