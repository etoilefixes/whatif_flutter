import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../app_controller.dart';
import '../l10n/app_strings.dart';
import '../models.dart';
import '../services/local_tts_speaker.dart';
import '../services/narration_audio_player.dart';

class GameplayPage extends StatefulWidget {
  const GameplayPage({
    super.key,
    required this.controller,
    required this.strings,
  });

  final AppController controller;
  final AppStrings strings;

  @override
  State<GameplayPage> createState() => _GameplayPageState();
}

class _GameplayPageState extends State<GameplayPage> {
  static const _ttsToMicDelay = Duration(milliseconds: 350);
  static const _autoContinueDelay = Duration(seconds: 3);

  final List<_StoryEntry> _entries = <_StoryEntry>[];
  final TextEditingController _actionController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final NarrationAudioPlayer _audioPlayer = NarrationAudioPlayer();
  final LocalTtsSpeaker _localTtsSpeaker = LocalTtsSpeaker();
  final SpeechToText _speech = SpeechToText();

  Timer? _autoContinueTimer;
  Timer? _listenTimer;
  Timer? _silenceTimer;

  bool _busy = false;
  bool _showInput = false;
  bool _restoredFromSave = false;
  bool _speechReady = false;
  bool _conversationMode = false;
  bool _conversationOwnsVoice = false;
  bool _textHidden = false;
  bool _scrollToBottomScheduled = false;
  String? _error;
  String? _phase;
  String? _eventId;
  String _liveTranscript = '';
  int _turn = 0;
  bool _awaitingNextEvent = false;
  bool _gameEnded = false;
  Uint8List? _backgroundImageBytes;
  _ConversationState _conversationState = _ConversationState.off;

  bool get _ttsEnabled =>
      _conversationMode || widget.controller.voiceConfig.enabled;

  String get _voiceName => widget.controller.voiceConfig.voice;
  bool get _usesLocalTts =>
      widget.controller.api.modeLabel == 'integrated-dart';

  bool get _canContinueNow =>
      !_gameEnded &&
      (_phase == 'setup' || _phase == 'resolution' || _awaitingNextEvent);

  bool get _canTakeTurnNow =>
      !_gameEnded && _phase == 'confrontation' && !_awaitingNextEvent;

  bool get _shouldListenForConversation =>
      _conversationMode && !_busy && _canTakeTurnNow;

  @override
  void initState() {
    super.initState();
    _audioPlayer.onComplete = _handleAudioComplete;
    _localTtsSpeaker.onComplete = _handleAudioComplete;
    unawaited(_initializeSpeech());
    unawaited(_bootstrap());
  }

