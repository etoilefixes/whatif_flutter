class LocalLorebookBuildResult {
  const LocalLorebookBuildResult({
    required this.characters,
    required this.locations,
    required this.items,
    required this.knowledge,
  });

  final List<Map<String, dynamic>> characters;
  final List<Map<String, dynamic>> locations;
  final List<Map<String, dynamic>> items;
  final List<Map<String, dynamic>> knowledge;
}

class LocalLorebookBuilder {
  const LocalLorebookBuilder();

  static const Set<String> _englishCharacterTitles = <String>{
    'captain',
    'commander',
    'doctor',
    'dr',
    'general',
    'guard',
    'lady',
    'lord',
    'master',
    'prince',
    'princess',
    'queen',
    'king',
    'sir',
  };

  static const Set<String> _englishLocationKeywords = <String>{
    'barracks',
    'bridge',
    'camp',
    'castle',
    'city',
    'court',
    'fortress',
    'forest',
    'gate',
    'garden',
    'hall',
    'harbor',
    'inn',
    'keep',
    'mountain',
    'palace',
    'pass',
    'road',
    'temple',
    'tower',
    'town',
    'village',
    'wall',
  };

  static const Set<String> _englishItemKeywords = <String>{
    'amulet',
    'blade',
    'book',
    'bow',
    'crown',
    'dagger',
    'key',
    'lantern',
    'letter',
    'map',
    'medallion',
    'ring',
    'scroll',
    'seal',
    'sword',
    'token',
    'torch',
  };

  static const Set<String> _englishCharacterStopwords = <String>{
    'chapter',
    'dawn',
    'evening',
    'midnight',
    'morning',
    'night',
    'someone',
    'something',
    'the',
    'they',
    'you',
  };

  static const Set<String> _chineseLocationSuffixes = <String>{
    '城',
    '镇',
    '村',
    '山',
    '谷',
    '宫',
    '殿',
    '楼',
    '阁',
    '门',
    '关',
    '营',
    '寨',
    '堂',
    '寺',
    '府',
    '路',
    '桥',
    '塔',
    '院',
    '海',
    '河',
    '湖',
    '江',
    '林',
  };

  static const Set<String> _chineseItemSuffixes = <String>{
    '剑',
    '刀',
    '信',
    '令牌',
    '地图',
    '卷轴',
    '书',
    '灯',
    '火把',
    '匕首',
    '弓',
    '印',
    '玉佩',
    '药',
    '箱',
    '钥匙',
    '戒指',
    '符',
    '冠',
    '珠',
  };

  LocalLorebookBuildResult build({
    required String locale,
    required String fullText,
    required List<String> sentences,
  }) {
    final characterCandidates = locale.startsWith('en')
        ? _extractEnglishCharacterCandidates(sentences)
        : _extractChineseCharacterCandidates(sentences);
    final locationCandidates = locale.startsWith('en')
        ? _extractEnglishLocationCandidates(sentences)
        : _extractChineseLocationCandidates(sentences);
    final itemCandidates = locale.startsWith('en')
        ? _extractEnglishItemCandidates(sentences)
        : _extractChineseItemCandidates(sentences);

    final characters = _buildCharacters(locale, characterCandidates);
    final characterMatchers = _characterMatchers(characters);
    final locations = _buildLocations(locale, locationCandidates);
    final items = _buildItems(locale, itemCandidates);
    final protagonistId = characters.first['id'] as String;
    final knowledge = _buildKnowledge(
      locale: locale,
      sentences: sentences,
      protagonistId: protagonistId,
      characterMatchers: characterMatchers,
    );

    return LocalLorebookBuildResult(
      characters: characters,
      locations: locations,
      items: items,
      knowledge: knowledge,
    );
  }

