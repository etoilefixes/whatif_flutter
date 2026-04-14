import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../models.dart';
import 'backend_api_contract.dart';
import 'local_bridge_planner.dart';
import 'local_context_enrichment.dart';
import 'local_delta_state.dart';
import 'local_deviation_agent.dart';
import 'local_memory_compression.dart';
import 'local_narrative_generator.dart';
import 'local_scene_adaptation.dart';
import 'local_worldpkg.dart';

class LocalGameEngine {
  LocalGameEngine({
    required Directory savesDir,
    this.narrativeGenerator,
    this.deviationAgent,
    this.memoryCompression,
    this.bridgePlanner,
    this.sceneAdaptationPlanner,
    LocalContextEnrichment? contextEnrichment,
  }) : _savesDir = savesDir,
       _contextEnrichment = contextEnrichment ?? const LocalContextEnrichment();

  final Directory _savesDir;
  final LocalNarrativeGenerator? narrativeGenerator;
  final LocalDeviationAgent? deviationAgent;
  final LocalMemoryCompressionManager? memoryCompression;
  final LocalBridgePlanner? bridgePlanner;
  final LocalSceneAdaptationPlanner? sceneAdaptationPlanner;
  final LocalContextEnrichment _contextEnrichment;

  LocalWorldPkg? _world;
  final List<_TranscriptEntry> _transcript = <_TranscriptEntry>[];
  final List<LocalDeviationHistoryEntry> _currentDeviationHistory =
      <LocalDeviationHistoryEntry>[];

  LocalDeltaStateManager _deltaState = LocalDeltaStateManager();
  String? _currentEventId;
  String? _phase;
  int _turn = 0;
  String? _playerName;
  bool _awaitingNextEvent = false;
  bool _gameEnded = false;
  int _currentEventTranscriptStart = 0;
  _PrefetchSlot? _prefetchSlot;

  String? get currentWorldTitle => _world?.title;
  String? get currentWorldFilename => _world?.filename;

  Future<void> waitForPrefetch() async {
    final slot = _prefetchSlot;
    if (slot == null) {
      return;
    }
    slot.result ??= await slot.future;
  }

  void setWorld(LocalWorldPkg world) {
    _invalidatePrefetch();
    _world = world;
    _resetState(clearWorldSelection: false);
  }

  GameState getGameState() {
    final event = _world?.getEvent(_currentEventId);
    return GameState(
      phase: _phase,
      event: event == null
          ? null
          : EventInfo(
              id: event.id,
              decisionText: event.decisionText,
              goal: event.goal,
              importance: event.importance,
              type: event.type,
              hasImage: (event.image ?? '').isNotEmpty,
            ),
      turn: _turn,
      playerName: _playerName,
      awaitingNextEvent: _awaitingNextEvent,
      gameEnded: _gameEnded,
    );
  }

  Future<List<SaveInfo>> listSaves() async {
    await _savesDir.create(recursive: true);
    final saves = <SaveInfo>[];

    await for (final entity in _savesDir.list()) {
      if (entity is! Directory ||
          !p.basename(entity.path).startsWith('save_')) {
        continue;
      }

      final metadataFile = File(p.join(entity.path, 'metadata.json'));
      if (!metadataFile.existsSync()) {
        continue;
      }

      final decoded = jsonDecode(metadataFile.readAsStringSync());
      final metadata = _asMap(decoded);
      if (metadata == null) {
        continue;
      }

      saves.add(SaveInfo.fromJson(metadata));
    }

    saves.sort((left, right) => right.saveTime.compareTo(left.saveTime));
    return saves;
  }

