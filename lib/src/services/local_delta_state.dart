class LocalDeltaEntry {
  const LocalDeltaEntry({
    required this.id,
    required this.fact,
    required this.sourceEventId,
    required this.intensity,
    required this.createdTurn,
    this.status = 'active',
    this.archivedSummary,
  });

  final String id;
  final String fact;
  final String sourceEventId;
  final int intensity;
  final int createdTurn;
  final String status;
  final String? archivedSummary;

  factory LocalDeltaEntry.fromJson(Map<String, dynamic> json) {
    return LocalDeltaEntry(
      id: json['id'] as String? ?? '',
      fact: json['fact'] as String? ?? '',
      sourceEventId: json['sourceEventId'] as String? ?? '',
      intensity: (json['intensity'] as num?)?.toInt() ?? 1,
      createdTurn: (json['createdTurn'] as num?)?.toInt() ?? 0,
      status: json['status'] as String? ?? 'active',
      archivedSummary: json['archivedSummary'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'fact': fact,
      'sourceEventId': sourceEventId,
      'intensity': intensity,
      'createdTurn': createdTurn,
      'status': status,
      if (archivedSummary != null) 'archivedSummary': archivedSummary,
    };
  }

  LocalDeltaEntry copyWith({
    String? id,
    String? fact,
    String? sourceEventId,
    int? intensity,
    int? createdTurn,
    String? status,
    String? archivedSummary,
  }) {
    return LocalDeltaEntry(
      id: id ?? this.id,
      fact: fact ?? this.fact,
      sourceEventId: sourceEventId ?? this.sourceEventId,
      intensity: intensity ?? this.intensity,
      createdTurn: createdTurn ?? this.createdTurn,
      status: status ?? this.status,
      archivedSummary: archivedSummary ?? this.archivedSummary,
    );
  }
}

class LocalDeltaStateManager {
  LocalDeltaStateManager();

  final List<LocalDeltaEntry> _active = <LocalDeltaEntry>[];
  final List<LocalDeltaEntry> _archived = <LocalDeltaEntry>[];
  int _nextId = 1;

  List<LocalDeltaEntry> get active =>
      List<LocalDeltaEntry>.unmodifiable(_active);
  List<LocalDeltaEntry> get archived =>
      List<LocalDeltaEntry>.unmodifiable(_archived);

  void reset() {
    _active.clear();
    _archived.clear();
    _nextId = 1;
  }

  LocalDeltaEntry createDelta({
    required String fact,
    required String sourceEventId,
    required int createdTurn,
    int intensity = 3,
  }) {
    final normalizedFact = fact.trim();
    final existingIndex = _active.indexWhere(
      (entry) => entry.fact == normalizedFact,
    );
    if (existingIndex >= 0) {
      final boosted = _active[existingIndex].copyWith(
        intensity: _clampIntensity(_active[existingIndex].intensity + 1),
      );
      _active[existingIndex] = boosted;
      return boosted;
    }

    final entry = LocalDeltaEntry(
      id: 'delta-${_nextId.toString().padLeft(3, '0')}',
      fact: normalizedFact,
      sourceEventId: sourceEventId,
      intensity: _clampIntensity(intensity),
      createdTurn: createdTurn,
    );
    _nextId += 1;
    _active.add(entry);
    return entry;
  }

  void advanceTimeline({required String nextEventId}) {
    if (nextEventId.isEmpty) {
      return;
    }

    final nextActive = <LocalDeltaEntry>[];
    for (final entry in _active) {
      final decayed = entry.copyWith(
        intensity: _clampIntensity(entry.intensity - 1),
      );
      if (decayed.intensity <= 0) {
        _archived.add(
          decayed.copyWith(
            status: 'archived',
            archivedSummary: _buildArchivedSummary(decayed.fact),
          ),
        );
      } else {
        nextActive.add(decayed);
      }
    }
    _active
      ..clear()
      ..addAll(nextActive);
  }

  LocalDeltaEntry? evolveDelta({
    required String deltaId,
    required String newFact,
    required int newIntensity,
  }) {
    final index = _active.indexWhere((entry) => entry.id == deltaId);
    if (index < 0) {
      return null;
    }

    final updated = _active[index].copyWith(
      fact: newFact.trim().isEmpty ? _active[index].fact : newFact.trim(),
      intensity: _clampIntensity(newIntensity),
    );
    _active[index] = updated;
    return updated;
  }

  String formatContext({required String locale}) {
    final parts = <String>[];
    if (_active.isNotEmpty) {
      parts.add(
        locale.startsWith('en') ? '[Active world changes]' : '[当前生效的世界变化]',
      );
      for (final entry in _active) {
        parts.add('- ${entry.fact} (intensity ${entry.intensity}/5)');
      }
    }
    if (_archived.isNotEmpty) {
      parts.add(
        locale.startsWith('en') ? '[Archived world changes]' : '[已归档的世界变化]',
      );
      for (final entry in _archived.take(5)) {
        parts.add('- ${entry.archivedSummary ?? entry.fact}');
      }
    }
    return parts.join('\n');
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'active': _active.map((entry) => entry.toJson()).toList(),
      'archived': _archived.map((entry) => entry.toJson()).toList(),
      'nextId': _nextId,
    };
  }

  factory LocalDeltaStateManager.fromJson(Map<String, dynamic>? json) {
    final manager = LocalDeltaStateManager();
    if (json == null) {
      return manager;
    }

    manager._active.addAll(
      _mapList(json['active']).map(LocalDeltaEntry.fromJson),
    );
    manager._archived.addAll(
      _mapList(json['archived']).map(LocalDeltaEntry.fromJson),
    );
    manager._nextId = (json['nextId'] as num?)?.toInt() ?? 1;
    return manager;
  }

  String _buildArchivedSummary(String fact) {
    final normalized = fact.trim();
    if (normalized.length <= 48) {
      return normalized;
    }
    return '${normalized.substring(0, 48)}...';
  }

  int _clampIntensity(int value) {
    if (value < 0) {
      return 0;
    }
    if (value > 5) {
      return 5;
    }
    return value;
  }
}

List<Map<String, dynamic>> _mapList(Object? value) {
  if (value is! List<dynamic>) {
    return const <Map<String, dynamic>>[];
  }

  return value
      .map<Map<String, dynamic>?>((item) {
        if (item is Map<String, dynamic>) {
          return item;
        }
        if (item is Map) {
          return item.map(
            (key, nestedValue) => MapEntry(key.toString(), nestedValue),
          );
        }
        return null;
      })
      .whereType<Map<String, dynamic>>()
      .toList();
}