  Future<void> _initializeSpeech() async {
    try {
      final available = await _speech.initialize(
        onStatus: _handleSpeechStatus,
        onError: _handleSpeechError,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _speechReady = available;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _speechReady = false;
      });
    }
  }

  Future<void> _bootstrap() async {
    final resume = widget.controller.resumeState;
    if (resume != null) {
      final blocks = resume.text
          .split(RegExp(r'\n\s*\n'))
          .map((value) => value.trim())
          .where((value) => value.isNotEmpty)
          .toList();

      final restoredEntries = blocks.isEmpty
          ? <_StoryEntry>[
              _StoryEntry(
                kind: _StoryKind.system,
                text: _localizedText(
                  widget.strings,
                  'gameplay.resumeLoaded',
                  'Resumed from save',
                ),
              ),
            ]
          : blocks
                .map(
                  (block) => _StoryEntry(
                    kind: block.startsWith('> ')
                        ? _StoryKind.player
                        : _StoryKind.narration,
                    text: block.startsWith('> ')
                        ? block.replaceFirst(RegExp(r'^>\s*'), '')
                        : block,
                  ),
                )
                .toList();

      setState(() {
        _entries
          ..clear()
          ..addAll(restoredEntries);
        _restoredFromSave = true;
        _phase = resume.phase;
        _eventId = resume.eventId;
        _turn = resume.turn;
        _awaitingNextEvent = resume.awaitingNextEvent;
        _gameEnded = resume.gameEnded;
        _backgroundImageBytes = null;
      });
      unawaited(_refreshBackgroundImage(resume.eventId, resume.eventHasImage));
      _jumpToBottom(animated: false);
      return;
    }

    await _runStream(
      widget.controller.api.startGameStream(
        lang: widget.controller.locale,
        tts: _ttsEnabled,
        voice: _voiceName,
      ),
    );
  }

  void _handleAudioComplete() {
    if (!_conversationMode || !mounted || _gameEnded) {
      return;
    }

    if (_canTakeTurnNow) {
      setState(() {
        _conversationState = _ConversationState.listening;
      });
      _queueStartListening(_ttsToMicDelay);
      return;
    }

    if (_canContinueNow) {
      setState(() {
        _conversationState = _ConversationState.submitting;
      });
      _queueAutoContinue(_autoContinueDelay);
      return;
    }

    setState(() {
      _conversationState = _ConversationState.off;
    });
  }

  void _handleSpeechStatus(String status) {
    if (!mounted) {
      return;
    }

    if (status == SpeechToText.listeningStatus) {
      setState(() {
        _conversationState = _ConversationState.listening;
      });
      return;
    }

    if ((status == SpeechToText.notListeningStatus ||
            status == SpeechToText.doneStatus) &&
        _shouldListenForConversation &&
        _liveTranscript.trim().isEmpty) {
      _queueStartListening(const Duration(milliseconds: 450));
    }
  }

  void _handleSpeechError(SpeechRecognitionError error) {
    if (!mounted) {
      return;
    }

    if (error.permanent &&
        _conversationMode &&
        _liveTranscript.trim().isEmpty) {
      _queueStartListening(const Duration(milliseconds: 700));
    }
  }

  void _handleSpeechResult(SpeechRecognitionResult result) {
    if (!mounted) {
      return;
    }

    final text = result.recognizedWords.trim();
    setState(() {
      _liveTranscript = text;
    });

    if (_conversationMode && text.isNotEmpty) {
      _scheduleSilenceSubmit();
    }
  }

  Future<void> _startConversationListening() async {
    if (!_shouldListenForConversation || !_speechReady) {
      return;
    }

    _silenceTimer?.cancel();
    _silenceTimer = null;

    try {
      if (_speech.isListening) {
        await _speech.stop();
      }
      await _speech.listen(
        onResult: _handleSpeechResult,
        localeId: widget.controller.locale == 'en' ? 'en-US' : 'zh-CN',
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 5),
        listenOptions: SpeechListenOptions(
          listenMode: ListenMode.dictation,
          partialResults: true,
          cancelOnError: true,
        ),
      );
    } catch (_) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.strings.text('gameplay.micNotSupported')),
        ),
      );
    }
  }

  void _scheduleSilenceSubmit() {
    _silenceTimer?.cancel();
    final delay = _liveTranscript.length > 20
        ? const Duration(seconds: 3)
        : const Duration(milliseconds: 2500);
    _silenceTimer = Timer(delay, () {
      unawaited(_submitRecognizedSpeech());
    });
  }

  Future<void> _submitRecognizedSpeech() async {
    final raw = _liveTranscript.trim();
    if (raw.isEmpty || !_conversationMode || _busy) {
      return;
    }

    _silenceTimer?.cancel();
    _silenceTimer = null;
    await _stopListening();

    var action = raw;
    try {
      action = await widget.controller.api.segmentVoiceText(raw);
    } catch (_) {}

    if (!mounted || action.trim().isEmpty) {
      return;
    }

    setState(() {
      _liveTranscript = '';
      _conversationState = _ConversationState.submitting;
    });

    await _submitAction(action.trim());
  }

  Future<void> _stopListening() async {
    _clearListenTimers();
    if (_liveTranscript.isNotEmpty) {
      setState(() {
        _liveTranscript = '';
      });
    }

    try {
      if (_speech.isListening) {
        await _speech.stop();
      }
    } catch (_) {}
  }

  void _clearAutoContinue() {
    _autoContinueTimer?.cancel();
    _autoContinueTimer = null;
  }

  void _clearListenTimers() {
    _listenTimer?.cancel();
    _listenTimer = null;
    _silenceTimer?.cancel();
    _silenceTimer = null;
  }

  void _queueAutoContinue(Duration delay) {
    _clearAutoContinue();
    _autoContinueTimer = Timer(delay, () {
      unawaited(_continueStory(automatic: true));
    });
  }

  void _queueStartListening(Duration delay) {
    _listenTimer?.cancel();
    _listenTimer = Timer(delay, () {
      unawaited(_startConversationListening());
    });
  }

  Future<void> _toggleVoice() async {
    final next = widget.controller.voiceConfig.copyWith(
      enabled: !widget.controller.voiceConfig.enabled,
    );
    await widget.controller.saveVoiceConfig(next);

    if (!mounted) {
      return;
    }

    if (!next.enabled && !_conversationMode) {
      await _audioPlayer.stop();
      await _localTtsSpeaker.stop();
    }

    setState(() {});
  }

  Future<void> _toggleConversationMode() async {
    if (_conversationMode) {
      await _disableConversationMode();
      return;
    }

    if (!_speechReady) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(widget.strings.text('gameplay.micNotSupported')),
        ),
      );
      return;
    }

    if (!widget.controller.voiceConfig.enabled) {
      _conversationOwnsVoice = true;
      await widget.controller.saveVoiceConfig(
        widget.controller.voiceConfig.copyWith(enabled: true),
      );
    } else {
      _conversationOwnsVoice = false;
    }

    if (!mounted) {
      return;
    }

    setState(() {
      _conversationMode = true;
    });

    if (_busy) {
      setState(() {
        _conversationState = _ConversationState.speaking;
      });
      return;
    }

    if (_canTakeTurnNow) {
      setState(() {
        _conversationState = _ConversationState.listening;
      });
      _queueStartListening(_ttsToMicDelay);
      return;
    }

    if (_canContinueNow) {
      setState(() {
        _conversationState = _ConversationState.submitting;
      });
      _queueAutoContinue(const Duration(milliseconds: 350));
      return;
    }

    setState(() {
      _conversationState = _ConversationState.off;
    });
  }

  Future<void> _disableConversationMode() async {
    _clearAutoContinue();
    _clearListenTimers();
    await _stopListening();
    await _audioPlayer.stop();
    await _localTtsSpeaker.stop();
    await _localTtsSpeaker.stop();

    final restoreVoice = _conversationOwnsVoice;
    _conversationOwnsVoice = false;

    if (mounted) {
      setState(() {
        _conversationMode = false;
        _conversationState = _ConversationState.off;
        _liveTranscript = '';
      });
    }

    if (restoreVoice) {
      await widget.controller.saveVoiceConfig(
        widget.controller.voiceConfig.copyWith(enabled: false),
      );
      if (mounted) {
        setState(() {});
      }
    }
  }

  Future<void> _goBackHome() async {
    final shouldLeave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(widget.strings.text('gameplay.backConfirmTitle')),
        content: Text(widget.strings.text('gameplay.backConfirmBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(widget.strings.text('gameplay.backConfirmStay')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(widget.strings.text('gameplay.backConfirmLeave')),
          ),
        ],
      ),
    );

    if (shouldLeave != true || !mounted) {
      return;
    }

    _clearAutoContinue();
    _clearListenTimers();
    await _stopListening();
    await _audioPlayer.stop();
    await _localTtsSpeaker.stop();
    await _localTtsSpeaker.stop();
    widget.controller.openStart();
  }

  Future<void> _refreshBackgroundImage(String? eventId, bool hasImage) async {
    if (!mounted) {
      return;
    }

    if (eventId == null || eventId.isEmpty || !hasImage) {
      setState(() {
        _backgroundImageBytes = null;
      });
      return;
    }

    final bytes = await widget.controller.api.getEventImage(eventId);
    if (!mounted || _eventId != eventId) {
      return;
    }

    setState(() {
      _backgroundImageBytes = bytes;
    });
  }

  Future<void> _runStream(Stream<SseEvent> stream) async {
    if (_busy) {
      return;
    }

    setState(() {
      _busy = true;
      _error = null;
      _showInput = false;
      _restoredFromSave = false;
      if (_conversationMode) {
        _conversationState = _ConversationState.speaking;
      }
    });

    if (_ttsEnabled) {
      _audioPlayer.reset();
    }

    var streamingIndex = -1;
    final narrationBuffer = StringBuffer();
    var playedLocalNarration = false;

    try {
      await for (final event in stream) {
        if (!mounted) {
          break;
        }

        switch (event.type) {
          case 'chunk':
            setState(() {
              if (streamingIndex == -1) {
                _entries.add(
                  const _StoryEntry(
                    kind: _StoryKind.narration,
                    text: '',
                    streaming: true,
                  ),
                );
                streamingIndex = _entries.length - 1;
              }

              final current = _entries[streamingIndex];
              _entries[streamingIndex] = current.copyWith(
                text: current.text + (event.text ?? ''),
                streaming: true,
              );
              narrationBuffer.write(event.text ?? '');
            });
            _jumpToBottom(animated: false);
            break;
          case 'audio':
            if (_ttsEnabled && !_usesLocalTts) {
              await _audioPlayer.enqueueBase64(event.audio ?? '');
            }
            break;
          case 'state':
            final state = event.state!;
            var addedDivider = false;
            setState(() {
              if (_eventId != null &&
                  state.eventId != null &&
                  state.eventId != _eventId) {
                _entries.add(
                  _StoryEntry(
                    kind: _StoryKind.system,
                    text: _localizedText(
                      widget.strings,
                      'gameplay.newEventDivider',
                      'New Event',
                    ),
                  ),
                );
                addedDivider = true;
              }

              _phase = state.phase;
              _eventId = state.eventId;
              _turn = state.turn;
              _awaitingNextEvent = state.awaitingNextEvent;
              _gameEnded = state.gameEnded;
            });
            unawaited(
              _refreshBackgroundImage(state.eventId, state.eventHasImage),
            );

            if (state.gameEnded && _conversationMode) {
              unawaited(_disableConversationMode());
            }

            if (addedDivider) {
              _jumpToBottom(animated: false);
            }
            break;
          case 'error':
            setState(() {
              _error = event.message;
              _entries.add(
                _StoryEntry(
                  kind: _StoryKind.system,
                  text: event.message ?? 'Unknown error',
                  isError: true,
                ),
              );
            });
            _jumpToBottom(animated: false);
            break;
          case 'done':
            break;
        }
      }

      if (_ttsEnabled &&
          _usesLocalTts &&
          _error == null &&
          narrationBuffer.toString().trim().isNotEmpty) {
        playedLocalNarration = await _localTtsSpeaker.speakNarration(
          narrationBuffer.toString(),
          locale: widget.controller.locale,
          voice: _voiceName,
        );
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          if (streamingIndex != -1) {
            final current = _entries[streamingIndex];
            _entries[streamingIndex] = current.copyWith(streaming: false);
          }
        });
        _jumpToBottom(animated: false);

        if (_conversationMode &&
            _error == null &&
            !_audioPlayer.isPlaying &&
            !_localTtsSpeaker.isSpeaking &&
            !playedLocalNarration) {
          _handleAudioComplete();
        } else if (!_conversationMode) {
          setState(() {
            _conversationState = _ConversationState.off;
          });
        }
      }
    }
  }

  Future<void> _continueStory({bool automatic = false}) async {
    if (_busy) {
      return;
    }

    _clearAutoContinue();
    _clearListenTimers();
    await _stopListening();
    await _audioPlayer.stop();

    if (_conversationMode && automatic) {
      setState(() {
        _conversationState = _ConversationState.submitting;
      });
    }

    await _runStream(
      widget.controller.api.continueGameStream(
        lang: widget.controller.locale,
        tts: _ttsEnabled,
        voice: _voiceName,
      ),
    );
  }

  Future<void> _submitAction([String? rawAction]) async {
    final action = (rawAction ?? _actionController.text).trim();
    if (action.isEmpty || _busy) {
      return;
    }

    _clearAutoContinue();
    _clearListenTimers();
    await _stopListening();
    await _audioPlayer.stop();

    setState(() {
      _entries.add(_StoryEntry(kind: _StoryKind.player, text: action));
      _showInput = false;
      if (_conversationMode) {
        _conversationState = _ConversationState.submitting;
      }
    });
    _actionController.clear();
    _jumpToBottom(animated: false);

    await _runStream(
      widget.controller.api.submitActionStream(
        action,
        lang: widget.controller.locale,
        tts: _ttsEnabled,
        voice: _voiceName,
      ),
    );
  }

  Future<void> _openSaveDialog() async {
    final message = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _SaveGameDialog(
        controller: widget.controller,
        strings: widget.strings,
      ),
    );

    if (!mounted || message == null || message.isEmpty) {
      return;
    }

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  void _jumpToBottom({bool animated = true}) {
    if (_scrollToBottomScheduled) {
      return;
    }
    _scrollToBottomScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottomScheduled = false;
      if (!_scrollController.hasClients) {
        return;
      }

      final position = _scrollController.position;
      final target = position.maxScrollExtent;
      final distance = (target - position.pixels).abs();
      if (!animated || distance > 320) {
        _scrollController.jumpTo(target);
        return;
      }

      _scrollController.animateTo(
        target,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    _clearAutoContinue();
    _clearListenTimers();
    unawaited(_audioPlayer.dispose());
    unawaited(_localTtsSpeaker.dispose());
    _actionController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showContinueButton =
        _canContinueNow &&
        _conversationState != _ConversationState.speaking &&
        _conversationState != _ConversationState.submitting;
    final showTakeTurnButton = _canTakeTurnNow && !_conversationMode;

    return LayoutBuilder(
      builder: (context, constraints) {
        final wideLayout = constraints.maxWidth >= 1220;

        return Stack(
          children: [
            if (_backgroundImageBytes != null)
              Positioned.fill(
                child: RepaintBoundary(
                  child: Image.memory(
                    _backgroundImageBytes!,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    filterQuality: FilterQuality.low,
                    errorBuilder: (context, error, stackTrace) =>
                        const SizedBox.shrink(),
                  ),
                ),
              ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: _textHidden ? 0.1 : 0.42),
                      Colors.black.withValues(alpha: _textHidden ? 0.18 : 0.66),
                      Colors.black.withValues(alpha: _textHidden ? 0.28 : 0.9),
                    ],
                  ),
                ),
              ),
            ),
            Column(
              children: [
                _buildTopBar(context),
                Expanded(
                  child: wideLayout
                      ? Padding(
                          padding: const EdgeInsets.fromLTRB(24, 12, 24, 20),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(
                                flex: 7,
                                child: _buildStoryPane(
                                  context,
                                  wideLayout: true,
                                ),
                              ),
                              const SizedBox(width: 16),
                              SizedBox(
                                width: 360,
                                child: _buildControlsPane(
                                  context,
                                  showContinueButton: showContinueButton,
                                  showTakeTurnButton: showTakeTurnButton,
                                  wideLayout: true,
                                ),
                              ),
                            ],
                          ),
                        )
                      : Column(
                          children: [
                            Expanded(
                              child: _buildStoryPane(
                                context,
                                wideLayout: false,
                              ),
                            ),
                            if (_showInput && !_conversationMode)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  24,
                                  0,
                                  24,
                                  12,
                                ),
                                child: _buildActionComposer(
                                  context,
                                  vertical: constraints.maxWidth < 640,
                                ),
                              ),
                            if (!_showInput)
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  24,
                                  0,
                                  24,
                                  20,
                                ),
                                child: _buildControlsPane(
                                  context,
                                  showContinueButton: showContinueButton,
                                  showTakeTurnButton: showTakeTurnButton,
                                  wideLayout: false,
                                ),
                              ),
                          ],
                        ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildTopBar(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IconButton.filledTonal(
            onPressed: _goBackHome,
            icon: const Icon(Icons.arrow_back_rounded),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.strings.text('gameplay.title'),
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                Text(
                  widget.controller.currentPkgName ?? '-',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: const Color(0xFFADC0D8),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Align(
              alignment: Alignment.topRight,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: [
                  if (_backgroundImageBytes != null)
                    IconButton.filledTonal(
                      onPressed: () {
                        setState(() {
                          _textHidden = !_textHidden;
                        });
                      },
                      icon: Icon(
                        _textHidden
                            ? Icons.visibility_rounded
                            : Icons.visibility_off_rounded,
                      ),
                    ),
                  if (_phase != null)
                    _MetaChip(label: _phaseLabel(widget.strings, _phase)),
                  _MetaChip(
                    label: widget.strings.text('saves.turn', {
                      'turn': _turn.toString(),
                    }),
                  ),
                  if (_gameEnded)
                    Chip(label: Text(widget.strings.text('gameplay.gameEnded')))
                  else if (_busy)
                    const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStoryPane(BuildContext context, {required bool wideLayout}) {
    final content = Column(
      children: [
        if (_restoredFromSave)
          Padding(
            padding: wideLayout
                ? const EdgeInsets.fromLTRB(18, 18, 18, 0)
                : const EdgeInsets.symmetric(horizontal: 24),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Chip(
                avatar: const Icon(Icons.history_rounded, size: 18),
                label: Text(widget.strings.text('gameplay.resumeLoaded')),
              ),
            ),
          ),
        if (_error != null)
          Padding(
            padding: wideLayout
                ? const EdgeInsets.fromLTRB(18, 12, 18, 0)
                : const EdgeInsets.fromLTRB(24, 12, 24, 0),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: const Color(0x33C96B54),
              ),
              child: Text(_error!),
            ),
          ),
        Expanded(
          child: _buildStoryList(
            context,
            padding: wideLayout
                ? const EdgeInsets.fromLTRB(18, 18, 18, 18)
                : const EdgeInsets.fromLTRB(24, 18, 24, 18),
          ),
        ),
      ],
    );

    if (!wideLayout) {
      return content;
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0x66111A2B),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0x223A4A68)),
      ),
      child: content,
    );
  }

  Widget _buildStoryList(
    BuildContext context, {
    required EdgeInsetsGeometry padding,
  }) {
    if (_entries.isEmpty) {
      return Center(
        child: Text(
          widget.strings.text('gameplay.empty'),
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(color: const Color(0xFFA7B5CC)),
        ),
      );
    }

    return Scrollbar(
      controller: _scrollController,
      thumbVisibility: MediaQuery.sizeOf(context).width >= 1220,
      child: RepaintBoundary(
        child: ListView.separated(
          controller: _scrollController,
          cacheExtent: 1400,
          padding: padding,
          itemCount: _entries.length,
          separatorBuilder: (context, index) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final entry = _entries[index];
            return _StoryBubble(entry: entry, textHidden: _textHidden);
          },
        ),
      ),
    );
  }

  Widget _buildControlsPane(
    BuildContext context, {
    required bool showContinueButton,
    required bool showTakeTurnButton,
    required bool wideLayout,
  }) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (wideLayout) ...[
          Text(
            _localizedText(
              widget.strings,
              'gameplay.controlsTitle',
              'Adventure Controls',
            ),
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 6),
          Text(
            _localizedText(
              widget.strings,
              'gameplay.controlsHint',
              'Keep actions, save slots, voice and conversation tools on the side while the story stays readable.',
            ),
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: const Color(0xFFA7B5CC)),
          ),
          const SizedBox(height: 16),
        ],
        if (_conversationMode &&
            _conversationState != _ConversationState.off) ...[
          _ConversationBanner(
            state: _conversationState,
            transcript: _liveTranscript,
            strings: widget.strings,
          ),
          const SizedBox(height: 12),
        ],
        if (_showInput && !_conversationMode && wideLayout) ...[
          _buildActionComposer(context, vertical: true),
          const SizedBox(height: 14),
        ],
        _buildActionButtons(
          context,
          showContinueButton: showContinueButton,
          showTakeTurnButton: showTakeTurnButton,
          wideLayout: wideLayout,
        ),
      ],
    );

    if (!wideLayout) {
      return content;
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xCC101A2B),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0x223A4A68)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22000000),
            blurRadius: 30,
            offset: Offset(0, 18),
          ),
        ],
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(18),
        child: content,
      ),
    );
  }

  Widget _buildActionButtons(
    BuildContext context, {
    required bool showContinueButton,
    required bool showTakeTurnButton,
    required bool wideLayout,
  }) {
    Widget wrapAction(Widget child) {
      if (!wideLayout) {
        return child;
      }
      return SizedBox(width: double.infinity, child: child);
    }

    final actions = <Widget>[
      wrapAction(
        FilledButton.tonalIcon(
          onPressed: _busy ? null : _openSaveDialog,
          icon: const Icon(Icons.save_rounded),
          label: Text(_localizedText(widget.strings, 'gameplay.save', 'Save')),
        ),
      ),
      wrapAction(
        FilledButton.tonalIcon(
          onPressed: _busy ? null : () => unawaited(_toggleVoice()),
          icon: Icon(
            widget.controller.voiceConfig.enabled
                ? Icons.volume_up_rounded
                : Icons.volume_off_rounded,
          ),
          label: Text(
            widget.controller.voiceConfig.enabled
                ? widget.strings.text('gameplay.voiceOn')
                : widget.strings.text('gameplay.voiceOff'),
          ),
        ),
      ),
      if (_speechReady)
        wrapAction(
          FilledButton.tonalIcon(
            onPressed: _busy && !_conversationMode
                ? null
                : () => unawaited(_toggleConversationMode()),
            icon: Icon(
              _conversationMode
                  ? Icons.chat_bubble_rounded
                  : Icons.chat_bubble_outline_rounded,
            ),
            label: Text(
              _conversationMode
                  ? widget.strings.text('gameplay.conversationOn')
                  : widget.strings.text('gameplay.conversationOff'),
            ),
          ),
        ),
      if (showTakeTurnButton)
        wrapAction(
          FilledButton.icon(
            onPressed: _busy
                ? null
                : () {
                    setState(() {
                      _showInput = true;
                    });
                  },
            icon: const Icon(Icons.edit_rounded),
            label: Text(widget.strings.text('gameplay.takeTurn')),
          ),
        ),
      if (showContinueButton)
        wrapAction(
          FilledButton.icon(
            onPressed: _busy ? null : () => unawaited(_continueStory()),
            icon: const Icon(Icons.fast_forward_rounded),
            label: Text(widget.strings.text('gameplay.continue')),
          ),
        ),
      if (!showContinueButton && !showTakeTurnButton && !_gameEnded)
        Align(
          alignment: Alignment.centerLeft,
          child: Chip(label: Text(widget.strings.text('gameplay.awaiting'))),
        ),
    ];

    if (!wideLayout) {
      return Wrap(spacing: 12, runSpacing: 12, children: actions);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var index = 0; index < actions.length; index += 1) ...[
          if (index > 0) const SizedBox(height: 12),
          actions[index],
        ],
      ],
    );
  }

  Widget _buildActionComposer(BuildContext context, {required bool vertical}) {
    if (!vertical) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: _actionController,
              autofocus: true,
              minLines: 1,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: widget.strings.text('gameplay.inputHint'),
              ),
              onSubmitted: (_) => unawaited(_submitAction()),
            ),
          ),
          const SizedBox(width: 12),
          FilledButton(
            onPressed: _busy ? null : () => unawaited(_submitAction()),
            child: Text(widget.strings.text('gameplay.submit')),
          ),
          const SizedBox(width: 8),
          FilledButton.tonal(
            onPressed: _busy
                ? null
                : () {
                    setState(() {
                      _showInput = false;
                    });
                  },
            child: Text(widget.strings.text('gameplay.cancel')),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _actionController,
          autofocus: true,
          minLines: 3,
          maxLines: 5,
          decoration: InputDecoration(
            hintText: widget.strings.text('gameplay.inputHint'),
          ),
          onSubmitted: (_) => unawaited(_submitAction()),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton(
                onPressed: _busy ? null : () => unawaited(_submitAction()),
                child: Text(widget.strings.text('gameplay.submit')),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.tonal(
                onPressed: _busy
                    ? null
                    : () {
                        setState(() {
                          _showInput = false;
                        });
                      },
                child: Text(widget.strings.text('gameplay.cancel')),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StoryBubble extends StatelessWidget {
  const _StoryBubble({required this.entry, required this.textHidden});

  final _StoryEntry entry;
  final bool textHidden;

  @override
  Widget build(BuildContext context) {
    if (entry.kind == _StoryKind.system) {
      return Align(
        alignment: Alignment.center,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 220),
          opacity: textHidden ? 0.35 : 1,
          child: Container(
            constraints: const BoxConstraints(maxWidth: 560),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              color: entry.isError
                  ? const Color(0x33C96B54)
                  : const Color(0x6611182A),
              border: Border.all(
                color: entry.isError
                    ? const Color(0x44C96B54)
                    : const Color(0x223A4A68),
              ),
            ),
            child: Text(
              entry.text,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: entry.isError
                    ? const Color(0xFFF2D0C8)
                    : const Color(0xFFA7B5CC),
              ),
            ),
          ),
        ),
      );
    }

    final isPlayer = entry.kind == _StoryKind.player;

    return Align(
      alignment: isPlayer ? Alignment.centerRight : Alignment.centerLeft,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 220),
        opacity: textHidden ? 0.14 : 1,
        child: Container(
          constraints: const BoxConstraints(maxWidth: 760),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            color: isPlayer ? const Color(0xFF1D3A59) : const Color(0xCC111A2B),
            border: Border.all(
              color: isPlayer
                  ? const Color(0x3352A3FF)
                  : const Color(0x223A4A68),
            ),
          ),
          child: Text(
            entry.streaming ? '${entry.text}|' : entry.text,
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(height: 1.65),
          ),
        ),
      ),
    );
  }
}

