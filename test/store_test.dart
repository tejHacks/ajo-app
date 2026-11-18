import 'package:ajo/models.dart';
import 'package:ajo/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('groups are saved on-device and survive a restart', () async {
    SharedPreferences.setMockInitialValues({});
    final a = AjoStore();
    await a.load();
    await a.upsert(AjoGroup(
      id: 'g1',
      name: 'Office ajo',
      amount: 20000,
      frequency: Frequency.weekly,
      start: DateTime(2026, 1, 5),
      members: [Member(id: 'a', name: 'Ade', phone: '')],
    ).togglePaid(0, 'a'));

    final b = AjoStore();
    await b.load();
    expect(b.byId('g1')?.name, 'Office ajo');
    expect(b.byId('g1')?.hasPaid(0, 'a'), isTrue);

    await b.remove('g1');
    final c = AjoStore();
    await c.load();
    expect(c.groups, isEmpty);
  });
}