  Future<String> saveGame(int slot, String description) async {
    final world = _requireWorld();
    await _savesDir.create(recursive: true);

    final saveDir = Directory(
      p.join(_savesDir.path, 'save_${slot.toString().padLeft(3, '0')}'),
    );
    await saveDir.create(recursive: true);

    final event = world.getEvent(_currentEventId);
    final resolvedDescription = description.trim().isNotEmpty
        ? description.trim()
        : _defaultSaveDescription(event);
    final now = DateTime.now().toIso8601String();

    final state = <String, dynamic>{
      'currentEventId': _currentEventId,
      'phase': _phase,
      'turn': _turn,
      'playerName': _playerName,
      'awaitingNextEvent': _awaitingNextEvent,
      'gameEnded': _gameEnded,
      'worldpkgFilename': world.filename,
      'worldpkgTitle': world.title,
      'transcript': _transcript.map((entry) => entry.toJson()).toList(),
      'deltaState': _deltaState.toJson(),
      'memoryCompression': memoryCompression?.toJson(),
      'currentEventTranscriptStart': _currentEventTranscriptStart,
      'currentDeviationHistory': _currentDeviationHistory
          .map((entry) => entry.toJson())
          .toList(),
    };

    final metadata = <String, dynamic>{
      'slot': slot,
      'saveTime': now,
      'playerName': _playerName ?? '',
      'currentPhase': _phase,
      'currentEventId': _currentEventId,
      'totalTurns': _turn,
      'description': resolvedDescription,
      'worldpkgTitle': world.title,
    };

    File(
      p.join(saveDir.path, 'state.json'),
    ).writeAsStringSync(jsonEncode(state));
    File(
      p.join(saveDir.path, 'metadata.json'),
    ).writeAsStringSync(jsonEncode(metadata));
    return 'Saved to slot $slot';
  }

  Future<LoadGameResponse> loadGame(int slot) async {
    _invalidatePrefetch();
    final world = _requireWorld();
    final saveDir = Directory(
      p.join(_savesDir.path, 'save_${slot.toString().padLeft(3, '0')}'),
    );
    final stateFile = File(p.join(saveDir.path, 'state.json'));
    if (!stateFile.existsSync()) {
      throw ApiException('Save slot $slot does not exist.');
    }

    final decoded = jsonDecode(stateFile.readAsStringSync());
    final state = _asMap(decoded);
    if (state == null) {
      throw const ApiException('Save data is corrupted.');
    }

    final saveWorldFilename = state['worldpkgFilename'] as String?;
    if (saveWorldFilename != null &&
        saveWorldFilename.isNotEmpty &&
        saveWorldFilename != world.filename) {
      throw const ApiException(
        'The selected world package does not match this save.',
      );
    }

    _currentEventId = state['currentEventId'] as String?;
    _phase = state['phase'] as String?;
    _turn = (state['turn'] as num?)?.toInt() ?? 0;
    _playerName = state['playerName'] as String?;
    _awaitingNextEvent = state['awaitingNextEvent'] as bool? ?? false;
    _gameEnded = state['gameEnded'] as bool? ?? false;
    _currentEventTranscriptStart =
        (state['currentEventTranscriptStart'] as num?)?.toInt() ?? 0;

    _transcript
      ..clear()
      ..addAll(_asMapList(state['transcript']).map(_TranscriptEntry.fromJson));

    _currentDeviationHistory
      ..clear()
      ..addAll(
        _asMapList(
          state['currentDeviationHistory'],
        ).map(LocalDeviationHistoryEntry.fromJson),
      );

    _deltaState = LocalDeltaStateManager.fromJson(_asMap(state['deltaState']));
    memoryCompression?.restoreFromJson(_asMap(state['memoryCompression']));

    return LoadGameResponse(
      text: _resumeText(),
      phase: _phase,
      eventId: _currentEventId,
      turn: _turn,
    );
  }

  Stream<SseEvent> startGame({String lang = 'zh-CN'}) async* {
    final world = _requireWorld();
    final firstEvent = world.getFirstEvent();
    if (firstEvent == null) {
      throw const ApiException('The selected world package has no events.');
    }

    _resetState(clearWorldSelection: false);
    _playerName = world.getProtagonist()?.name ?? '';
    _currentEventId = firstEvent.id;
    _phase = 'setup';
    _currentEventTranscriptStart = 0;

    final narrative = await _setupNarrative(firstEvent, lang);
    _appendNarration(narrative);
    if (firstEvent.type == 'narrative') {
      _awaitingNextEvent = true;
    }
    _maybeSchedulePrefetch(lang);

    yield* _emitNarrative(narrative);
  }

  Stream<SseEvent> continueGame({String lang = 'zh-CN'}) async* {
    _requireWorld();
    final prefetched = await _consumePrefetch(lang);
    if (prefetched != null) {
      _applyPrefetchResult(prefetched);
      _appendNarration(prefetched.narrative);
      _maybeSchedulePrefetch(lang);
      yield* _emitNarrative(prefetched.narrative);
      return;
    }

    if (_gameEnded) {
      final ending = _endingNarrative(lang);
      yield* _emitNarrative(ending);
      return;
    }

    if (_awaitingNextEvent || _phase == 'resolution') {
      yield* _advanceToNextEvent(lang);
      return;
    }

    if (_phase == 'setup') {
      final event = _requireCurrentEvent();
      if (event.type != 'interactive') {
        _awaitingNextEvent = true;
        yield* _advanceToNextEvent(lang);
        return;
      }

      _phase = 'confrontation';
      final narrative = await _confrontationPrompt(event, lang);
      _appendNarration(narrative);
      _maybeSchedulePrefetch(lang);
      yield* _emitNarrative(narrative);
      return;
    }

    final narrative = lang.startsWith('en')
        ? 'The story is waiting for your action.'
        : '故事正在等待你的行动。';
    _appendSystem(narrative);
    yield* _emitNarrative(narrative);
  }

