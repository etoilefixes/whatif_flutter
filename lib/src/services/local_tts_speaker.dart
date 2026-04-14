import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../models.dart';

class LocalTtsSpeaker {
  LocalTtsSpeaker({FlutterTts? engine}) : _tts = engine ?? FlutterTts() {
    _tts.setStartHandler(() {
      _speaking = true;
    });
    _tts.setCompletionHandler(_finishPlayback);
    _tts.setCancelHandler(_finishPlayback);
    _tts.setErrorHandler((_) {
      _finishPlayback();
    });
  }

  final FlutterTts _tts;

  bool _speaking = false;
  bool _notifyOnComplete = false;

  VoidCallback? onComplete;

  bool get isSpeaking => _speaking;

  Future<List<VoiceInfo>> listVoices({String? locale}) async {
    final voices = await _loadVoices(locale: locale);
    if (voices.isNotEmpty) {
      return voices
          .map(
            (voice) => VoiceInfo(
              name: voice.name,
              gender: voice.gender,
              friendlyName: voice.friendlyName,
            ),
          )
          .toList();
    }
    return _fallbackVoices(locale: locale);
  }

  Future<bool> speakNarration(
    String text, {
    String? locale,
    String? voice,
  }) async {
    final normalized = _normalizeNarrationText(text);
    if (normalized.isEmpty) {
      return false;
    }

    await stop();

    final voices = await _loadVoices(locale: locale);
    final resolvedVoice = _resolveVoice(
      voices,
      requestedName: voice,
      locale: locale,
    );
    final resolvedLocale = _resolveLocale(
      requestedLocale: locale,
      voiceLocale: resolvedVoice?.locale,
    );

    try {
      await _tts.awaitSpeakCompletion(false);
    } catch (_) {}

    try {
      await _tts.setLanguage(resolvedLocale);
    } catch (_) {}

    try {
      await _tts.setSpeechRate(_speechRateForLocale(resolvedLocale));
    } catch (_) {}

    if (resolvedVoice != null &&
        !resolvedVoice.name.startsWith('system-default-')) {
      try {
        await _tts.setVoice(<String, String>{
          'name': resolvedVoice.name,
          if (resolvedVoice.locale.isNotEmpty) 'locale': resolvedVoice.locale,
        });
      } catch (_) {}
    }

    _notifyOnComplete = true;
    _speaking = true;
    try {
      await _tts.speak(normalized);
      return true;
    } catch (_) {
      _speaking = false;
      _notifyOnComplete = false;
      return false;
    }
  }

  Future<void> stop() async {
    _notifyOnComplete = false;
    _speaking = false;
    try {
      await _tts.stop();
    } catch (_) {}
  }

  Future<void> dispose() async {
    await stop();
  }

  void _finishPlayback() {
    final shouldNotify = _notifyOnComplete;
    _notifyOnComplete = false;
    _speaking = false;
    if (shouldNotify) {
      onComplete?.call();
    }
  }

  Future<List<_LocalVoice>> _loadVoices({String? locale}) async {
    try {
      final raw = await _tts.getVoices;
      final parsed = _parseVoices(raw);
      final normalizedLocale = _normalizeLocale(locale);
      if (normalizedLocale.isEmpty) {
        return parsed;
      }

      final matching = parsed
          .where(
            (voice) => _normalizeLocale(
              voice.locale,
            ).startsWith(normalizedLocale.split('-').first),
          )
          .toList();
      return matching.isNotEmpty ? matching : parsed;
    } catch (_) {
      return const <_LocalVoice>[];
    }
  }