class _ConversationBanner extends StatelessWidget {
  const _ConversationBanner({
    required this.state,
    required this.transcript,
    required this.strings,
  });

  final _ConversationState state;
  final String transcript;
  final AppStrings strings;

  @override
  Widget build(BuildContext context) {
    late final IconData icon;
    late final String text;

    switch (state) {
      case _ConversationState.listening:
        icon = Icons.mic_rounded;
        text = transcript.isEmpty
            ? strings.text('gameplay.listening')
            : transcript;
        break;
      case _ConversationState.speaking:
        icon = Icons.graphic_eq_rounded;
        text = strings.text('gameplay.speaking');
        break;
      case _ConversationState.submitting:
        icon = Icons.more_horiz_rounded;
        text = strings.text('gameplay.autoContinuing');
        break;
      case _ConversationState.off:
        icon = Icons.chat_bubble_outline_rounded;
        text = '';
        break;
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0xCC111A2B),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0x335B7AA6)),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFFD6922F)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: const Color(0xFFE4EDF9)),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0x77131D31),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0x223A4A68)),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: const Color(0xFFB6C7DE),
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

String _localizedText(
  AppStrings strings,
  String key,
  String fallback, [
  Map<String, String> params = const {},
]) {
  final value = strings.text(key, params);
  return value == key ? fallback : value;
}