  Stream<SseEvent> submitAction(String action, {String lang = 'zh-CN'}) async* {
    _requireWorld();
    if (action.trim().isEmpty) {
      throw const ApiException('Action cannot be empty.');
    }
    if (_phase != 'confrontation') {
      throw const ApiException(
        'You can only act during the confrontation phase.',
      );
    }

    final event = _requireCurrentEvent();
    final trimmedAction = action.trim();
    _transcript.add(_TranscriptEntry.player(trimmedAction));

    _turn += 1;
    _phase = 'resolution';
    _awaitingNextEvent = true;

    final analysis = await _analyzeAction(
      lang: lang,
      event: event,
      action: trimmedAction,
    );

    if (analysis?.hasWorldChange == true) {
      final deltaFact = analysis!.deltaFact?.trim();
      if (deltaFact != null && deltaFact.isNotEmpty) {
        _deltaState.createDelta(
          fact: deltaFact,
          sourceEventId: event.id,
          createdTurn: _turn,
          intensity: analysis.deltaIntensity ?? 3,
        );
      }
    }

    final narrative = await _resolutionNarrative(
      event,
      trimmedAction,
      lang,
      analysis: analysis,
    );
    _appendNarration(narrative);

    _currentDeviationHistory.add(
      LocalDeviationHistoryEntry(
        playerAction: trimmedAction,
        responseSummary: _summarizeNarrative(narrative),
        analysis: analysis,
      ),
    );
    _maybeSchedulePrefetch(lang);

    yield* _emitNarrative(narrative);
  }

  Uint8List? getEventImage(String eventId) {
    return _world?.getEventImageBytes(eventId);
  }

  void _resetState({required bool clearWorldSelection}) {
    _invalidatePrefetch();
    if (clearWorldSelection) {
      _world = null;
    }
    _transcript.clear();
    _currentDeviationHistory.clear();
    _deltaState = LocalDeltaStateManager();
    memoryCompression?.reset();
    _currentEventId = null;
    _phase = null;
    _turn = 0;
    _playerName = null;
    _awaitingNextEvent = false;
    _gameEnded = false;
    _currentEventTranscriptStart = 0;
  }

  LocalWorldPkg _requireWorld() {
    final world = _world;
    if (world == null) {
      throw const ApiException('No world package is selected.');
    }
    return world;
  }

  LocalWorldEvent _requireCurrentEvent() {
    final event = _world?.getEvent(_currentEventId);
    if (event == null) {
      throw const ApiException('The current event is unavailable.');
    }
    return event;
  }

  Future<LocalDeviationAnalysis?> _analyzeAction({
    required String lang,
    required LocalWorldEvent event,
    required String action,
  }) async {
    final agent = deviationAgent;
    if (agent == null) {
      return null;
    }

    try {
      return await agent.analyze(
        LocalDeviationRequest(
          locale: lang,
          eventId: event.id,
          eventGoal: event.goal,
          importance: event.importance,
          playerAction: action,
          currentHistory: List<LocalDeviationHistoryEntry>.unmodifiable(
            _currentDeviationHistory,
          ),
          deltaState: _deltaState,
        ),
      );
    } catch (_) {
      return null;
    }
  }

  void _maybeSchedulePrefetch(String lang) {
    _invalidatePrefetch();
    if (_gameEnded) {
      return;
    }

    final action = _nextPrefetchAction();
    if (action == null) {
      return;
    }

    final key = _buildPrefetchKey(lang);
    final slot = _PrefetchSlot(
      key: key,
      future: _runPrefetch(action, lang: lang),
    );
    _prefetchSlot = slot;
  }

