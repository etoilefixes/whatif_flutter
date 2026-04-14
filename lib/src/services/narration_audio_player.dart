import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

class NarrationAudioPlayer {
  NarrationAudioPlayer() {
    _player.setReleaseMode(ReleaseMode.stop);
    _player.onPlayerComplete.listen((_) {
      _playing = false;
      unawaited(_playNext());
    });
  }

  final AudioPlayer _player = AudioPlayer();
  final Queue<Uint8List> _queue = Queue<Uint8List>();

  bool _playing = false;
  bool _stopped = false;
  VoidCallback? onComplete;

  bool get isPlaying => _playing || _queue.isNotEmpty;

  void reset() {
    _stopped = false;
  }

  Future<void> enqueueBase64(String value) async {
    if (_stopped || value.isEmpty) {
      return;
    }

    try {
      _queue.add(base64Decode(value));
      if (!_playing) {
        await _playNext();
      }
    } catch (_) {}
  }

  Future<void> stop() async {
    _stopped = true;
    _queue.clear();
    _playing = false;
    try {
      await _player.stop();
    } catch (_) {}
  }

  Future<void> dispose() async {
    await stop();
    await _player.dispose();
  }

  Future<void> _playNext() async {
    if (_stopped) {
      _playing = false;
      return;
    }

    final bytes = _queue.isEmpty ? null : _queue.removeFirst();
    if (bytes == null) {
      final wasPlaying = _playing;
      _playing = false;
      if (wasPlaying && !_stopped) {
        onComplete?.call();
      }
      return;
    }

    _playing = true;
    try {
      await _player.play(BytesSource(bytes, mimeType: 'audio/mpeg'));
    } catch (_) {
      _playing = false;
      unawaited(_playNext());
    }
  }
}
