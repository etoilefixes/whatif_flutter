import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;

import 'backend_api_contract.dart';
import 'local_lorebook_builder.dart';
import 'local_transition_builder.dart';
import 'local_worldpkg_extraction_enhancer.dart';

class LocalWorldPkgBuilder {
  const LocalWorldPkgBuilder({
    required this.outputDir,
    LocalLorebookBuilder? lorebookBuilder,
    LocalTransitionBuilder? transitionBuilder,
    LocalWorldPkgExtractionEnhancer? extractionEnhancer,
  }) : _lorebookBuilder = lorebookBuilder ?? const LocalLorebookBuilder(),
       _transitionBuilder = transitionBuilder ?? const LocalTransitionBuilder(),
       _extractionEnhancer = extractionEnhancer;

  final Directory outputDir;
  final LocalLorebookBuilder _lorebookBuilder;
  final LocalTransitionBuilder _transitionBuilder;
  final LocalWorldPkgExtractionEnhancer? _extractionEnhancer;

  Future<File> buildFromTextFile(String filePath) async {
    final sourceFile = File(filePath);
    if (!sourceFile.existsSync()) {
      throw ApiException('The selected text file does not exist.');
    }

    final extension = p.extension(sourceFile.path).toLowerCase();
    if (extension != '.txt' && extension != '.md') {
      throw const ApiException(
        'Only .txt and .md files can be converted locally.',
      );
    }

    await outputDir.create(recursive: true);

    final rawBytes = await sourceFile.readAsBytes();
    final rawText = utf8.decode(rawBytes, allowMalformed: true);
    final cleanText = _cleanText(rawText);
    if (cleanText.trim().isEmpty) {
      throw const ApiException(
        'The selected text file is empty after cleanup.',
      );
    }

    final locale = _detectLocale(cleanText);
    final title = _deriveTitle(sourceFile);
    final sentences = _splitSentences(cleanText);
    if (sentences.isEmpty) {
      throw const ApiException(
        'No usable sentences were found in the selected text.',
      );
    }

    final events = _buildEvents(sentences, locale);
    final heuristicLorebook = _lorebookBuilder.build(
      locale: locale,
      fullText: cleanText,
      sentences: sentences.map((sentence) => sentence.text).toList(),
    );
    final enhanced = await _extractionEnhancer?.enhance(
      locale: locale,
      title: title,
      fullText: cleanText,
      sentences: sentences.map((sentence) => sentence.text).toList(),
      heuristicEvents: events,
      heuristicLorebook: heuristicLorebook,
    );
    final resolvedEvents = enhanced?.events ?? events;
    final lorebook = enhanced?.lorebook ?? heuristicLorebook;
    final transitions = _transitionBuilder.build(
      events: resolvedEvents,
      sentences: sentences.map((sentence) => sentence.text).toList(),
      lorebook: lorebook,
    );
    final fullTextBytes = utf8.encode(cleanText);
    final outputFile = File(
      p.join(outputDir.path, _nextAvailableFilename('$title.wpkg')),
    );

    final archive = Archive()
      ..addFile(
        _jsonFile('metadata.json', <String, dynamic>{
          'title': title,
          'source_file': sourceFile.path,
          'total_characters': cleanText.length,
          'total_sentences': sentences.length,
          'event_count': resolvedEvents.length,
          'character_count': lorebook.characters.length,
          'location_count': lorebook.locations.length,
          'item_count': lorebook.items.length,
          'knowledge_count': lorebook.knowledge.length,
          'transition_count': transitions.length,
          'created_at': DateTime.now().toIso8601String(),
        }),
      )
      ..addFile(
        ArchiveFile(
          'source/full_text.txt',
          fullTextBytes.length,
          fullTextBytes,
        ),
      )
      ..addFile(
        _jsonFile('source/sentences.json', <String, dynamic>{
          'total_sentences': sentences.length,
          'total_characters': cleanText.length,
          'sentences': sentences
              .map(
                (sentence) => <String, dynamic>{
                  'index': sentence.index,
                  'text': sentence.text,
                  'start': sentence.start,
                  'end': sentence.end,
                },
              )
              .toList(),
        }),
      )
      ..addFile(
        _jsonFile('events/events.json', <String, dynamic>{
          'events': resolvedEvents,
        }),
      )
      ..addFile(
        _jsonFile('lorebook/characters.json', <String, dynamic>{
          'characters': lorebook.characters,
        }),
      )
      ..addFile(
        _jsonFile('lorebook/locations.json', <String, dynamic>{
          'locations': lorebook.locations,
        }),
      )
      ..addFile(
        _jsonFile('lorebook/items.json', <String, dynamic>{
          'items': lorebook.items,
        }),
      )
      ..addFile(
        _jsonFile('lorebook/knowledge.json', <String, dynamic>{
          'knowledge': lorebook.knowledge,
        }),
      )
      ..addFile(
        _jsonFile('transitions/transitions.json', <String, dynamic>{
          'transitions': transitions,
        }),
      );

    final encoded = ZipEncoder().encode(archive);
    if (encoded.isEmpty) {
      throw const ApiException('Failed to build the local world package.');
    }

    await outputFile.writeAsBytes(encoded, flush: true);
    return outputFile;
  }

