import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';

/// Builds an API client. Swapped for a fake in tests.
typedef ApiFactory = AjoApi Function(String baseUrl, String? token);

/// Account, server address and the queue of changes waiting to reach the server.
/// Everything is saved on the phone, so queued changes survive restarts.
class SyncService extends ChangeNotifier {
  SyncService({ApiFactory? apiFactory}) : _apiFactory = apiFactory ?? ((url, token) => AjoApi(baseUrl: url, token: token));

  static const _key = 'ajo-sync';
  final ApiFactory _apiFactory;

  String baseUrl = defaultApiUrl;
  Session? session;

  /// Groups changed on the phone that the server hasn't got yet.
  final Set<String> pendingPush = {};

  /// Groups deleted on the phone that still need deleting on the server.
  final Set<String> pendingDelete = {};

  DateTime? lastSynced;
  String? lastError;
  bool syncing = false;

  bool get signedIn => session != null;
  int get pendingCount => pendingPush.length + pendingDelete.length;

  AjoApi api() => _apiFactory(baseUrl, session?.token);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw != null) {
      final j = jsonDecode(raw) as Map<String, dynamic>;
      baseUrl = (j['baseUrl'] as String?) ?? defaultApiUrl;
      session = j['session'] == null ? null : Session.fromJson(j['session'] as Map<String, dynamic>);
      pendingPush.addAll((j['pendingPush'] as List? ?? []).cast<String>());
      pendingDelete.addAll((j['pendingDelete'] as List? ?? []).cast<String>());
      lastSynced = j['lastSynced'] == null ? null : DateTime.parse(j['lastSynced'] as String);
    }
    notifyListeners();
  }

  Future<void> save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _key,
      jsonEncode({
        'baseUrl': baseUrl,
        'session': session?.toJson(),
        'pendingPush': pendingPush.toList(),
        'pendingDelete': pendingDelete.toList(),
        'lastSynced': lastSynced?.toIso8601String(),
      }),
    );
  }

  Future<void> setBaseUrl(String url) async {
    baseUrl = url.trim().isEmpty ? defaultApiUrl : url.trim();
    notifyListeners();
    await save();
  }

  Future<void> signIn(String email, String password) async {
    session = await api().login(email.trim(), password);
    lastError = null;
    notifyListeners();
    await save();
  }

  Future<void> register(String name, String email, String password) async {
    session = await api().register(name.trim(), email.trim(), password);
    lastError = null;
    notifyListeners();
    await save();
  }

  /// Sign out on this phone. Groups stay on the phone; the server keeps its copy.
  Future<void> signOut() async {
    try {
      await api().logout();
    } catch (_) {
      // Offline: the token is dropped on the phone anyway.
    }
    session = null;
    pendingPush.clear();
    pendingDelete.clear();
    lastSynced = null;
    lastError = null;
    notifyListeners();
    await save();
  }

  void markChanged(String id) {
    pendingDelete.remove(id);
    pendingPush.add(id);
    notifyListeners();
  }

  void markDeleted(String id) {
    pendingPush.remove(id);
    pendingDelete.add(id);
    notifyListeners();
  }

  void begin() {
    syncing = true;
    notifyListeners();
  }

  void finish({Object? error}) {
    syncing = false;
    if (error == null) {
      lastSynced = DateTime.now();
      lastError = null;
    } else {
      lastError = error is AjoApiException ? error.message : 'Offline. Changes will sync when you’re back online.';
    }
    notifyListeners();
  }
}