  List<_LocalVoice> _parseVoices(Object? raw) {
    if (raw is! List) {
      return const <_LocalVoice>[];
    }

    final voices = <_LocalVoice>[];
    final seen = <String>{};
    for (final entry in raw) {
      if (entry is! Map) {
        continue;
      }
      final map = entry.map(
        (key, value) => MapEntry(key.toString(), value?.toString() ?? ''),
      );
      final name = (map['name'] ?? map['identifier'] ?? '').trim();
      if (name.isEmpty || !seen.add(name)) {
        continue;
      }
      final locale = _normalizeLocale(map['locale'] ?? map['language']);
      final gender = (map['gender'] ?? '').trim();
      final label = (map['displayName'] ?? map['name'] ?? '').trim();
      voices.add(
        _LocalVoice(
          name: name,
          locale: locale,
          gender: gender,
          friendlyName: label.isEmpty
              ? _friendlyName(name: name, locale: locale)
              : _friendlyName(name: label, locale: locale),
        ),
      );
    }
    voices.sort(
      (left, right) => left.friendlyName.compareTo(right.friendlyName),
    );
    return voices;
  }

  _LocalVoice? _resolveVoice(
    List<_LocalVoice> voices, {
    String? requestedName,
    String? locale,
  }) {
    if (voices.isEmpty) {
      return null;
    }

    final normalizedRequested = (requestedName ?? '').trim();
    if (normalizedRequested.isNotEmpty &&
        !normalizedRequested.startsWith('system-default-')) {
      for (final voice in voices) {
        if (voice.name == normalizedRequested) {
          return voice;
        }
      }
    }

    final normalizedLocale = _normalizeLocale(locale);
    if (normalizedLocale.isNotEmpty) {
      for (final voice in voices) {
        if (_normalizeLocale(
          voice.locale,
        ).startsWith(normalizedLocale.split('-').first)) {
          return voice;
        }
      }
    }

    return voices.first;
  }

  String _normalizeNarrationText(String text) {
    return text
        .replaceAll(RegExp(r'\r\n?'), '\n')
        .replaceAll(RegExp(r'\n{2,}'), '\n')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r'\s+([,.!?;:])'), r'$1')
        .trim();
  }

  String _resolveLocale({String? requestedLocale, String? voiceLocale}) {
    final normalizedVoiceLocale = _normalizeLocale(voiceLocale);
    if (normalizedVoiceLocale.isNotEmpty) {
      return normalizedVoiceLocale;
    }
    final normalizedRequestedLocale = _normalizeLocale(requestedLocale);
    if (normalizedRequestedLocale.isNotEmpty) {
      return normalizedRequestedLocale;
    }
    return 'en-US';
  }

  double _speechRateForLocale(String locale) {
    return locale.toLowerCase().startsWith('zh') ? 0.42 : 0.46;
  }

  String _normalizeLocale(String? locale) {
    final normalized = (locale ?? '').replaceAll('_', '-').trim();
    if (normalized.isEmpty) {
      return '';
    }
    final parts = normalized.split('-');
    if (parts.length == 1) {
      return parts.first.toLowerCase();
    }
    final language = parts.first.toLowerCase();
    final region = parts.last.toUpperCase();
    return '$language-$region';
  }

  String _friendlyName({required String name, required String locale}) {
    if (locale.isEmpty) {
      return name;
    }
    return '$name ($locale)';
  }

  List<VoiceInfo> _fallbackVoices({String? locale}) {
    final normalizedLocale = _normalizeLocale(locale);
    if (normalizedLocale.startsWith('en')) {
      return const <VoiceInfo>[
        VoiceInfo(
          name: 'system-default-en-US',
          gender: '',
          friendlyName: 'System Default (en-US)',
        ),
      ];
    }
    if (normalizedLocale.startsWith('zh')) {
      return const <VoiceInfo>[
        VoiceInfo(
          name: 'system-default-zh-CN',
          gender: '',
          friendlyName: 'System Default (zh-CN)',
        ),
      ];
    }
    return const <VoiceInfo>[
      VoiceInfo(
        name: 'system-default',
        gender: '',
        friendlyName: 'System Default',
      ),
    ];
  }
}

class _LocalVoice {
  const _LocalVoice({
    required this.name,
    required this.locale,
    required this.gender,
    required this.friendlyName,
  });

  final String name;
  final String locale;
  final String gender;
  final String friendlyName;
}