  _PrefetchAction? _nextPrefetchAction() {
    if (_awaitingNextEvent || _phase == 'resolution') {
      return _PrefetchAction.advanceToNextEvent;
    }

    if (_phase != 'setup') {
      return null;
    }

    final event = _world?.getEvent(_currentEventId);
    if (event == null || event.type != 'interactive') {
      return null;
    }
    return _PrefetchAction.advanceFromSetup;
  }

  Future<_PrefetchResult?> _consumePrefetch(String lang) async {
    final slot = _prefetchSlot;
    if (slot == null) {
      return null;
    }

    if (slot.key != _buildPrefetchKey(lang)) {
      _invalidatePrefetch();
      return null;
    }

    _prefetchSlot = null;
    slot.result ??= await slot.future;
    if (slot.result == null) {
      return null;
    }
    if (slot.key != _buildPrefetchKey(lang)) {
      return null;
    }
    return slot.result;
  }

  Future<_PrefetchResult?> _runPrefetch(
    _PrefetchAction action, {
    required String lang,
  }) async {
    try {
      return switch (action) {
        _PrefetchAction.advanceToNextEvent => await _prefetchNextEvent(lang),
        _PrefetchAction.advanceFromSetup => await _prefetchConfrontation(lang),
      };
    } catch (_) {
      return null;
    }
  }

  Future<_PrefetchResult?> _prefetchNextEvent(String lang) async {
    final world = _requireWorld();
    final previousEventText = _currentEventTranscriptText();
    final memorySnapshot = _cloneMemoryCompressionManager(memoryCompression);
    final deltaSnapshot = _cloneDeltaState(_deltaState);

    await _compressCurrentEventIfNeeded(lang, manager: memorySnapshot);

    final nextId = world.getNextEventId(_currentEventId);
    if (nextId == null) {
      return _PrefetchResult(
        action: _PrefetchAction.advanceToNextEvent,
        narrative: _endingNarrative(lang),
        phase: _phase,
        eventId: _currentEventId,
        awaitingNextEvent: false,
        gameEnded: true,
        deltaStateJson: deltaSnapshot.toJson(),
        memoryCompressionJson: memorySnapshot?.toJson(),
      );
    }

    final nextEvent = world.getEvent(nextId);
    if (nextEvent == null) {
      return null;
    }

    deltaSnapshot.advanceTimeline(nextEventId: nextId);
    final narrative = await _entryNarrative(
      nextEvent,
      lang,
      previousEventText: previousEventText,
      deltaState: deltaSnapshot,
      memoryManager: memorySnapshot,
    );

    return _PrefetchResult(
      action: _PrefetchAction.advanceToNextEvent,
      narrative: narrative,
      phase: 'setup',
      eventId: nextId,
      awaitingNextEvent: nextEvent.type == 'narrative',
      gameEnded: false,
      deltaStateJson: deltaSnapshot.toJson(),
      memoryCompressionJson: memorySnapshot?.toJson(),
    );
  }

  Future<_PrefetchResult?> _prefetchConfrontation(String lang) async {
    final event = _requireCurrentEvent();
    if (event.type != 'interactive') {
      return null;
    }

    final narrative = await _confrontationPrompt(
      event,
      lang,
      deltaState: _deltaState,
      memoryManager: memoryCompression,
    );
    return _PrefetchResult(
      action: _PrefetchAction.advanceFromSetup,
      narrative: narrative,
      phase: 'confrontation',
      eventId: event.id,
      awaitingNextEvent: false,
      gameEnded: false,
      deltaStateJson: _deltaState.toJson(),
      memoryCompressionJson: memoryCompression?.toJson(),
    );
  }

  void _applyPrefetchResult(_PrefetchResult result) {
    _deltaState = LocalDeltaStateManager.fromJson(result.deltaStateJson);
    memoryCompression?.restoreFromJson(result.memoryCompressionJson);

    if (result.action == _PrefetchAction.advanceToNextEvent &&
        result.gameEnded) {
      _gameEnded = true;
      _awaitingNextEvent = false;
      _currentDeviationHistory.clear();
      return;
    }

    if (result.action == _PrefetchAction.advanceToNextEvent) {
      _currentDeviationHistory.clear();
      _currentEventId = result.eventId;
      _phase = result.phase;
      _awaitingNextEvent = result.awaitingNextEvent;
      _gameEnded = false;
      _currentEventTranscriptStart = _transcript.length;
      return;
    }

    _currentEventId = result.eventId;
    _phase = result.phase;
    _awaitingNextEvent = result.awaitingNextEvent;
    _gameEnded = result.gameEnded;
  }

