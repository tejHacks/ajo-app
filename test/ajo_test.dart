import 'package:ajo/main.dart';
import 'package:ajo/models.dart';
import 'package:ajo/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

AjoGroup group({Frequency f = Frequency.monthly}) => AjoGroup(
      id: 'g1',
      name: 'Office ajo',
      amount: 20000,
      frequency: f,
      start: DateTime(2026, 1, 31),
      members: [Member(id: 'a', name: 'Ade'), Member(id: 'b', name: 'Bisi'), Member(id: 'c', name: 'Chidi')],
    );

void main() {
  group_tests();

  testWidgets('creates nothing and shows empty state on first launch', (tester) async {
    SharedPreferences.setMockInitialValues({'onboarded': true});
    final store = AjoStore();
    await store.load();
    await tester.pumpWidget(AjoApp(store: store));
    await tester.pumpAndSettle();
    expect(find.text('No groups yet'), findsOneWidget);
    expect(find.text('New group'), findsOneWidget);
  });

  testWidgets('group screen shows recipient, pot and payment progress', (tester) async {
    SharedPreferences.setMockInitialValues({'onboarded': true});
    final store = AjoStore();
    await store.load();
    await store.upsert(group().togglePaid(0, 'a'));
    await tester.pumpWidget(AjoApp(store: store));
    await tester.pumpAndSettle();
    expect(find.text('Office ajo'), findsOneWidget);
    await tester.tap(find.text('Office ajo'));
    await tester.pumpAndSettle();
    expect(find.textContaining('collects'), findsWidgets);
    expect(find.textContaining('₦60,000'), findsWidgets);
  });
}

// ignore: non_constant_identifier_names
void group_tests() {
  test('pot is amount × members, recipients rotate in order', () {
    final g = group();
    expect(g.pot, 60000);
    expect([0, 1, 2].map((c) => g.recipient(c).name), ['Ade', 'Bisi', 'Chidi']);
  });

  test('monthly due dates clamp to day 28 so short months never skip', () {
    final g = group();
    expect(g.dueDate(1), DateTime(2026, 2, 28));
    expect(g.dueDate(2), DateTime(2026, 3, 28));
  });

  test('weekly due dates step by 7 days', () {
    final g = group(f: Frequency.weekly);
    expect(g.dueDate(2), DateTime(2026, 2, 14));
  });

  test('current cycle follows the calendar and clamps to the round', () {
    final g = group(f: Frequency.weekly);
    expect(g.currentCycle(DateTime(2026, 1, 1)), -1);
    expect(g.currentCycle(DateTime(2026, 2, 1)), 0);
    expect(g.currentCycle(DateTime(2026, 2, 8)), 1);
    expect(g.currentCycle(DateTime(2027, 1, 1)), 2);
  });

  test('payments toggle, owing list and completion', () {
    var g = group();
    g = g.togglePaid(0, 'a').togglePaid(0, 'b');
    expect(g.paidCount(0), 2);
    expect(g.collectedSoFar(0), 40000);
    expect(g.owing(0).map((m) => m.name), ['Chidi']);
    g = g.togglePaid(0, 'c');
    expect(g.isComplete(0), isTrue);
    g = g.togglePaid(0, 'c');
    expect(g.isComplete(0), isFalse);
  });

  test('json round-trip keeps payments and collections', () {
    final g = group().togglePaid(1, 'b').toggleCollected(0);
    final back = AjoGroup.fromJson(g.toJson());
    expect(back.hasPaid(1, 'b'), isTrue);
    expect(back.collected, {0});
    expect(back.members.map((m) => m.name), ['Ade', 'Bisi', 'Chidi']);
  });
}