  String _cleanText(String text) {
    final withoutChapterHeadings = text
        .replaceAll(
          RegExp(
            r'^\s*\u7b2c[\u4e00-\u9fff\d]+[\u7ae0\u8282\u56de\u5377\u7bc7\u5e55\u96c6].*$',
            multiLine: true,
          ),
          '',
        )
        .replaceAll(
          RegExp(
            r'^\s*chapter\s+\d+.*$',
            caseSensitive: false,
            multiLine: true,
          ),
          '',
        )
        .replaceAll(RegExp(r'^\s*#+\s+.*$', multiLine: true), '');

    final normalizedNewlines = withoutChapterHeadings
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n');

    final trimmedLines = normalizedNewlines
        .split('\n')
        .map((line) => line.trimRight())
        .join('\n');

    return trimmedLines.trim();
  }

  String _detectLocale(String text) {
    final chineseMatches = RegExp(r'[\u4E00-\u9FFF]').allMatches(text).length;
    final latinMatches = RegExp(r'[A-Za-z]').allMatches(text).length;
    return chineseMatches >= latinMatches ? 'zh-CN' : 'en';
  }

  String _deriveTitle(File sourceFile) {
    final stem = p.basenameWithoutExtension(sourceFile.path).trim();
    return stem.isEmpty ? 'WhatIf Story' : stem;
  }

  List<_LocalSentence> _splitSentences(String text) {
    final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final sentences = <_LocalSentence>[];
    var buffer = StringBuffer();
    var sentenceStart = 0;
    var hasVisibleChar = false;

    void flush(int end) {
      final value = buffer.toString().trim();
      if (value.isNotEmpty) {
        sentences.add(
          _LocalSentence(
            index: sentences.length + 1,
            text: value,
            start: sentenceStart,
            end: end,
          ),
        );
      }
      buffer = StringBuffer();
      hasVisibleChar = false;
    }

    for (var index = 0; index < normalized.length; index += 1) {
      final char = normalized[index];
      if (!hasVisibleChar && char.trim().isNotEmpty) {
        sentenceStart = index;
        hasVisibleChar = true;
      }

      buffer.write(char);

      final next = index + 1 < normalized.length ? normalized[index + 1] : '';
      final endsSentence =
          _isSentenceEndingPunctuation(char) && !_isClosingQuote(next);
      final endsParagraph = char == '\n' && next == '\n';

      if (endsSentence || endsParagraph) {
        var end = index + 1;
        while (end < normalized.length && _isClosingQuote(normalized[end])) {
          buffer.write(normalized[end]);
          end += 1;
        }
        flush(end);
        index = end - 1;
      }
    }

    if (buffer.isNotEmpty) {
      flush(normalized.length);
    }

    return sentences;
  }

  bool _isSentenceEndingPunctuation(String char) {
    return const <String>{
      '\u3002',
      '\uff01',
      '\uff1f',
      '!',
      '?',
      ';',
      '\uff1b',
      '.',
    }.contains(char);
  }

  bool _isClosingQuote(String char) {
    return const <String>{
      '"',
      '\'',
      '\u201d',
      '\u2019',
      '\u300d',
      '\u300f',
      '\uff09',
      ')',
      '\u3011',
      ']',
    }.contains(char);
  }