  void _invalidatePrefetch() {
    _prefetchSlot = null;
  }

  String _buildPrefetchKey(String lang) {
    final activeDeltas = _deltaState.active
        .map((entry) => '${entry.id}:${entry.fact}:${entry.intensity}')
        .join('|');
    final archivedDeltas = _deltaState.archived
        .map((entry) => '${entry.id}:${entry.fact}:${entry.intensity}')
        .join('|');
    return <String>[
      lang,
      _world?.filename ?? '',
      _currentEventId ?? '',
      _phase ?? '',
      _turn.toString(),
      _awaitingNextEvent.toString(),
      _gameEnded.toString(),
      _transcript.length.toString(),
      _currentEventTranscriptStart.toString(),
      activeDeltas,
      archivedDeltas,
    ].join('::');
  }

  LocalDeltaStateManager _cloneDeltaState(LocalDeltaStateManager source) {
    return LocalDeltaStateManager.fromJson(source.toJson());
  }

  LocalMemoryCompressionManager? _cloneMemoryCompressionManager(
    LocalMemoryCompressionManager? source,
  ) {
    if (source == null) {
      return null;
    }

    final clone = LocalMemoryCompressionManager(
      store: source.store,
      llmClient: source.llmClient,
      loadConfig: source.loadConfig,
    );
    clone.restoreFromJson(source.toJson());
    return clone;
  }

  Stream<SseEvent> _advanceToNextEvent(String lang) async* {
    final world = _requireWorld();
    final previousEventText = _currentEventTranscriptText();
    await _compressCurrentEventIfNeeded(lang);
    final nextId = world.getNextEventId(_currentEventId);
    if (nextId == null) {
      _gameEnded = true;
      _awaitingNextEvent = false;
      _currentDeviationHistory.clear();
      final ending = _endingNarrative(lang);
      _appendNarration(ending);
      yield* _emitNarrative(ending);
      return;
    }

    final nextEvent = world.getEvent(nextId);
    if (nextEvent == null) {
      throw const ApiException('The next event could not be loaded.');
    }

    _deltaState.advanceTimeline(nextEventId: nextId);
    _currentDeviationHistory.clear();
    _currentEventId = nextId;
    _phase = 'setup';
    _awaitingNextEvent = false;
    _currentEventTranscriptStart = _transcript.length;

    final narrative = await _entryNarrative(
      nextEvent,
      lang,
      previousEventText: previousEventText,
    );
    _appendNarration(narrative);
    if (nextEvent.type == 'narrative') {
      _awaitingNextEvent = true;
    }
    _maybeSchedulePrefetch(lang);

    yield* _emitNarrative(narrative);
  }

  Stream<SseEvent> _emitNarrative(String narrative) async* {
    yield SseEvent.state(_gameStateData());
    for (final chunk in _chunkText(narrative)) {
      yield SseEvent.chunk(chunk);
      await Future<void>.delayed(const Duration(milliseconds: 8));
    }
    yield const SseEvent.done();
  }

  Iterable<String> _chunkText(String text) sync* {
    final normalized = text.trim();
    if (normalized.isEmpty) {
      return;
    }

    final parts = normalized.split(RegExp(r'(?<=[。！？!?\.])'));
    for (final part in parts) {
      final value = part.trim();
      if (value.isEmpty) {
        continue;
      }
      yield value.endsWith('\n') ? value : '$value\n';
    }
  }

  Future<String> _setupNarrative(
    LocalWorldEvent event,
    String lang, {
    LocalDeltaStateManager? deltaState,
    LocalMemoryCompressionManager? memoryManager,
  }) async {
    final fallback =
        _world!.getPhaseTextFull(event.id, 'setup') ??
        _world!.getEventTextFull(event.id) ??
        _world!.getPhaseDecisionText(event.id, 'setup') ??
        _world!.getEventDecisionText(event.id) ??
        (lang.startsWith('en') ? 'A new event begins.' : '新的事件开始了。');

    return _renderNarrative(
      phase: 'setup',
      lang: lang,
      event: event,
      phaseSource:
          _world!.getPhaseTextFull(event.id, 'setup') ??
          _world!.getEventTextFull(event.id) ??
          fallback,
      fallback: fallback,
      deltaState: deltaState,
      memoryManager: memoryManager,
    );
  }

