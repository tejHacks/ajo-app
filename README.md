# Ajo

> Run your ajo without the notebook.

## What's built

- Create a group: contribution, weekly/monthly, first collection date, members in **payout order** (drag to reorder)
- Each cycle: **who collects**, the **pot**, a payment checklist, progress, and "mark pot handed over"
- Full schedule of every collection date; **share the ledger** as text to the group chat
- Tested cycle logic in `lib/models.dart` (month-end dates clamp to the 28th so no month is skipped)

## Next

- Payment reminders (local notifications), Paystack links for contributions, multiple rounds, export to PDF

## Run it

```bash
flutter pub get
flutter run            # pick an Android or iOS device
flutter test
flutter analyze
```

Built with Flutter 3.47 / Dart 3.13. Everything is stored on-device.
