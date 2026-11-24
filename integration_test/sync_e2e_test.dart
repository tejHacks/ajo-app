// End-to-end: the real app on a simulator or emulator, syncing with a running Ajo API.
//
//   cd ../ajo-api && php artisan serve --host 0.0.0.0 --port 8000
//   flutter test integration_test/sync_e2e_test.dart -d <device>
//
// The API address defaults to the local server (127.0.0.1 on iOS, 10.0.2.2 on the
// Android emulator). Override with --dart-define=AJO_API_URL=https://…/api.
import 'package:ajo/api.dart';
import 'package:ajo/main.dart';
import 'package:ajo/models.dart';
import 'package:ajo/store.dart';
import 'package:ajo/sync.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a group made in the app reaches the API, and payments follow', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
    await prefs.setBool('onboarded', true);

    final sync = SyncService();
    await sync.load();
    final email = 'e2e-${DateTime.now().millisecondsSinceEpoch}@ajo.test';
    await sync.register('Simulator Organiser', email, 'secret123');
    expect(sync.signedIn, isTrue);

    final store = AjoStore(sync: sync);
    await store.load();
    await tester.pumpWidget(AjoApp(store: store));
    await tester.pumpAndSettle();

    // Make a group the way the app does, then let it sync.
    final group = AjoGroup(
      id: 'g-${DateTime.now().millisecondsSinceEpoch}',
      name: 'Ẹgbẹ́ Simulator ajo',
      amount: 10000,
      frequency: Frequency.monthly,
      start: DateTime(2026, 12, 1),
      members: [Member(id: 'a', name: 'Ade'), Member(id: 'b', name: 'Bisi'), Member(id: 'c', name: 'Chidi')],
    );
    await store.upsert(group);
    await store.syncNow();
    await tester.pumpAndSettle();

    expect(sync.pendingCount, 0, reason: sync.lastError ?? '');
    expect(find.text('Ẹgbẹ́ Simulator ajo'), findsOneWidget);
    expect(find.byTooltip('All changes synced'), findsOneWidget);

    final api = AjoApi(baseUrl: sync.baseUrl, token: sync.session!.token);
    var onServer = (await api.listGroups()).singleWhere((g) => g.id == group.id);
    expect(onServer.name, 'Ẹgbẹ́ Simulator ajo');
    expect(onServer.members.map((m) => m.name), ['Ade', 'Bisi', 'Chidi']);

    // Open the group and tick Ade's payment for this cycle on screen.
    await tester.tap(find.text('Ẹgbẹ́ Simulator ajo'));
    await tester.pumpAndSettle();
    await store.upsert(store.byId(group.id)!.togglePaid(0, 'a'));
    await store.syncNow();
    await tester.pumpAndSettle();

    onServer = (await api.listGroups()).singleWhere((g) => g.id == group.id);
    expect(onServer.hasPaid(0, 'a'), isTrue);
    expect(sync.pendingCount, 0);

    // The account screen shows the signed-in user.
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('All changes synced'));
    await tester.pumpAndSettle();
    expect(find.text('Simulator Organiser'), findsOneWidget);
    expect(find.text('All changes synced'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Sync now'), findsOneWidget);
  });
}
