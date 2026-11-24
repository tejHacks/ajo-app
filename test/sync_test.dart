import 'dart:io';

import 'package:ajo/api.dart';
import 'package:ajo/models.dart';
import 'package:ajo/store.dart';
import 'package:ajo/sync.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// An in-memory Ajo API that can be switched offline.
class FakeServer {
  final Map<String, AjoGroup> groups = {};
  bool online = true;
  int puts = 0;

  void _net() {
    if (!online) throw const SocketException('offline');
  }
}

class FakeApi extends AjoApi {
  FakeApi(this.server) : super(baseUrl: 'https://ajo.test/api', token: 't');
  final FakeServer server;

  @override
  Future<List<AjoGroup>> listGroups() async {
    server._net();
    return server.groups.values.toList();
  }

  @override
  Future<SaveResult> putGroup(AjoGroup group) async {
    server._net();
    server.puts++;
    final existing = server.groups[group.id];
    if (existing != null && existing.isNewerThan(group)) return SaveResult(existing, conflict: true);
    server.groups[group.id] = group;
    return SaveResult(group, conflict: false);
  }

  @override
  Future<void> deleteGroup(String id) async {
    server._net();
    server.groups.remove(id);
  }
}

AjoGroup g(String id, {String name = 'Office ajo', DateTime? at}) => AjoGroup(
      id: id,
      name: name,
      amount: 20000,
      frequency: Frequency.monthly,
      start: DateTime(2026, 1, 31),
      members: [Member(id: 'a', name: 'Ade'), Member(id: 'b', name: 'Bisi')],
      updatedAt: at,
    );

Future<(AjoStore, SyncService, FakeServer)> setup({bool signedIn = true, DateTime? now}) async {
  SharedPreferences.setMockInitialValues({});
  final server = FakeServer();
  final sync = SyncService(apiFactory: (_, _) => FakeApi(server));
  if (signedIn) sync.session = const Session(token: 't', name: 'Ada', email: 'ada@x.com');
  final store = AjoStore(sync: sync, clock: () => now ?? DateTime.utc(2026, 11, 24, 12));
  await store.load();
  return (store, sync, server);
}

void main() {
  test('without an account nothing is queued or sent', () async {
    final (store, sync, server) = await setup(signedIn: false);
    await store.upsert(g('g1'));
    await store.syncNow();
    expect(sync.pendingCount, 0);
    expect(server.puts, 0);
    expect(store.groups.single.updatedAt, isNotNull); // still stamped for later
  });

  test('when signed in, a change reaches the server', () async {
    final (store, sync, server) = await setup();
    await store.upsert(g('g1'));
    await store.syncNow();
    expect(server.groups.keys, ['g1']);
    expect(sync.pendingCount, 0);
    expect(sync.lastError, isNull);
  });

  test('offline changes wait in the queue and go up when back online', () async {
    final (store, sync, server) = await setup();
    server.online = false;

    await store.upsert(g('g1'));
    await store.syncNow();
    expect(sync.pendingPush, {'g1'});
    expect(sync.lastError, contains('Offline'));
    expect(server.groups, isEmpty);

    server.online = true;
    await store.syncNow();
    expect(sync.pendingCount, 0);
    expect(server.groups.keys, ['g1']);
  });

  test('the queue survives an app restart', () async {
    final (store, sync, server) = await setup();
    server.online = false;
    await store.upsert(g('g1'));
    await store.syncNow();

    final again = SyncService(apiFactory: (_, _) => FakeApi(server));
    await again.load();
    expect(again.pendingPush, {'g1'});
    expect(again.session?.email, 'ada@x.com');
  });

  test('a deletion made offline reaches the server later', () async {
    final (store, sync, server) = await setup();
    await store.upsert(g('g1'));
    await store.syncNow();

    server.online = false;
    await store.remove('g1');
    await store.syncNow();
    expect(sync.pendingDelete, {'g1'});

    server.online = true;
    await store.syncNow();
    expect(server.groups, isEmpty);
    expect(store.groups, isEmpty);
  });

  test('pulling: the newer copy of each group wins, and phone-only groups go up', () async {
    final (store, sync, server) = await setup();
    // On the phone: g1 (older than the server's), g2 (newer), g3 (never synced).
    store.groups = [
      g('g1', name: 'Phone g1', at: DateTime.utc(2026, 11, 1)),
      g('g2', name: 'Phone g2', at: DateTime.utc(2026, 11, 20)),
      g('g3', name: 'Phone only', at: DateTime.utc(2026, 11, 20)),
    ];
    server.groups['g1'] = g('g1', name: 'Server g1', at: DateTime.utc(2026, 11, 10));
    server.groups['g2'] = g('g2', name: 'Server g2', at: DateTime.utc(2026, 11, 10));
    server.groups['g4'] = g('g4', name: 'From another phone', at: DateTime.utc(2026, 11, 10));

    await store.syncNow();

    expect(store.byId('g1')!.name, 'Server g1');
    expect(store.byId('g4')!.name, 'From another phone');
    expect(server.groups['g2']!.name, 'Phone g2');
    expect(server.groups['g3']!.name, 'Phone only');
    expect(sync.pendingCount, 0);
  });

  test('if the server already has a newer copy, the phone takes it', () async {
    final (store, sync, server) = await setup(now: DateTime.utc(2026, 11, 1));
    server.groups['g1'] = g('g1', name: 'Changed elsewhere', at: DateTime.utc(2026, 11, 20));

    await store.upsert(g('g1', name: 'Old phone edit'));
    await store.syncNow(pull: false);

    expect(store.byId('g1')!.name, 'Changed elsewhere');
    expect(sync.pendingCount, 0);
  });

  test('signing out keeps the groups on the phone', () async {
    final (store, sync, _) = await setup();
    await store.upsert(g('g1'));
    await sync.signOut();
    expect(sync.signedIn, isFalse);
    expect(store.groups, hasLength(1));
  });

  test('a group saved before updatedAt existed still loads', () {
    final old = g('g1').toJson()..remove('updatedAt');
    final loaded = AjoGroup.fromJson(old);
    expect(loaded.updatedAt, isNull);
    expect(g('g2', at: DateTime.utc(2026)).isNewerThan(loaded), isTrue);
    expect(loaded.isNewerThan(g('g2', at: DateTime.utc(2026))), isFalse);
  });
}
