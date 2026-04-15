import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:flutter_client/src/models.dart';
import 'package:flutter_client/src/services/config_store.dart';
import 'package:flutter_client/src/services/storage_backend.dart';

void main() {
  test('ConfigStore.open migrates legacy shared preferences', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'locale': 'en-US',
      'backend_url': 'https://example.com/v1',
      'api_keys': jsonEncode(<String, String>{'openai': 'sk-test'}),
    });
    final prefs = await SharedPreferences.getInstance();
    final store = await ConfigStore.open(
      legacyPrefs: prefs,
      useInMemoryDatabase: true,
    );
    addTearDown(store.dispose);

    expect(store.getLocale(), 'en-US');
    expect(store.getBackendUrl(), 'https://example.com/v1');
    expect(store.getModelProviders(), hasLength(1));
    expect(store.getModelProviders().single.name, 'openai');
    expect(store.getModelProviders().single.apiKey, 'sk-test');
  });

  test('ConfigStore persists and reloads save snapshots', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final store = await ConfigStore.open(
      legacyPrefs: prefs,
      useInMemoryDatabase: true,
    );
    addTearDown(store.dispose);

    const info = SaveInfo(
      slot: 2,
      saveTime: '2026-04-15T12:30:00.000Z',
      playerName: 'Mira',
      currentPhase: 'resolution',
      currentEventId: 'event_2',
      totalTurns: 7,
      description: 'Gate falls at dawn',
      worldpkgTitle: 'Iron Gate',
    );
    const state = <String, dynamic>{
      'currentEventId': 'event_2',
      'phase': 'resolution',
      'turn': 7,
      'worldpkgFilename': 'iron_gate.wpkg',
    };

    await store.saveGameSnapshot(info: info, state: state);

    final saves = await store.listSavedGames();
    final snapshot = await store.getSavedGame(2);

    expect(saves, hasLength(1));
    expect(saves.single.description, 'Gate falls at dawn');
    expect(snapshot, isNotNull);
    expect(snapshot!.info.slot, 2);
    expect(snapshot.state['worldpkgFilename'], 'iron_gate.wpkg');
  });

  test('ConfigStore prunes stale package index records', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final prefs = await SharedPreferences.getInstance();
    final store = await ConfigStore.open(
      legacyPrefs: prefs,
      useInMemoryDatabase: true,
    );
    addTearDown(store.dispose);

    await store.upsertPackageRecord(
      const PersistedPackageRecord(
        filename: 'a.wpkg',
        title: 'Alpha',
        size: 10,
        hasCover: true,
        modifiedAtMs: 1,
        indexedAtMs: 2,
      ),
    );
    await store.upsertPackageRecord(
      const PersistedPackageRecord(
        filename: 'b.wpkg',
        title: 'Beta',
        size: 11,
        hasCover: false,
        modifiedAtMs: 3,
        indexedAtMs: 4,
      ),
    );

    await store.prunePackageRecords(<String>{'b.wpkg'});
    final records = await store.listPackageRecords();

    expect(records, hasLength(1));
    expect(records.single.filename, 'b.wpkg');
    expect(records.single.title, 'Beta');
  });
}