String _phaseLabel(AppStrings strings, String? phase) {
  switch (phase) {
    case 'setup':
      return _localizedText(strings, 'gameplay.phase.setup', 'Setup');
    case 'confrontation':
      return _localizedText(
        strings,
        'gameplay.phase.confrontation',
        'Confrontation',
      );
    case 'resolution':
      return _localizedText(strings, 'gameplay.phase.resolution', 'Resolution');
    default:
      return _localizedText(strings, 'gameplay.phase.unknown', 'Unknown');
  }
}

String _formatSaveTime(BuildContext context, String raw) {
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) {
    return raw;
  }

  final localizations = MaterialLocalizations.of(context);
  final local = parsed.toLocal();
  final day = localizations.formatMediumDate(local);
  final time = localizations.formatTimeOfDay(
    TimeOfDay.fromDateTime(local),
    alwaysUse24HourFormat: true,
  );
  return '$day $time';
}

int _defaultManualSlot(List<SaveInfo> saves) {
  const manualSlots = <int>[1, 2, 3, 4, 5, 6];
  final occupied = saves.map((save) => save.slot).toSet();
  for (final slot in manualSlots) {
    if (!occupied.contains(slot)) {
      return slot;
    }
  }
  return manualSlots.first;
}

class _SaveGameDialog extends StatefulWidget {
  const _SaveGameDialog({required this.controller, required this.strings});