  Future<String> _confrontationPrompt(
    LocalWorldEvent event,
    String lang, {
    LocalDeltaStateManager? deltaState,
    LocalMemoryCompressionManager? memoryManager,
  }) async {
    final fallback =
        _world!.getPhaseTextFull(event.id, 'confrontation') ??
        _world!.getPhaseDecisionText(event.id, 'confrontation') ??
        (lang.startsWith('en') ? 'What will you do next?' : '接下来你准备怎么做？');

    return _renderNarrative(
      phase: 'confrontation',
      lang: lang,
      event: event,
      phaseSource:
          _world!.getPhaseTextFull(event.id, 'confrontation') ??
          _world!.getPhaseDecisionText(event.id, 'confrontation') ??
          fallback,
      fallback: fallback,
      deltaState: deltaState,
      memoryManager: memoryManager,
    );
  }

  Future<String> _resolutionNarrative(
    LocalWorldEvent event,
    String action,
    String lang, {
    LocalDeviationAnalysis? analysis,
    LocalDeltaStateManager? deltaState,
    LocalMemoryCompressionManager? memoryManager,
  }) async {
    final resolution =
        _world!.getPhaseTextFull(event.id, 'resolution') ??
        _world!.getPhaseDecisionText(event.id, 'resolution') ??
        event.goal;
    final fallback = lang.startsWith('en')
        ? 'You choose: $action\n\n$resolution'
        : '你选择了：$action\n\n$resolution';

    return _renderNarrative(
      phase: 'resolution',
      lang: lang,
      event: event,
      phaseSource: resolution,
      fallback: fallback,
      playerAction: action,
      agentNotes: analysis?.asPromptNote(locale: lang),
      deltaState: deltaState,
      memoryManager: memoryManager,
    );
  }

  Future<String> _renderNarrative({
    required String phase,
    required String lang,
    required LocalWorldEvent event,
    required String phaseSource,
    required String fallback,
    String? playerAction,
    String? agentNotes,
    LocalDeltaStateManager? deltaState,
    LocalMemoryCompressionManager? memoryManager,
  }) async {
    final resolvedDeltaState = deltaState ?? _deltaState;
    final adaptation = await _sceneAdaptation(
      phase: phase,
      lang: lang,
      event: event,
      phaseSource: phaseSource,
      fallback: fallback,
      deltaState: resolvedDeltaState,
    );
    final resolvedPhaseSource = adaptation?.adaptedPhaseSource ?? phaseSource;
    final resolvedFallback = adaptation?.adaptedFallbackText ?? fallback;
    final generator = narrativeGenerator;
    if (generator == null) {
      return resolvedFallback;
    }

    final generated = await generator.generate(
      LocalNarrativeRequest(
        locale: lang,
        phase: phase,
        worldTitle: _world!.title,
        eventId: event.id,
        eventType: event.type,
        eventGoal: event.goal,
        eventDecisionText: event.decisionText,
        turn: _turn,
        phaseSource: resolvedPhaseSource,
        fallbackText: resolvedFallback,
        playerAction: playerAction,
        playerName: _playerName,
        previousStory: _recentStoryContext(),
        historyContext: _historyContext(
          event: event,
          phaseSource: resolvedPhaseSource,
          playerAction: playerAction,
        ),
        memoryContext: _memoryContext(
          event: event,
          phaseSource: resolvedPhaseSource,
          playerAction: playerAction,
          manager: memoryManager,
        ),
        entityContext: _entityContext(
          event: event,
          phaseSource: resolvedPhaseSource,
          playerAction: playerAction,
        ),
        preconditionsText: _preconditionsText(event, lang),
        deltaContext: resolvedDeltaState.formatContext(locale: lang),
        agentNotes: agentNotes,
        adaptationPlanText: adaptation?.adaptationPlanText,
      ),
    );

    if (generated == null || generated.trim().isEmpty) {
      return resolvedFallback;
    }
    return generated.trim();
  }

  Future<String> _entryNarrative(
    LocalWorldEvent event,
    String lang, {
    required String previousEventText,
    LocalDeltaStateManager? deltaState,
    LocalMemoryCompressionManager? memoryManager,
  }) async {
    final bridgeNarrative = await _bridgeNarrative(
      event: event,
      lang: lang,
      previousEventText: previousEventText,
      deltaState: deltaState,
    );
    if (bridgeNarrative != null && bridgeNarrative.trim().isNotEmpty) {
      return bridgeNarrative.trim();
    }
    return _setupNarrative(
      event,
      lang,
      deltaState: deltaState,
      memoryManager: memoryManager,
    );
  }

