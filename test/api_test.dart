import 'dart:convert';

import 'package:ajo/api.dart';
import 'package:ajo/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> serverGroup({String name = 'Office ajo', String updatedAt = '2026-11-24T10:00:00.000Z', Object paid = const {'0': ['a']}}) => {
      'id': 'g1',
      'name': name,
      'amount': 20000,
      'frequency': 'monthly',
      'start': '2026-01-31T00:00:00.000',
      'members': [
        {'id': 'a', 'name': 'Ade', 'phone': ''},
        {'id': 'b', 'name': 'Bisi', 'phone': ''},
      ],
      'paid': paid,
      'collected': [0],
      'updatedAt': updatedAt,
    };

void main() {
  test('login sends JSON and returns the session', () async {
    late http.Request sent;
    final api = AjoApi(
      baseUrl: 'https://ajo.test/api/',
      client: MockClient((req) async {
        sent = req;
        return http.Response(jsonEncode({'token': 't0k', 'user': {'id': 1, 'name': 'Ada', 'email': 'ada@x.com'}}), 200);
      }),
    );

    final session = await api.login('ada@x.com', 'secret123');

    expect(sent.url.toString(), 'https://ajo.test/api/login'); // trailing slash handled
    expect(sent.headers['Accept'], 'application/json');
    expect(jsonDecode(sent.body), {'email': 'ada@x.com', 'password': 'secret123', 'device_name': 'ajo-app'});
    expect(session.token, 't0k');
    expect(session.name, 'Ada');
  });

  test('validation errors come back as a readable message', () async {
    final api = AjoApi(
      baseUrl: 'https://ajo.test/api',
      client: MockClient((_) async => http.Response(
            jsonEncode({'message': 'invalid', 'errors': {'email': ['That email and password don’t match an account.']}}),
            422,
            headers: {'content-type': 'application/json; charset=utf-8'},
          )),
    );

    expect(
      () => api.login('ada@x.com', 'nope'),
      throwsA(isA<AjoApiException>()
          .having((e) => e.status, 'status', 422)
          .having((e) => e.message, 'message', 'That email and password don’t match an account.')),
    );
  });

  test('signed-in calls send the token', () async {
    late http.Request sent;
    final api = AjoApi(
      baseUrl: 'https://ajo.test/api',
      token: 'abc',
      client: MockClient((req) async {
        sent = req;
        return http.Response(jsonEncode([serverGroup()]), 200);
      }),
    );

    final groups = await api.listGroups();

    expect(sent.headers['Authorization'], 'Bearer abc');
    expect(groups.single.name, 'Office ajo');
    expect(groups.single.hasPaid(0, 'a'), isTrue);
    expect(groups.single.collected, {0});
    expect(groups.single.updatedAt, DateTime.utc(2026, 11, 24, 10));
  });

  test('an empty paid list from the server reads as no payments', () async {
    final api = AjoApi(baseUrl: 'https://ajo.test/api', client: MockClient((_) async => http.Response(jsonEncode([serverGroup(paid: [])]), 200)));
    expect((await api.listGroups()).single.paid, isEmpty);
  });

  test('saving a group: 201 is saved, 409 returns the newer server copy', () async {
    var status = 201;
    late Map<String, dynamic> body;
    final api = AjoApi(
      baseUrl: 'https://ajo.test/api',
      token: 'abc',
      client: MockClient((req) async {
        body = jsonDecode(req.body) as Map<String, dynamic>;
        expect(req.method, 'PUT');
        expect(req.url.path, '/api/groups/g1');
        return http.Response(jsonEncode(serverGroup(name: status == 409 ? 'Server name' : body['name'] as String)), status);
      }),
    );
    final local = AjoGroup.fromJson(serverGroup(name: 'Phone name'));

    final saved = await api.putGroup(local);
    expect(saved.conflict, isFalse);
    expect(body['members'], hasLength(2));

    status = 409;
    final conflict = await api.putGroup(local);
    expect(conflict.conflict, isTrue);
    expect(conflict.group.name, 'Server name');
  });

  test('names with Yoruba letters and ₦ survive a server reply without a charset', () async {
    final body = utf8.encode(jsonEncode([serverGroup(name: 'Ẹgbẹ́ Ọlá ₦')]));
    final api = AjoApi(
      baseUrl: 'https://ajo.test/api',
      client: MockClient((_) async => http.Response.bytes(body, 200, headers: {'content-type': 'application/json'})),
    );
    expect((await api.listGroups()).single.name, 'Ẹgbẹ́ Ọlá ₦');
  });

  test('deleting a group that is already gone is fine', () async {
    final api = AjoApi(baseUrl: 'https://ajo.test/api', token: 'abc', client: MockClient((_) async => http.Response('{"message":"Not found"}', 404)));
    await api.deleteGroup('gone');
  });
}