  List<Map<String, dynamic>> _buildCharacters(
    String locale,
    List<_EntityCandidate> candidates,
  ) {
    if (candidates.isEmpty) {
      return <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'protagonist',
          'name': locale.startsWith('en') ? 'Protagonist' : '主角',
          'aliases': <String>[],
          'importance': 'protagonist',
          'identity': <String, dynamic>{
            'role': locale.startsWith('en') ? 'Story Protagonist' : '故事主角',
          },
          'relationships': <List<dynamic>>[],
          'dialogue_examples': <List<dynamic>>[],
        },
      ];
    }

    final sorted = candidates.take(5).toList();
    final characters = <Map<String, dynamic>>[];
    for (var index = 0; index < sorted.length; index += 1) {
      final candidate = sorted[index];
      final isProtagonist = index == 0;
      final importance = isProtagonist
          ? 'protagonist'
          : candidate.count >= 2
          ? 'key'
          : 'supporting';
      final role = _characterRole(locale, candidate, isProtagonist);
      characters.add(<String, dynamic>{
        'id': isProtagonist ? 'protagonist' : 'character_${index + 1}',
        'name': candidate.display,
        'aliases': candidate.aliases
            .where((alias) => alias != candidate.display)
            .take(3)
            .toList(),
        'importance': importance,
        'identity': <String, dynamic>{'role': role},
        'relationships': <List<dynamic>>[],
        'dialogue_examples': candidate.contexts.take(2).toList(),
      });
    }
    return characters;
  }

  String _characterRole(
    String locale,
    _EntityCandidate candidate,
    bool isProtagonist,
  ) {
    if (candidate.tags.isNotEmpty) {
      final firstTag = candidate.tags.first;
      if (locale.startsWith('en')) {
        return _titleCase(firstTag);
      }
      return firstTag;
    }

    if (isProtagonist) {
      return locale.startsWith('en') ? 'Story Protagonist' : '故事主角';
    }
    return locale.startsWith('en') ? 'Supporting Character' : '配角';
  }

  List<Map<String, dynamic>> _buildLocations(
    String locale,
    List<_EntityCandidate> candidates,
  ) {
    return List<Map<String, dynamic>>.generate(candidates.take(5).length, (
      index,
    ) {
      final candidate = candidates[index];
      return <String, dynamic>{
        'id': 'location_${index + 1}',
        'name': candidate.display,
        'aliases': <String>[],
        'importance': index < 2 ? 'key' : 'normal',
        'type': _locationType(locale, candidate.display),
        'parent_location': null,
        'description': <String, dynamic>{
          'overview': candidate.contexts.isEmpty
              ? candidate.display
              : _trimToLength(candidate.contexts.first, 180),
          'atmosphere': null,
          'visual_details': null,
          'sounds': null,
          'smells': null,
          'notable_features': null,
        },
        'connected_to': <List<dynamic>>[],
      };
    });
  }

  String _locationType(String locale, String name) {
    if (locale.startsWith('en')) {
      final lower = name.toLowerCase();
      if (lower.endsWith('road') ||
          lower.endsWith('bridge') ||
          lower.endsWith('pass')) {
        return 'path';
      }
      if (lower.endsWith('city') ||
          lower.endsWith('town') ||
          lower.endsWith('village')) {
        return 'settlement';
      }
      if (lower.endsWith('forest') || lower.endsWith('mountain')) {
        return 'wilderness';
      }
      return 'building';
    }

    if (name.endsWith('路') || name.endsWith('桥')) {
      return 'path';
    }
    if (name.endsWith('城') || name.endsWith('镇') || name.endsWith('村')) {
      return 'settlement';
    }
    if (name.endsWith('山') ||
        name.endsWith('谷') ||
        name.endsWith('海') ||
        name.endsWith('河') ||
        name.endsWith('湖') ||
        name.endsWith('江') ||
        name.endsWith('林')) {
      return 'wilderness';
    }
    return 'building';
  }

  List<Map<String, dynamic>> _buildItems(
    String locale,
    List<_EntityCandidate> candidates,
  ) {
    return List<Map<String, dynamic>>.generate(candidates.take(5).length, (
      index,
    ) {
      final candidate = candidates[index];
      return <String, dynamic>{
        'id': 'item_${index + 1}',
        'name': candidate.display,
        'aliases': <String>[],
        'importance': candidate.count >= 2 ? 'key' : 'normal',
        'category': _itemCategory(locale, candidate.display),
        'description': <String, dynamic>{
          'appearance': candidate.contexts.isEmpty
              ? candidate.display
              : _trimToLength(candidate.contexts.first, 180),
          'material': null,
          'size': null,
        },
        'function': <String, dynamic>{
          'primary_use': _itemPrimaryUse(locale, candidate.display),
          'special_abilities': null,
          'limitations': null,
        },
        'significance': <String, dynamic>{
          'narrative_role': null,
          'symbolic_meaning': null,
        },
      };
    });
  }

  String _itemCategory(String locale, String name) {
    final lower = name.toLowerCase();
    if (lower.contains('sword') ||
        lower.contains('blade') ||
        lower.contains('dagger') ||
        lower.contains('bow') ||
        name.contains('剑') ||
        name.contains('刀') ||
        name.contains('匕首') ||
        name.contains('弓')) {
      return 'weapon';
    }
    if (lower.contains('key') ||
        lower.contains('seal') ||
        lower.contains('token') ||
        lower.contains('amulet') ||
        lower.contains('ring') ||
        name.contains('钥匙') ||
        name.contains('令牌') ||
        name.contains('印') ||
        name.contains('玉佩') ||
        name.contains('戒指')) {
      return 'key_item';
    }
    if (lower.contains('letter') ||
        lower.contains('map') ||
        lower.contains('scroll') ||
        lower.contains('book') ||
        name.contains('信') ||
        name.contains('地图') ||
        name.contains('卷轴') ||
        name.contains('书')) {
      return 'document';
    }
    if (lower.contains('lantern') ||
        lower.contains('torch') ||
        name.contains('灯') ||
        name.contains('火把')) {
      return 'tool';
    }
    return 'other';
  }

  String _itemPrimaryUse(String locale, String name) {
    final category = _itemCategory(locale, name);
    return switch (category) {
      'weapon' => locale.startsWith('en') ? 'Combat' : '战斗',
      'key_item' => locale.startsWith('en') ? 'Unlocking progress' : '推动剧情',
      'document' => locale.startsWith('en') ? 'Carrying information' : '承载信息',
      'tool' => locale.startsWith('en') ? 'Practical use' : '实际用途',
      _ => locale.startsWith('en') ? 'Story object' : '剧情物件',
    };
  }

  List<Map<String, dynamic>> _buildKnowledge({
    required String locale,
    required List<String> sentences,
    required String protagonistId,
    required List<_CharacterMatcher> characterMatchers,
  }) {
    final entries = <Map<String, dynamic>>[];
    final seen = <String>{};

    for (final sentence in sentences) {
      if (!_looksLikeKnowledge(locale, sentence)) {
        continue;
      }

      final summary = _knowledgeSummary(sentence, locale);
      final key = summary.toLowerCase();
      if (!seen.add(key)) {
        continue;
      }

      final holders = <String>{
        for (final matcher in characterMatchers)
          if (matcher.matches(sentence)) matcher.id,
      };
      if (holders.isEmpty) {
        holders.add(protagonistId);
      }

      entries.add(<String, dynamic>{
        'id': 'knowledge_${entries.length + 1}',
        'name': summary,
        'initial_holders': holders.toList(),
        'description': _trimToLength(sentence.trim(), 220),
      });

      if (entries.length >= 5) {
        break;
      }
    }

    return entries;
  }

  bool _looksLikeKnowledge(String locale, String sentence) {
    if (locale.startsWith('en')) {
      return RegExp(
        r'\b(secret|truth|plan|warning|order|message|promise|rumor|news|must|would|will|betray|identity)\b',
        caseSensitive: false,
      ).hasMatch(sentence);
    }

    return RegExp(r'秘密|真相|计划|命令|消息|约定|传闻|警告|必须|得知|知道|预言').hasMatch(sentence);
  }

  String _knowledgeSummary(String sentence, String locale) {
    final compact = sentence.replaceAll(RegExp(r'\s+'), ' ').trim();
    final parts = compact.split(RegExp(r'[,:;，：；]'));
    final summary = parts.first.trim();
    if (summary.isEmpty) {
      return locale.startsWith('en') ? 'Story knowledge' : '剧情信息';
    }
    return _trimToLength(summary, 72);
  }

  List<_EntityCandidate> _extractEnglishCharacterCandidates(
    List<String> sentences,
  ) {
    final stats = <String, _EntityCandidate>{};
    final pattern = RegExp(r'\b[A-Z][a-z]+(?:\s+[A-Z][a-z]+){0,2}\b');

    for (var index = 0; index < sentences.length; index += 1) {
      final sentence = sentences[index];
      for (final match in pattern.allMatches(sentence)) {
        final raw = match.group(0);
        if (raw == null) {
          continue;
        }

        final normalized = _normalizeEnglishCharacter(raw);
        if (normalized == null) {
          continue;
        }

        _recordCandidate(
          stats: stats,
          key: normalized.name.toLowerCase(),
          display: normalized.name,
          sentenceIndex: index,
          sentence: sentence,
          alias: raw,
          tag: normalized.title,
        );
      }
    }

    return _sortedCandidates(
      stats.values.where(
        (candidate) =>
            candidate.count >= 2 ||
            candidate.tags.isNotEmpty ||
            _hasCharacterContext(true, candidate.contexts),
      ),
    );
  }

  _EnglishCharacterNormalization? _normalizeEnglishCharacter(String raw) {
    final words = raw.trim().split(RegExp(r'\s+'));
    if (words.isEmpty) {
      return null;
    }

    var title = '';
    var nameWords = words;
    final firstLower = words.first.toLowerCase().replaceAll('.', '');
    if (_englishCharacterTitles.contains(firstLower) && words.length > 1) {
      title = words.first;
      nameWords = words.sublist(1);
    }

    if (nameWords.isEmpty) {
      return null;
    }

    final canonical = nameWords.join(' ');
    final canonicalLower = canonical.toLowerCase();
    final finalWord = nameWords.last.toLowerCase();
    if (_englishCharacterStopwords.contains(canonicalLower) ||
        _englishLocationKeywords.contains(finalWord) ||
        _englishItemKeywords.contains(finalWord) ||
        canonicalLower.startsWith('chapter ')) {
      return null;
    }

    return _EnglishCharacterNormalization(name: canonical, title: title);
  }

  List<_EntityCandidate> _extractChineseCharacterCandidates(
    List<String> sentences,
  ) {
    final stats = <String, _EntityCandidate>{};
    final patterns = <RegExp>[
      RegExp(r'(?:名叫|叫做|叫|是)([\u4e00-\u9fff]{2,4})'),
      RegExp(r'([\u4e00-\u9fff]{2,4})(?:说道|说|问道|问|喊道|喊|低声|看向|望向)'),
    ];
    final stopwords = <String>{'自己', '他们', '我们', '这里', '那里', '主角', '对方'};

    for (var index = 0; index < sentences.length; index += 1) {
      final sentence = sentences[index];
      for (final pattern in patterns) {
        for (final match in pattern.allMatches(sentence)) {
          final raw = match.group(1);
          if (raw == null ||
              stopwords.contains(raw) ||
              _endsWithAny(raw, _chineseLocationSuffixes) ||
              _endsWithAny(raw, _chineseItemSuffixes)) {
            continue;
          }

          _recordCandidate(
            stats: stats,
            key: raw,
            display: raw,
            sentenceIndex: index,
            sentence: sentence,
            alias: raw,
          );
        }
      }
    }

    return _sortedCandidates(
      stats.values.where(
        (candidate) =>
            candidate.count >= 2 ||
            _hasCharacterContext(false, candidate.contexts),
      ),
    );
  }

  List<_EntityCandidate> _extractEnglishLocationCandidates(
    List<String> sentences,
  ) {
    final stats = <String, _EntityCandidate>{};
    final exactPattern = RegExp(
      r'\b[A-Z][a-z]+(?:\s+[A-Z][a-z]+){0,2}\s(?:Barracks|Bridge|Camp|Castle|City|Court|Fortress|Forest|Gate|Garden|Hall|Harbor|Inn|Keep|Mountain|Palace|Pass|Road|Temple|Tower|Town|Village|Wall)\b',
    );
    final genericPattern = RegExp(
      r'\b(?:the\s+)?(?:[a-z]+(?:\s+[a-z]+){0,2}\s(?:barracks|bridge|camp|castle|city|court|fortress|forest|gate|garden|hall|harbor|inn|keep|mountain|palace|pass|road|temple|tower|town|village|wall))\b',
      caseSensitive: false,
    );

    for (var index = 0; index < sentences.length; index += 1) {
      final sentence = sentences[index];
      for (final match in exactPattern.allMatches(sentence)) {
        final raw = match.group(0);
        if (raw == null) {
          continue;
        }
        final display = raw.trim();
        _recordCandidate(
          stats: stats,
          key: display.toLowerCase(),
          display: display,
          sentenceIndex: index,
          sentence: sentence,
          alias: display,
        );
      }
      for (final match in genericPattern.allMatches(sentence)) {
        final raw = match.group(0);
        if (raw == null) {
          continue;
        }
        final display = raw
            .replaceFirst(RegExp(r'^(the|a|an)\s+', caseSensitive: false), '')
            .trim();
        _recordCandidate(
          stats: stats,
          key: display.toLowerCase(),
          display: display,
          sentenceIndex: index,
          sentence: sentence,
          alias: display,
        );
      }
    }

    return _sortedCandidates(stats.values);
  }

  List<_EntityCandidate> _extractChineseLocationCandidates(
    List<String> sentences,
  ) {
    final stats = <String, _EntityCandidate>{};
    final pattern = RegExp(
      r'[\u4e00-\u9fff]{1,8}(?:城|镇|村|山|谷|宫|殿|楼|阁|门|关|营|寨|堂|寺|府|路|桥|塔|院|海|河|湖|江|林)',
    );

    for (var index = 0; index < sentences.length; index += 1) {
      final sentence = sentences[index];
      for (final match in pattern.allMatches(sentence)) {
        final raw = match.group(0);
        if (raw == null) {
          continue;
        }

        final display = raw.trim();
        _recordCandidate(
          stats: stats,
          key: display,
          display: display,
          sentenceIndex: index,
          sentence: sentence,
          alias: display,
        );
      }
    }

    return _sortedCandidates(stats.values);
  }

  List<_EntityCandidate> _extractEnglishItemCandidates(List<String> sentences) {
    final stats = <String, _EntityCandidate>{};
    final pattern = RegExp(
      r'\b(?:the\s+)?(?:[A-Za-z]+\s+){0,2}(?:amulet|blade|book|bow|crown|dagger|key|lantern|letter|map|medallion|ring|scroll|seal|sword|token|torch)\b',
      caseSensitive: false,
    );

    for (var index = 0; index < sentences.length; index += 1) {
      final sentence = sentences[index];
      for (final match in pattern.allMatches(sentence)) {
        final raw = match.group(0);
        if (raw == null) {
          continue;
        }
        final display = raw
            .replaceFirst(RegExp(r'^(the|a|an)\s+', caseSensitive: false), '')
            .trim();
        _recordCandidate(
          stats: stats,
          key: display.toLowerCase(),
          display: display,
          sentenceIndex: index,
          sentence: sentence,
          alias: display,
        );
      }
    }

    return _sortedCandidates(stats.values);
  }

  List<_EntityCandidate> _extractChineseItemCandidates(List<String> sentences) {
    final stats = <String, _EntityCandidate>{};
    final pattern = RegExp(
      r'[\u4e00-\u9fff]{0,4}(?:剑|刀|信|令牌|地图|卷轴|书|灯|火把|匕首|弓|印|玉佩|药|箱|钥匙|戒指|符|冠|珠)',
    );

    for (var index = 0; index < sentences.length; index += 1) {
      final sentence = sentences[index];
      for (final match in pattern.allMatches(sentence)) {
        final raw = match.group(0);
        if (raw == null) {
          continue;
        }
        final display = raw.trim();
        _recordCandidate(
          stats: stats,
          key: display,
          display: display,
          sentenceIndex: index,
          sentence: sentence,
          alias: display,
        );
      }
    }

    return _sortedCandidates(stats.values);
  }

  void _recordCandidate({
    required Map<String, _EntityCandidate> stats,
    required String key,
    required String display,
    required int sentenceIndex,
    required String sentence,
    String? alias,
    String? tag,
  }) {
    final candidate = stats.putIfAbsent(
      key,
      () => _EntityCandidate(display: display, firstIndex: sentenceIndex),
    );
    candidate.count += 1;
    if (alias != null && alias.trim().isNotEmpty) {
      candidate.aliases.add(alias.trim());
    }
    if (tag != null && tag.trim().isNotEmpty) {
      candidate.tags.add(tag.trim());
    }
    final trimmedSentence = sentence.trim();
    if (trimmedSentence.isNotEmpty &&
        !candidate.contexts.contains(trimmedSentence) &&
        candidate.contexts.length < 3) {
      candidate.contexts.add(trimmedSentence);
    }
  }

  List<_EntityCandidate> _sortedCandidates(Iterable<_EntityCandidate> values) {
    final sorted = values.toList()
      ..sort((left, right) {
        final byCount = right.count.compareTo(left.count);
        if (byCount != 0) {
          return byCount;
        }
        return left.firstIndex.compareTo(right.firstIndex);
      });
    return sorted;
  }

  bool _hasCharacterContext(bool english, List<String> contexts) {
    final pattern = english
        ? RegExp(
            r'\b(said|asked|shouted|warned|whispered|replied|looked|turned|gripped|held|carried|called|screamed)\b',
            caseSensitive: false,
          )
        : RegExp(r'说|问|喊|看|握|拿|叫|低声|喝道');
    return contexts.any(pattern.hasMatch);
  }

  List<_CharacterMatcher> _characterMatchers(
    List<Map<String, dynamic>> characters,
  ) {
    return characters.map((character) {
      final aliases = <String>{
        character['name'] as String? ?? '',
        ...((character['aliases'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<String>()),
      }.where((value) => value.trim().isNotEmpty).toList();
      return _CharacterMatcher(
        id: character['id'] as String,
        aliases: aliases.toList(),
      );
    }).toList();
  }

  bool _endsWithAny(String value, Set<String> suffixes) {
    return suffixes.any(value.endsWith);
  }

  String _trimToLength(String text, int maxLength) {
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= maxLength) {
      return normalized;
    }
    return '${normalized.substring(0, maxLength)}...';
  }

  String _titleCase(String value) {
    if (value.isEmpty) {
      return value;
    }
    return value[0].toUpperCase() + value.substring(1).toLowerCase();
  }
}

class _EntityCandidate {
  _EntityCandidate({required this.display, required this.firstIndex});

  final String display;
  final int firstIndex;
  int count = 0;
  final Set<String> aliases = <String>{};
  final Set<String> tags = <String>{};
  final List<String> contexts = <String>[];
}

class _EnglishCharacterNormalization {
  const _EnglishCharacterNormalization({
    required this.name,
    required this.title,
  });

  final String name;
  final String title;
}

class _CharacterMatcher {
  const _CharacterMatcher({required this.id, required this.aliases});

  final String id;
  final List<String> aliases;

  bool matches(String sentence) {
    final lower = sentence.toLowerCase();
    for (final alias in aliases) {
      if (alias.isEmpty) {
        continue;
      }
      if (lower.contains(alias.toLowerCase())) {
        return true;
      }
    }
    return false;
  }
}
