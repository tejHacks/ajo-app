import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';
import 'sync.dart';

/// All groups. The phone's copy is always saved first, so the app works fully
/// offline. When [sync] is set and the user is signed in, every change is also
/// queued for the server and sent as soon as it can be.
class AjoStore extends ChangeNotifier {
  AjoStore({this.sync, DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  static const _key = 'ajo-groups';
  final SyncService? sync;
  final DateTime Function() _clock;

  List<AjoGroup> groups = [];
  bool ready = false;

  Future<void>? _running;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null) {
      groups = (jsonDecode(raw) as List).cast<Map<String, dynamic>>().map(AjoGroup.fromJson).toList();
    }
    ready = true;
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(groups.map((g) => g.toJson()).toList()));
  }

  AjoGroup? byId(String id) => groups.where((g) => g.id == id).firstOrNull;

  void _put(AjoGroup g) {
    final i = groups.indexWhere((x) => x.id == g.id);
    i >= 0 ? groups[i] = g : groups.add(g);
  }

  Future<void> upsert(AjoGroup g) async {
    _put(g.touched(_clock()));
    notifyListeners();
    await _save();
    if (sync?.signedIn ?? false) {
      sync!.markChanged(g.id);
      await sync!.save();
      unawaited(syncNow(pull: false));
    }
  }

  Future<void> remove(String id) async {
    groups.removeWhere((g) => g.id == id);
    notifyListeners();
    await _save();
    if (sync?.signedIn ?? false) {
      sync!.markDeleted(id);
      await sync!.save();
      unawaited(syncNow(pull: false));
    }
  }

  /// Send queued changes, and (with [pull]) fetch the server's groups and merge them:
  /// for each group the newer copy wins. If a sync is already running, this waits for
  /// it and then runs again, so every change made before the call is included.
  /// Network errors leave the queue for next time.
  Future<void> syncNow({bool pull = true}) async {
    while (_running != null) {
      await _running;
    }
    final run = _sync(pull);
    _running = run;
    try {
      await run;
    } finally {
      _running = null;
    }
  }

  Future<void> _sync(bool pull) async {
    final s = sync;
    if (s == null || !s.signedIn) return;
    s.begin();
    try {
      final api = s.api();

      for (final id in s.pendingDelete.toList()) {
        await api.deleteGroup(id);
        s.pendingDelete.remove(id);
      }

      if (pull) {
        final remote = await api.listGroups();
        final remoteIds = <String>{};
        for (final r in remote) {
          remoteIds.add(r.id);
          if (s.pendingDelete.contains(r.id)) continue;
          final local = byId(r.id);
          if (local == null || r.isNewerThan(local)) {
            _put(r);
            s.pendingPush.remove(r.id);
          } else if (local.isNewerThan(r)) {
            s.pendingPush.add(r.id);
          }
        }
        // Groups made before signing in, or while offline, go up too.
        for (final g in groups) {
          if (!remoteIds.contains(g.id)) s.pendingPush.add(g.id);
        }
      }

      for (final id in s.pendingPush.toList()) {
        final local = byId(id);
        if (local == null) {
          s.pendingPush.remove(id);
          continue;
        }
        final result = await api.putGroup(local);
        // Whether ours was saved or the server kept a newer copy, the server's copy is
        // now the truth, unless the user changed the group again while we were sending.
        final current = byId(id);
        if (current == null || !current.isNewerThan(local)) {
          _put(result.group);
          s.pendingPush.remove(id);
        }
      }

      s.finish();
    } catch (e) {
      s.finish(error: e);
    } finally {
      notifyListeners();
      await _save();
      await s.save();
    }
  }
}