  final AppController controller;
  final AppStrings strings;

  @override
  State<_SaveGameDialog> createState() => _SaveGameDialogState();
}

class _SaveGameDialogState extends State<_SaveGameDialog> {
  static const _manualSlots = <int>[1, 2, 3, 4, 5, 6];

  final TextEditingController _descriptionController = TextEditingController();

  List<SaveInfo> _saves = const <SaveInfo>[];
  bool _loading = true;
  bool _saving = false;
  String? _error;
  int _selectedSlot = _manualSlots.first;

  @override
  void initState() {
    super.initState();
    _load();
  }

  SaveInfo? _saveForSlot(int slot) {
    for (final save in _saves) {
      if (save.slot == slot) {
        return save;
      }
    }
    return null;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final saves = await widget.controller.fetchSaves();
      if (!mounted) {
        return;
      }

      final selectedSlot = _defaultManualSlot(saves);
      final existingSave = saves.where((save) => save.slot == selectedSlot);

      _descriptionController.text = existingSave.isEmpty
          ? ''
          : existingSave.first.description;

      setState(() {
        _saves = saves;
        _selectedSlot = selectedSlot;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  void _selectSlot(int slot) {
    final save = _saveForSlot(slot);
    setState(() {
      _selectedSlot = slot;
      _error = null;
    });
    _descriptionController.text = save?.description ?? '';
  }

  Future<void> _save() async {
    if (_loading || _saving) {
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final message = await widget.controller.saveGame(
        _selectedSlot,
        _descriptionController.text.trim(),
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(message);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      backgroundColor: const Color(0xFF0F1626),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(28),
        side: const BorderSide(color: Color(0x22D6922F)),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760, maxHeight: 720),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _localizedText(
                        widget.strings,
                        'saves.saveTitle',
                        'Choose a save slot',
                      ),
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  IconButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                _localizedText(
                  widget.strings,
                  'saves.saveHint',
                  'Manual saves do not overwrite the autosave slot.',
                ),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: const Color(0xFFA7B5CC),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0x33C96B54),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(_error!),
                ),
              ],
              const SizedBox(height: 16),
              Expanded(child: _buildBody(context)),
              const SizedBox(height: 16),
              TextField(
                controller: _descriptionController,
                minLines: 2,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: _localizedText(
                    widget.strings,
                    'saves.saveDescription',
                    'Save title',
                  ),
                  hintText: _localizedText(
                    widget.strings,
                    'saves.saveDescriptionHint',
                    'Leave blank to use an automatic summary.',
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: Text(
                      _localizedText(widget.strings, 'common.cancel', 'Cancel'),
                    ),
                  ),
                  const Spacer(),
                  FilledButton.tonal(
                    onPressed: _loading || _saving ? null : _load,
                    child: Text(widget.strings.text('common.retry')),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: _loading || _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_rounded),
                    label: Text(
                      _saving
                          ? _localizedText(
                              widget.strings,
                              'saves.processing',
                              'Processing...',
                            )
                          : _localizedText(
                              widget.strings,
                              'saves.saveNow',
                              'Save now',
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            Text(widget.strings.text('saves.loading')),
          ],
        ),
      );
    }

    return ListView.separated(
      itemCount: _manualSlots.length,
      separatorBuilder: (context, index) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final slot = _manualSlots[index];
        final save = _saveForSlot(slot);
        final selected = _selectedSlot == slot;

        return InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: _saving ? null : () => _selectSlot(slot),
          child: Ink(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected
                    ? const Color(0x88D6922F)
                    : const Color(0x223A4A68),
              ),
              color: selected
                  ? const Color(0xFF16233A)
                  : const Color(0xFF111B2E),
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    color: const Color(0xFF1C2A43),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    slot.toString(),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        save?.description.isNotEmpty == true
                            ? save!.description
                            : _localizedText(
                                widget.strings,
                                'saves.emptySlot',
                                'Empty slot',
                              ),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _localizedText(
                          widget.strings,
                          'saves.slotLabel',
                          'Slot $slot',
                          {'slot': slot.toString()},
                        ),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: const Color(0xFFA7B5CC),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        save == null
                            ? _localizedText(
                                widget.strings,
                                'saves.saveDescriptionHint',
                                'Leave blank to use an automatic summary.',
                              )
                            : '${_phaseLabel(widget.strings, save.currentPhase)}  |  ${widget.strings.text('saves.turn', {'turn': save.totalTurns.toString()})}  |  ${_formatSaveTime(context, save.saveTime)}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: const Color(0xFF94A2BD),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                if (selected)
                  const Icon(
                    Icons.check_circle_rounded,
                    color: Color(0xFFD6922F),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _StoryEntry {
  const _StoryEntry({
    required this.kind,
    required this.text,
    this.streaming = false,
    this.isError = false,
  });

  final _StoryKind kind;
  final String text;
  final bool streaming;
  final bool isError;

  _StoryEntry copyWith({
    _StoryKind? kind,
    String? text,
    bool? streaming,
    bool? isError,
  }) {
    return _StoryEntry(
      kind: kind ?? this.kind,
      text: text ?? this.text,
      streaming: streaming ?? this.streaming,
      isError: isError ?? this.isError,
    );
  }
}

enum _StoryKind { narration, player, system }

enum _ConversationState { off, listening, speaking, submitting }