  List<Map<String, dynamic>> _buildEvents(
    List<_LocalSentence> sentences,
    String locale,
  ) {
    final chunks = <List<_LocalSentence>>[];
    const targetChunkSize = 6;
    var cursor = 0;
    while (cursor < sentences.length) {
      final remaining = sentences.length - cursor;
      final size = remaining <= 8 ? remaining : targetChunkSize;
      chunks.add(sentences.sublist(cursor, cursor + size));
      cursor += size;
    }

    return List<Map<String, dynamic>>.generate(chunks.length, (index) {
      final chunk = chunks[index];
      final first = chunk.first;
      final last = chunk.last;
      final phaseRanges = _defaultPhaseRanges(first.index, last.index);
      final importance =
          chunks.length == 1 || index == 0 || index == chunks.length - 1
          ? 'key'
          : 'normal';
      final eventDecisionText = _eventDecisionText(chunk, locale);

      final setupText =
          _rangeTextFromChunk(chunk, phaseRanges['setup']) ?? eventDecisionText;
      final confrontationText =
          _rangeTextFromChunk(chunk, phaseRanges['confrontation']) ??
          eventDecisionText;
      final resolutionText =
          _rangeTextFromChunk(chunk, phaseRanges['resolution']) ??
          eventDecisionText;

      return <String, dynamic>{
        'id': 'event_${index + 1}',
        'type': 'interactive',
        'goal': _eventGoal(chunk, locale),
        'sentence_range': <int>[first.index, last.index],
        'importance': importance,
        'decision_text': eventDecisionText,
        'phases': <String, dynamic>{
          'setup': <String, dynamic>{
            'sentence_range': phaseRanges['setup'],
            'description': '',
            'decision_text': _trimToLength(setupText, 120),
          },
          'confrontation': <String, dynamic>{
            'sentence_range': phaseRanges['confrontation'],
            'description': '',
            'decision_text': _trimToLength(confrontationText, 120),
          },
          'resolution': <String, dynamic>{
            'sentence_range': phaseRanges['resolution'],
            'description': '',
            'decision_text': _trimToLength(resolutionText, 120),
          },
        },
      };
    });
  }

  String _eventGoal(List<_LocalSentence> chunk, String locale) {
    final seed = _trimToLength(chunk.first.text, 40);
    if (locale.startsWith('en')) {
      return 'Change what happens next around "$seed".';
    }
    return '\u56f4\u7ed5\u201c$seed\u201d\u6539\u5199\u63a5\u4e0b\u6765'
        '\u7684\u5c40\u52bf\u3002';
  }

  String _eventDecisionText(List<_LocalSentence> chunk, String locale) {
    final seed = _trimToLength(chunk.first.text, 36);
    if (locale.startsWith('en')) {
      return 'Decide how to respond to "$seed".';
    }
    return '\u51b3\u5b9a\u5982\u4f55\u56de\u5e94\u201c$seed\u201d\u3002';
  }

  String _trimToLength(String text, int maxLength) {
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= maxLength) {
      return normalized;
    }
    return '${normalized.substring(0, maxLength)}...';
  }

  String _nextAvailableFilename(String desiredName) {
    final sanitizedBase = _sanitizeFilename(
      p.basenameWithoutExtension(desiredName),
    );
    final extension = p.extension(desiredName).isEmpty
        ? '.wpkg'
        : p.extension(desiredName);

    var candidate = '$sanitizedBase$extension';
    var counter = 2;
    while (File(p.join(outputDir.path, candidate)).existsSync()) {
      candidate = '$sanitizedBase-$counter$extension';
      counter += 1;
    }
    return candidate;
  }

  String _sanitizeFilename(String value) {
    final sanitized = value
        .replaceAll(RegExp(r'[<>:"/\\|?*]'), '_')
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ');
    if (sanitized.isEmpty) {
      return 'whatif-story';
    }
    return sanitized;
  }

  Map<String, List<int>?> _defaultPhaseRanges(int start, int end) {
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
    final setupEnd = start + setupLength - 1;
    final confrontationStart = setupEnd + 1;
    final confrontationEnd = confrontationStart + confrontationLength - 1;
    final resolutionStart = confrontationEnd + 1;

    return <String, List<int>?>{
      'setup': <int>[start, setupEnd],
      'confrontation': <int>[confrontationStart, confrontationEnd],
      'resolution': <int>[resolutionStart, end],
    };
  }

  String? _rangeTextFromChunk(
    List<_LocalSentence> chunk,
    List<int>? sentenceRange,
  ) {
    if (sentenceRange == null || sentenceRange.length != 2) {
      return null;
    }
    final parts = chunk
        .where(
          (sentence) =>
              sentence.index >= sentenceRange.first &&
              sentence.index <= sentenceRange.last,
        )
        .map((sentence) => sentence.text)
        .toList();
    if (parts.isEmpty) {
      return null;
    }
    return parts.join(' ');
  }

  ArchiveFile _jsonFile(String name, Map<String, dynamic> json) {
    final bytes = utf8.encode(jsonEncode(json));
    return ArchiveFile(name, bytes.length, bytes);
  }
}

class _LocalSentence {
  const _LocalSentence({
    required this.index,
    required this.text,
    required this.start,
    required this.end,
  });

  final int index;
  final String text;
  final int start;
  final int end;
}
