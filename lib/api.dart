import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

import 'package:http/http.dart' as http;

import 'models.dart';

/// The server address. Set at build time with `--dart-define=AJO_API_URL=https://…/api`,
/// or in the app under Account & sync. Without either, it points at a local
/// `php artisan serve` on this computer: 10.0.2.2 from the Android emulator,
/// 127.0.0.1 from the iOS simulator.
const _envApiUrl = String.fromEnvironment('AJO_API_URL');

String get defaultApiUrl {
  if (_envApiUrl.isNotEmpty) return _envApiUrl;
  if (!kIsWeb && Platform.isAndroid) return 'http://10.0.2.2:8000/api';
  return 'http://127.0.0.1:8000/api';
}

/// The signed-in account.
class Session {
  const Session({required this.token, required this.name, required this.email});
  final String token;
  final String name;
  final String email;

  Map<String, dynamic> toJson() => {'token': token, 'name': name, 'email': email};
  factory Session.fromJson(Map<String, dynamic> j) =>
      Session(token: j['token'] as String, name: j['name'] as String, email: j['email'] as String);
}

/// The server said no (validation, auth or another HTTP error).
class AjoApiException implements Exception {
  AjoApiException(this.status, this.message);
  final int status;
  final String message;
  @override
  String toString() => message;
}

/// Result of saving a group: the server's copy, and whether the server kept a newer
/// version instead of ours (HTTP 409).
class SaveResult {
  const SaveResult(this.group, {required this.conflict});
  final AjoGroup group;
  final bool conflict;
}

/// Talks to the Ajo API (Laravel + Sanctum).
class AjoApi {
  AjoApi({required this.baseUrl, this.token, http.Client? client}) : _client = client ?? http.Client();

  final String baseUrl;
  final String? token;
  final http.Client _client;
  static const _timeout = Duration(seconds: 15);

  Uri _uri(String path) => Uri.parse('${baseUrl.replaceAll(RegExp(r'/+$'), '')}$path');

  Map<String, String> get _headers => {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Future<Session> register(String name, String email, String password) =>
      _session('/register', {'name': name, 'email': email, 'password': password, 'device_name': 'ajo-app'});

  Future<Session> login(String email, String password) =>
      _session('/login', {'email': email, 'password': password, 'device_name': 'ajo-app'});

  Future<void> logout() async {
    final res = await _client.post(_uri('/logout'), headers: _headers).timeout(_timeout);
    if (res.statusCode != 401) _check(res);
  }

  Future<List<AjoGroup>> listGroups() async {
    final res = await _client.get(_uri('/groups'), headers: _headers).timeout(_timeout);
    _check(res);
    return (_json(res) as List).cast<Map<String, dynamic>>().map(AjoGroup.fromJson).toList();
  }

  /// Create or replace a whole group. A 409 means the server has a newer copy,
  /// which comes back so the phone can keep it.
  Future<SaveResult> putGroup(AjoGroup group) async {
    final res = await _client
        .put(_uri('/groups/${Uri.encodeComponent(group.id)}'), headers: _headers, body: jsonEncode(group.toJson()))
        .timeout(_timeout);
    if (res.statusCode == 409) {
      return SaveResult(AjoGroup.fromJson(_json(res) as Map<String, dynamic>), conflict: true);
    }
    _check(res);
    return SaveResult(AjoGroup.fromJson(_json(res) as Map<String, dynamic>), conflict: false);
  }

  /// Delete a group. Already gone (404) counts as done.
  Future<void> deleteGroup(String id) async {
    final res = await _client.delete(_uri('/groups/${Uri.encodeComponent(id)}'), headers: _headers).timeout(_timeout);
    if (res.statusCode != 404) _check(res);
  }

  Future<Session> _session(String path, Map<String, String> body) async {
    final res = await _client.post(_uri(path), headers: _headers, body: jsonEncode(body)).timeout(_timeout);
    _check(res);
    final j = _json(res) as Map<String, dynamic>;
    final user = j['user'] as Map<String, dynamic>;
    return Session(token: j['token'] as String, name: user['name'] as String, email: user['email'] as String);
  }

  /// Laravel sends JSON without a charset, and package:http would then read it as
  /// Latin-1, garbling names like "Ọlá" and "₦". JSON is always UTF-8.
  static dynamic _json(http.Response res) => jsonDecode(utf8.decode(res.bodyBytes));

  void _check(http.Response res) {
    if (res.statusCode >= 200 && res.statusCode < 300) return;
    var message = 'The server returned ${res.statusCode}.';
    try {
      final j = _json(res) as Map<String, dynamic>;
      final errors = j['errors'];
      if (errors is Map && errors.isNotEmpty) {
        message = ((errors.values.first as List).first).toString();
      } else if (j['message'] is String && (j['message'] as String).isNotEmpty) {
        message = j['message'] as String;
      }
    } catch (_) {}
    throw AjoApiException(res.statusCode, message);
  }
}
