# Ajo

> Run your ajo without the notebook.

## What's built

- Create a group: contribution, weekly/monthly, first collection date, members in **payout order** (drag to reorder)
- Each cycle: **who collects**, the **pot**, a payment checklist, progress, and "mark pot handed over"
- Full schedule of every collection date; **share the ledger** as text to the group chat
- Tested cycle logic in `lib/models.dart` (month-end dates clamp to the 28th so no month is skipped)
- **Backup and sync** (optional): sign in under the cloud icon to keep your groups on the [Ajo API](https://github.com/tejHacks/ajo-api) and use them on another phone

## Offline first, sync when you can

The phone's copy is always saved first, so Ajo works with no account and no internet. Signed in, every change is also queued for the server:

- Changes made offline wait in a queue that survives restarts, and go up when you're back online.
- Opening the app pulls the server's groups. For each group the newer copy wins (`updatedAt`), and groups made before signing in are uploaded.
- If the server already has a newer copy, it answers 409 and the phone keeps the server's version.
- Signing out keeps your groups on the phone.

The server address comes from `--dart-define=AJO_API_URL=https://your-server/api`, or can be changed in the app. By default it reaches a local `php artisan serve --host 0.0.0.0 --port 8000`: `10.0.2.2` from the Android emulator, `127.0.0.1` from the iOS simulator. Plain HTTP is allowed only for local addresses; every other server must use HTTPS.

### Test sync end to end

With the API running locally:

```bash
flutter test integration_test/sync_e2e_test.dart -d <simulator or emulator id>
```

It signs up, makes a group in the real app, syncs it, ticks a payment, and checks both on the server.

## Next

- Members joining a group from their own phones (invites), payment reminders, Paystack links for contributions, multiple rounds, export to PDF

## Run it

```bash
flutter pub get
flutter run            # pick an Android or iOS device
flutter test           # 27 tests: cycle logic, screens, API client and sync
flutter analyze
```

Built with Flutter 3.47 / Dart 3.13.