  Future<String?> _bridgeNarrative({
    required LocalWorldEvent event,
    required String lang,
    required String previousEventText,
    LocalDeltaStateManager? deltaState,
  }) async {
    final planner = bridgePlanner;
    final world = _world;
    final resolvedDeltaState = deltaState ?? _deltaState;
    if (planner == null || world == null || resolvedDeltaState.active.isEmpty) {
      return null;
    }

    final phaseSource =
        world.getPhaseTextFull(event.id, 'setup') ??
        world.getEventTextFull(event.id) ??
        event.goal;
    final plan = await planner.plan(
      locale: lang,
      deltaState: resolvedDeltaState,
      nextEvent: event,
      nextPhaseSource: phaseSource,
      preconditions: world.getPreconditions(event.id),
      previousEvent: previousEventText,
    );
    if (plan == null || plan.bridgeNarrative.trim().isEmpty) {
      return null;
    }

    for (final evolution in plan.deltaEvolutions) {
      resolvedDeltaState.evolveDelta(
        deltaId: evolution.originalDeltaId,
        newFact: evolution.evolvedFact,
        newIntensity: evolution.evolvedIntensity,
      );
    }
    return plan.bridgeNarrative.trim();
  }

  Future<LocalSceneAdaptationResult?> _sceneAdaptation({
    required String phase,
    required String lang,
    required LocalWorldEvent event,
    required String phaseSource,
    required String fallback,
    LocalDeltaStateManager? deltaState,
  }) async {
    final planner = sceneAdaptationPlanner;
    final resolvedDeltaState = deltaState ?? _deltaState;
    if (planner == null || resolvedDeltaState.active.isEmpty) {
      return null;
    }

    return planner.adapt(
      locale: lang,
      phase: phase,
      event: event,
      phaseSource: phaseSource,
      fallbackText: fallback,
      deltaState: resolvedDeltaState,
    );
  }

  String _historyContext({
    required LocalWorldEvent event,
    required String phaseSource,
    required String? playerAction,
  }) {
    return _contextEnrichment.buildHistoryContext(
      query: _contextQuery(
        event: event,
        phaseSource: phaseSource,
        playerAction: playerAction,
      ),
      transcriptEntries: _transcript.map((entry) => entry.resumeText).toList(),
    );
  }

  String _memoryContext({
    required LocalWorldEvent event,
    required String phaseSource,
    required String? playerAction,
    LocalMemoryCompressionManager? manager,
  }) {
    final resolvedManager = manager ?? memoryCompression;
    if (resolvedManager == null) {
      return '';
    }
    return resolvedManager.buildRecallContext(
      query: _contextQuery(
        event: event,
        phaseSource: phaseSource,
        playerAction: playerAction,
      ),
      currentEventId: event.id,
    );
  }

  String _entityContext({
    required LocalWorldEvent event,
    required String phaseSource,
    required String? playerAction,
  }) {
    return _contextEnrichment.buildEntityContext(
      world: _world!,
      query: _contextQuery(
        event: event,
        phaseSource: phaseSource,
        playerAction: playerAction,
      ),
    );
  }

  String _contextQuery({
    required LocalWorldEvent event,
    required String phaseSource,
    required String? playerAction,
  }) {
    return <String>[
      event.goal,
      event.decisionText,
      phaseSource,
      playerAction ?? '',
    ].where((value) => value.trim().isNotEmpty).join('\n');
  }

  String _preconditionsText(LocalWorldEvent event, String lang) {
    final world = _world;
    if (world == null) {
      return '';
    }

    final preconditions = world
        .getPreconditions(event.id)
        .where((condition) => (condition.fromValue ?? '').trim().isNotEmpty)
        .toList();
    if (preconditions.isEmpty) {
      return '';
    }

    return preconditions
        .map((condition) {
          final fromValue = condition.fromValue!.trim();
          if (lang.startsWith('en')) {
            return '- ${condition.name} (${condition.type}) must have ${_attributeLabelEn(condition.attribute)} = $fromValue';
          }
          return '- ${condition.name}（${condition.type}）的${condition.attribute}必须为$fromValue';
        })
        .join('\n');
  }

  String _attributeLabelEn(String attribute) {
    return switch (attribute) {
      '\u5730\u70b9' => 'location',
      '\u6301\u6709\u8005' => 'holder',
      '\u77e5\u6653\u8005' => 'knower',
      _ => attribute,
    };
  }

