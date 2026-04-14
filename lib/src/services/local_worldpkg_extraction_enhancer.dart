import 'dart:convert';

import '../models.dart';
import 'config_store.dart';
import 'integrated_llm_client.dart';
import 'local_lorebook_builder.dart';

class LocalWorldPkgExtractionData {
  const LocalWorldPkgExtractionData({
    required this.events,
    required this.lorebook,
  });

  final List<Map<String, dynamic>> events;
  final LocalLorebookBuildResult lorebook;
}

abstract class LocalWorldPkgExtractionEnhancer {
  const LocalWorldPkgExtractionEnhancer();

  Future<LocalWorldPkgExtractionData?> enhance({
    required String locale,
    required String title,
    required String fullText,
    required List<String> sentences,
    required List<Map<String, dynamic>> heuristicEvents,
    required LocalLorebookBuildResult heuristicLorebook,
  });
}

class LocalLlmWorldPkgExtractionEnhancer
    implements LocalWorldPkgExtractionEnhancer {
  LocalLlmWorldPkgExtractionEnhancer({
    required this.store,
    required this.llmClient,
    required this.loadConfig,
  });

  final ConfigStore store;
  final IntegratedLlmClient llmClient;
  final Future<LlmConfigMap> Function() loadConfig;

  @override
  Future<LocalWorldPkgExtractionData?> enhance({
    required String locale,
    required String title,
    required String fullText,
    required List<String> sentences,
    required List<Map<String, dynamic>> heuristicEvents,
    required LocalLorebookBuildResult heuristicLorebook,
  }) async {
    final config = await loadConfig();
    final refinedEvents = await _refineEvents(
      locale: locale,
      title: title,
      sentences: sentences,
      heuristicEvents: heuristicEvents,
      config: config,
    );
    final refinedLorebook = await _refineLorebook(
      locale: locale,
      title: title,
      fullText: fullText,
      heuristicEvents: heuristicEvents,
      heuristicLorebook: heuristicLorebook,
      config: config,
    );

    if (refinedEvents == null && refinedLorebook == null) {
      return null;
    }

    return LocalWorldPkgExtractionData(
      events: refinedEvents ?? heuristicEvents,
      lorebook: refinedLorebook ?? heuristicLorebook,
    );
  }

  Future<List<Map<String, dynamic>>?> _refineEvents({
    required String locale,
    required String title,
    required List<String> sentences,
    required List<Map<String, dynamic>> heuristicEvents,
    required LlmConfigMap config,
  }) async {
    final eventSlot = config.extractors['event_extractor'];
    final decisionSlot = config.extractors['decision_text_extractor'];

    List<Map<String, dynamic>> merged = heuristicEvents
        .map((event) => _deepCopyMap(event))
        .toList();

    if (eventSlot != null) {
      final access = _slotAccess(eventSlot);
      if (access != null) {
        try {
          final response = await llmClient.completeChat(
            provider: access.provider,
            apiKey: access.apiKey,
            model: eventSlot.model,
            temperature: eventSlot.temperature,
            apiBase: eventSlot.apiBase,
            extraParams: eventSlot.extraParams,
            messages: <Map<String, String>>[
              <String, String>{
                'role': 'system',
                'content': _eventSystemPrompt(locale),
              },
              <String, String>{
                'role': 'user',
                'content': _eventPrompt(
                  locale: locale,
                  title: title,
                  sentences: sentences,
                  heuristicEvents: heuristicEvents,
                ),
              },
            ],
          );
          final parsed = _parseEventRefinements(response);
          if (parsed != null && parsed.isNotEmpty) {
            final segmented = _normalizeSegmentedEvents(
              candidates: parsed,
              sentences: sentences,
              locale: locale,
            );
            if (segmented != null && segmented.isNotEmpty) {
              merged = segmented;
            } else {
              merged = _mergeEventRefinements(merged, parsed);
            }
          }
        } catch (_) {}
      }
    }

    if (decisionSlot == null) {
      return merged;
    }

    final decisionAccess = _slotAccess(decisionSlot);
    if (decisionAccess == null) {
      return merged;
    }

    for (var index = 0; index < merged.length; index += 1) {
      final event = merged[index];
      final eventRange = (event['sentence_range'] as List<dynamic>? ?? const [])
          .whereType<num>()
          .map((value) => value.toInt())
          .toList();
      if (eventRange.length == 2) {
        final eventText = _rangeText(
          sentences,
          eventRange.first,
          eventRange.last,
        );
        final compressed = await _compressDecisionText(
          locale: locale,
          access: decisionAccess,
          slot: decisionSlot,
          text: eventText,
        );
        if (compressed != null) {
          event['decision_text'] = compressed;
        }
      }

      final phases = _mapValue(event['phases']);
      if (phases == null) {
        continue;
      }

      for (final phaseName in const <String>[
        'setup',
        'confrontation',
        'resolution',
      ]) {
        final phase = _mapValue(phases[phaseName]);
        if (phase == null) {
          continue;
        }
        final range = (phase['sentence_range'] as List<dynamic>? ?? const [])
            .whereType<num>()
            .map((value) => value.toInt())
            .toList();
        if (range.length != 2) {
          continue;
        }
        final phaseText = _rangeText(sentences, range.first, range.last);
        final compressed = await _compressDecisionText(
          locale: locale,
          access: decisionAccess,
          slot: decisionSlot,
          text: phaseText,
        );
        if (compressed != null) {
          phase['decision_text'] = compressed;
        }
      }
    }

    return merged;
  }

  Future<LocalLorebookBuildResult?> _refineLorebook({
    required String locale,
    required String title,
    required String fullText,
    required List<Map<String, dynamic>> heuristicEvents,
    required LocalLorebookBuildResult heuristicLorebook,
    required LlmConfigMap config,
  }) async {
    final slot = config.extractors['lorebook_extractor'];
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
            'content': _lorebookSystemPrompt(locale),
          },
          <String, String>{
            'role': 'user',
            'content': _lorebookPrompt(
              locale: locale,
              title: title,
              fullText: fullText,
              heuristicEvents: heuristicEvents,
              heuristicLorebook: heuristicLorebook,
            ),
          },
        ],
      );
      return _parseLorebookResult(response);
    } catch (_) {
      return null;
    }
  }

  Future<String?> _compressDecisionText({
    required String locale,
    required _SlotAccess access,
    required LlmSlotConfig slot,
    required String text,
  }) async {
    final normalized = text.trim();
    if (normalized.isEmpty) {
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
            'content': _decisionTextSystemPrompt(locale),
          },
          <String, String>{
            'role': 'user',
            'content': _decisionTextPrompt(normalized),
          },
        ],
      );
      final compact = response.replaceAll(RegExp(r'\s+'), ' ').trim();
      return compact.isEmpty ? null : compact;
    } catch (_) {
      return null;
    }
  }

  _SlotAccess? _slotAccess(LlmSlotConfig slot) {
    final provider = _provider(slot.model);
    final creds = provider == null
        ? null
        : store.getProviderCredentials(provider);
    if (provider == null ||
        creds == null ||
        creds.apiKey.isEmpty ||
        !llmClient.supportsProvider(provider, apiBase: slot.apiBase ?? creds.apiUrl)) {
      return null;
    }
    return _SlotAccess(provider: provider, apiKey: creds.apiKey);
  }

  String? _provider(String model) {
    final slash = model.indexOf('/');
    if (slash <= 0) {
      return null;
    }
    return model.substring(0, slash);
  }

  String _eventSystemPrompt(String locale) {
    final language = locale.startsWith('en')
        ? 'Return concise English JSON.'
        : 'Return concise Simplified Chinese JSON.';
    return '''
You improve local story event extraction for a local interactive fiction package.
$language
Heuristic events are only a starting point. You may keep them, refine them, split them, or merge them.
If you change event count or sentence ranges, return a complete event list with valid sentence ranges.
Keep event sentence ranges strictly increasing, non-overlapping, and within the available sentence indexes.
For every interactive event, include setup, confrontation, and resolution phase objects.
Return only valid JSON:
{"events":[{"id":"event_1","type":"interactive","goal":"...","sentence_range":[1,3],"importance":"key","decision_text":"...","soft_guide_hints":["..."],"phases":{"setup":{"sentence_range":[1,1],"description":"...","decision_text":"..."},"confrontation":{"sentence_range":[2,2],"description":"...","decision_text":"..."},"resolution":{"sentence_range":[3,3],"description":"...","decision_text":"..."}}}]}
''';
  }

  String _eventPrompt({
    required String locale,
    required String title,
    required List<String> sentences,
    required List<Map<String, dynamic>> heuristicEvents,
  }) {
    final sentencePayload = List<Map<String, dynamic>>.generate(
      sentences.length,
      (index) => <String, dynamic>{
        'index': index + 1,
        'text': sentences[index],
      },
    );

    return '''
<locale>$locale</locale>
<title>$title</title>

Return either:
1. a full re-segmented event list with sentence ranges, or
2. refinement fields for the heuristic ids when you do not want to change segmentation.

<sentences>
${jsonEncode(sentencePayload)}
</sentences>

<heuristic_events>
${jsonEncode(heuristicEvents)}
</heuristic_events>
''';
  }

  String _decisionTextSystemPrompt(String locale) {
    return locale.startsWith('en')
        ? 'Compress the passage into one vivid, actionable summary sentence.'
        : '将片段压缩成一句清晰、有动作感的摘要。';
  }

  String _decisionTextPrompt(String text) {
    return '''
Rewrite this source passage as one concise summary sentence without markdown.

$text
''';
  }

  String _lorebookSystemPrompt(String locale) {
    final language = locale.startsWith('en')
        ? 'Return English JSON.'
        : 'Return Simplified Chinese JSON.';
    return '''
You refine heuristic lorebook extraction for a local interactive fiction package.
$language
Return only valid JSON:
{"characters":[...],"locations":[...],"items":[...],"knowledge":[...]}
Keep the structure compact and valid.
''';
  }

  String _lorebookPrompt({
    required String locale,
    required String title,
    required String fullText,
    required List<Map<String, dynamic>> heuristicEvents,
    required LocalLorebookBuildResult heuristicLorebook,
  }) {
    return '''
<locale>$locale</locale>
<title>$title</title>

<heuristic_events>
${jsonEncode(heuristicEvents)}
</heuristic_events>

<heuristic_lorebook>
${jsonEncode(<String, dynamic>{'characters': heuristicLorebook.characters, 'locations': heuristicLorebook.locations, 'items': heuristicLorebook.items, 'knowledge': heuristicLorebook.knowledge})}
</heuristic_lorebook>

<full_text>
$fullText
</full_text>
''';
  }

  List<Map<String, dynamic>>? _parseEventRefinements(String raw) {
    final decoded = _parseJsonObject(raw);
    final events = decoded?['events'];
    if (events is! List<dynamic>) {
      return null;
    }
    return events.map(_mapValue).whereType<Map<String, dynamic>>().toList();
  }

  List<Map<String, dynamic>>? _normalizeSegmentedEvents({
    required List<Map<String, dynamic>> candidates,
    required List<String> sentences,
    required String locale,
  }) {
    if (candidates.isEmpty || sentences.isEmpty) {
      return null;
    }

    final normalized = <Map<String, dynamic>>[];
    final usedIds = <String>{};
    var previousEnd = 0;

    for (var index = 0; index < candidates.length; index += 1) {
      final candidate = candidates[index];
      final range = _normalizeRange(
        candidate['sentence_range'],
        minValue: 1,
        maxValue: sentences.length,
      );
      if (range == null || range.first <= previousEnd) {
        return null;
      }

      final type = candidate['type']?.toString().trim() == 'narrative'
          ? 'narrative'
          : 'interactive';
      final eventText = _rangeText(sentences, range.first, range.last);
      final defaultDecisionText = _defaultEventDecisionText(eventText, locale);
      final event = <String, dynamic>{
        'id': _uniqueEventId(candidate['id'], index + 1, usedIds),
        'type': type,
        'goal': _nonEmptyOr(
          candidate['goal'],
          _defaultEventGoal(eventText, locale),
        ),
        'sentence_range': <int>[range.first, range.last],
        'importance': _normalizeImportance(
          candidate['importance'],
          index: index,
          total: candidates.length,
        ),
        'decision_text': _nonEmptyOr(
          candidate['decision_text'],
          defaultDecisionText,
        ),
        'soft_guide_hints': _normalizeStringList(
          candidate['soft_guide_hints'],
          limit: 4,
        ),
      };

      final image = _stringValue(candidate['image']);
      if (image.isNotEmpty) {
        event['image'] = image;
      }

      if (type == 'interactive') {
        event['phases'] = _normalizeInteractivePhases(
          rawPhases: _mapValue(candidate['phases']),
          eventRange: range,
          sentences: sentences,
          fallbackDecisionText: defaultDecisionText,
        );
      } else {
        final narrative = _stringValue(candidate['narrative']);
        if (narrative.isNotEmpty) {
          event['narrative'] = narrative;
        }
      }

      normalized.add(event);
      previousEnd = range.last;
    }

    return normalized;
  }

  Map<String, dynamic> _normalizeInteractivePhases({
    required Map<String, dynamic>? rawPhases,
    required List<int> eventRange,
    required List<String> sentences,
    required String fallbackDecisionText,
  }) {
    final validRanges = _validatedPhaseRanges(
      rawPhases,
      minValue: eventRange.first,
      maxValue: eventRange.last,
    );
    final fallbackRanges = _defaultPhaseRanges(eventRange);
    final phases = <String, dynamic>{};

    for (final phaseName in const <String>[
      'setup',
      'confrontation',
      'resolution',
    ]) {
      final phaseData = _mapValue(rawPhases?[phaseName]);
      final range = validRanges?[phaseName] ?? fallbackRanges[phaseName];
      final text = range == null
          ? fallbackDecisionText
          : _rangeText(sentences, range.first, range.last);
      phases[phaseName] = <String, dynamic>{
        'sentence_range': range,
        'description': _stringValue(phaseData?['description']),
        'decision_text': _nonEmptyOr(
          phaseData?['decision_text'],
          _trimToLength(text, 120),
        ),
      };
    }

    return phases;
  }

  Map<String, List<int>>? _validatedPhaseRanges(
    Map<String, dynamic>? rawPhases, {
    required int minValue,
    required int maxValue,
  }) {
    if (rawPhases == null) {
      return null;
    }

    final setup = _normalizeRange(
      _mapValue(rawPhases['setup'])?['sentence_range'],
      minValue: minValue,
      maxValue: maxValue,
    );
    final confrontation = _normalizeRange(
      _mapValue(rawPhases['confrontation'])?['sentence_range'],
      minValue: minValue,
      maxValue: maxValue,
    );
    final resolution = _normalizeRange(
      _mapValue(rawPhases['resolution'])?['sentence_range'],
      minValue: minValue,
      maxValue: maxValue,
    );
    if (setup == null || confrontation == null || resolution == null) {
      return null;
    }
    if (setup.first != minValue ||
        setup.last + 1 != confrontation.first ||
        confrontation.last + 1 != resolution.first ||
        resolution.last != maxValue) {
      return null;
    }

    return <String, List<int>>{
      'setup': setup,
      'confrontation': confrontation,
      'resolution': resolution,
    };
  }

  List<Map<String, dynamic>> _mergeEventRefinements(
    List<Map<String, dynamic>> heuristicEvents,
    List<Map<String, dynamic>> refinements,
  ) {
    final byId = <String, Map<String, dynamic>>{
      for (final refinement in refinements)
        if ((refinement['id'] as String?)?.isNotEmpty == true)
          refinement['id'] as String: refinement,
    };

    return heuristicEvents.map((event) {
      final eventId = event['id'] as String? ?? '';
      final refinement = byId[eventId];
      if (refinement == null) {
        return event;
      }

      final merged = _deepCopyMap(event);
      final type = refinement['type'] as String?;
      if (type == 'interactive' || type == 'narrative') {
        merged['type'] = type;
      }

      for (final key in const <String>['goal', 'importance', 'decision_text']) {
        final value = refinement[key]?.toString().trim();
        if (value != null && value.isNotEmpty) {
          merged[key] = value;
        }
      }

      final hints = refinement['soft_guide_hints'];
      if (hints is List<dynamic>) {
        final normalizedHints = hints
            .whereType<String>()
            .map((value) => value.trim())
            .where((value) => value.isNotEmpty)
            .take(4)
            .toList();
        if (normalizedHints.isNotEmpty) {
          merged['soft_guide_hints'] = normalizedHints;
        }
      }

      final mergedPhases = _mapValue(merged['phases']);
      final refinedPhases = _mapValue(refinement['phases']);
      if (mergedPhases != null && refinedPhases != null) {
        for (final phaseName in const <String>[
          'setup',
          'confrontation',
          'resolution',
        ]) {
          final mergedPhase = _mapValue(mergedPhases[phaseName]);
          final refinedPhase = _mapValue(refinedPhases[phaseName]);
          if (mergedPhase == null || refinedPhase == null) {
            continue;
          }

          for (final key in const <String>['description', 'decision_text']) {
            final value = refinedPhase[key]?.toString().trim();
            if (value != null && value.isNotEmpty) {
              mergedPhase[key] = value;
            }
          }
        }
      }

      return merged;
    }).toList();
  }

  LocalLorebookBuildResult? _parseLorebookResult(String raw) {
    final decoded = _parseJsonObject(raw);
    if (decoded == null) {
      return null;
    }

    final characters = _normalizeEntityList(decoded['characters']);
    if (characters.isEmpty) {
      return null;
    }

    return LocalLorebookBuildResult(
      characters: characters,
      locations: _normalizeEntityList(decoded['locations']),
      items: _normalizeEntityList(decoded['items']),
      knowledge: _normalizeEntityList(decoded['knowledge']),
    );
  }

  List<Map<String, dynamic>> _normalizeEntityList(Object? value) {
    if (value is! List<dynamic>) {
      return const <Map<String, dynamic>>[];
    }
    return value.map(_mapValue).whereType<Map<String, dynamic>>().toList();
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
      return _mapValue(decoded);
    } catch (_) {
      return null;
    }
  }

  String _rangeText(List<String> sentences, int start, int end) {
    final startIndex = start < 1 ? 0 : start - 1;
    final endIndex = end > sentences.length ? sentences.length : end;
    if (startIndex >= endIndex) {
      return '';
    }
    return sentences.sublist(startIndex, endIndex).join(' ');
  }

  String _defaultEventGoal(String text, String locale) {
    final seed = _trimToLength(text, 40);
    if (locale.startsWith('en')) {
      return 'Change what happens next around "$seed".';
    }
    return '围绕“$seed”改变接下来的局势。';
  }

  String _defaultEventDecisionText(String text, String locale) {
    final seed = _trimToLength(text, 36);
    if (locale.startsWith('en')) {
      return 'Decide how to respond to "$seed".';
    }
    return '决定如何回应“$seed”。';
  }

  String _normalizeImportance(
    Object? value, {
    required int index,
    required int total,
  }) {
    final normalized = _stringValue(value);
    if (normalized == 'key' ||
        normalized == 'normal' ||
        normalized == 'optional') {
      return normalized;
    }
    return total == 1 || index == 0 || index == total - 1 ? 'key' : 'normal';
  }

  String _uniqueEventId(Object? value, int index, Set<String> usedIds) {
    var normalized = _normalizeIdentifier(_stringValue(value));
    if (normalized.isEmpty || usedIds.contains(normalized)) {
      normalized = 'event_$index';
    }
    while (usedIds.contains(normalized)) {
      normalized = '${normalized}_$index';
    }
    usedIds.add(normalized);
    return normalized;
  }

  String _normalizeIdentifier(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
  }

  Map<String, List<int>?> _defaultPhaseRanges(List<int> eventRange) {
    final start = eventRange.first;
    final end = eventRange.last;
    final length = end - start + 1;
    if (length <= 0) {
      return const <String, List<int>?>{
        'setup': null,
        'confrontation': null,
        'resolution': null,
      };
    }
    if (length == 1) {
      return <String, List<int>?>{
        'setup': <int>[start, start],
        'confrontation': null,
        'resolution': null,
      };
    }
    if (length == 2) {
      return <String, List<int>?>{
        'setup': <int>[start, start],
        'confrontation': <int>[start + 1, end],
        'resolution': null,
      };
    }

    final base = length ~/ 3;
    final extra = length % 3;
    final setupLength = base;
    final confrontationLength = base + (extra > 0 ? 1 : 0);
    final resolutionLength = base + (extra > 1 ? 1 : 0);
    final setupEnd = start + setupLength - 1;
    final confrontationStart = setupEnd + 1;
    final confrontationEnd = confrontationStart + confrontationLength - 1;
    final resolutionStart = confrontationEnd + 1;
    final resolutionEnd = resolutionStart + resolutionLength - 1;

    return <String, List<int>?>{
      'setup': <int>[start, setupEnd],
      'confrontation': <int>[confrontationStart, confrontationEnd],
      'resolution': <int>[
        resolutionStart,
        resolutionEnd > end ? end : resolutionEnd,
      ],
    };
  }

  List<int>? _normalizeRange(
    Object? value, {
    required int minValue,
    required int maxValue,
  }) {
    final range = (value as List<dynamic>?)
        ?.whereType<num>()
        .map((item) => item.toInt())
        .toList();
    if (range == null || range.length != 2) {
      return null;
    }
    if (range.first < minValue ||
        range.last > maxValue ||
        range.first > range.last) {
      return null;
    }
    return <int>[range.first, range.last];
  }

  List<String> _normalizeStringList(Object? value, {required int limit}) {
    if (value is! List<dynamic>) {
      return const <String>[];
    }
    return value
        .whereType<String>()
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .take(limit)
        .toList();
  }

  String _nonEmptyOr(Object? value, String fallback) {
    final normalized = _stringValue(value);
    return normalized.isEmpty ? fallback : normalized;
  }

  String _stringValue(Object? value) {
    return value?.toString().trim() ?? '';
  }

  String _trimToLength(String text, int maxLength) {
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= maxLength) {
      return normalized;
    }
    return '${normalized.substring(0, maxLength)}...';
  }
}

class _SlotAccess {
  const _SlotAccess({required this.provider, required this.apiKey});

  final String provider;
  final String apiKey;
}

Map<String, dynamic> _deepCopyMap(Map<String, dynamic> value) {
  final encoded = jsonEncode(value);
  final decoded = jsonDecode(encoded);
  return decoded as Map<String, dynamic>;
}

Map<String, dynamic>? _mapValue(Object? value) {
  if (value is Map<String, dynamic>) {
    return value;
  }
  if (value is Map) {
    return value.map(
      (key, nestedValue) => MapEntry(key.toString(), nestedValue),
    );
  }
  return null;
}
