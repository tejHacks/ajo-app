import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'models.dart';

/// All groups, persisted on-device. Notifies listeners on every change.
class AjoStore extends ChangeNotifier {
  static const _key = 'ajo-groups';
  List<AjoGroup> groups = [];
  bool ready = false;

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

  Future<void> upsert(AjoGroup g) async {
    final i = groups.indexWhere((x) => x.id == g.id);
    i >= 0 ? groups[i] = g : groups.add(g);
    notifyListeners();
    await _save();
  }

  Future<void> remove(String id) async {
    groups.removeWhere((g) => g.id == id);
    notifyListeners();
    await _save();
  }
}