  String _recentStoryContext() {
    if (_transcript.isEmpty) {
      return '';
    }

    final entries = _transcript.length <= 6
        ? _transcript
        : _transcript.sublist(_transcript.length - 6);
    return entries.map((entry) => entry.resumeText).join('\n\n');
  }

  Future<void> _compressCurrentEventIfNeeded(
    String lang, {
    LocalMemoryCompressionManager? manager,
  }) async {
    final resolvedManager = manager ?? memoryCompression;
    final eventId = _currentEventId;
    if (resolvedManager == null || eventId == null || eventId.isEmpty) {
      return;
    }

    final content = _currentEventTranscriptText();
    if (content.trim().isEmpty) {
      return;
    }
    await resolvedManager.compressEvent(
      locale: lang,
      eventId: eventId,
      eventContent: content,
    );
  }

  String _currentEventTranscriptText() {
    if (_currentEventTranscriptStart >= _transcript.length) {
      return '';
    }
    return _transcript
        .sublist(_currentEventTranscriptStart)
        .map((entry) => entry.resumeText)
        .join('\n\n')
        .trim();
  }

  String _summarizeNarrative(String narrative) {
    final compact = narrative.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (compact.length <= 160) {
      return compact;
    }
    return '${compact.substring(0, 160)}...';
  }

  String _endingNarrative(String lang) {
    final title = _world?.title ?? 'WhatIf';
    return lang.startsWith('en')
        ? 'The story of "$title" ends here.'
        : '《$title》的故事到此结束。';
  }

  String _defaultSaveDescription(LocalWorldEvent? event) {
    if (event == null) {
      return 'Turn $_turn';
    }
    final base = event.decisionText.trim().isNotEmpty
        ? event.decisionText.trim()
        : event.goal.trim();
    return '$base - ${_phase ?? 'setup'} - Turn $_turn';
  }

  String _resumeText() {
    if (_transcript.isEmpty) {
      return '';
    }
    return _transcript.map((entry) => entry.resumeText).join('\n\n');
  }

  void _appendNarration(String text) {
    _transcript.add(_TranscriptEntry.narration(text));
  }

  void _appendSystem(String text) {
    _transcript.add(_TranscriptEntry.system(text));
  }

  GameStateData _gameStateData() {
    final event = _world?.getEvent(_currentEventId);
    return GameStateData(
      phase: _phase,
      eventId: _currentEventId,
      turn: _turn,
      awaitingNextEvent: _awaitingNextEvent,
      gameEnded: _gameEnded,
      eventHasImage: (event?.image ?? '').isNotEmpty,
    );
  }
}

enum _PrefetchAction { advanceToNextEvent, advanceFromSetup }

class _PrefetchSlot {
  _PrefetchSlot({required this.key, required this.future});

  final String key;
  final Future<_PrefetchResult?> future;
  _PrefetchResult? result;
}

class _PrefetchResult {
  const _PrefetchResult({
    required this.action,
    required this.narrative,
    required this.phase,
    required this.eventId,
    required this.awaitingNextEvent,
    required this.gameEnded,
    required this.deltaStateJson,
    required this.memoryCompressionJson,
  });

  final _PrefetchAction action;
  final String narrative;
  final String? phase;
  final String? eventId;
  final bool awaitingNextEvent;
  final bool gameEnded;
  final Map<String, dynamic> deltaStateJson;
  final Map<String, dynamic>? memoryCompressionJson;
}

class _TranscriptEntry {
  const _TranscriptEntry._({required this.kind, required this.text});

  final String kind;
  final String text;

  factory _TranscriptEntry.narration(String text) {
    return _TranscriptEntry._(kind: 'narration', text: text);
  }

  factory _TranscriptEntry.player(String text) {
    return _TranscriptEntry._(kind: 'player', text: text);
  }

  factory _TranscriptEntry.system(String text) {
    return _TranscriptEntry._(kind: 'system', text: text);
  }

  factory _TranscriptEntry.fromJson(Map<String, dynamic> json) {
    return _TranscriptEntry._(
      kind: json['kind'] as String? ?? 'narration',
      text: json['text'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{'kind': kind, 'text': text};
  }

  String get resumeText => kind == 'player' ? '> $text' : text;
}

Map<String, dynamic>? _asMap(Object? value) {
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

List<Map<String, dynamic>> _asMapList(Object? value) {
  if (value is! List<dynamic>) {
    return const <Map<String, dynamic>>[];
  }

  return value.map(_asMap).whereType<Map<String, dynamic>>().toList();
}
