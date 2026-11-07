# Cash Client

Flutter mobile app for credit union collectors (the Penco system). Collectors use it in the field to record members' daily susu deposits, create withdrawal requests and submit the day's collections to the office.

The app is a client of the `bankingbackend` Spring Boot API. It holds no business rules of its own; the backend enforces permissions and records every transaction.

## Status

| Area | State |
|---|---|
| Light and dark theme (Indigo Aurora palette) | Done. Follows the phone's light/dark setting |
| In-app theme choice (system / light / dark) | Planned with the settings screen |
| Sign-in, token refresh, single device | Not started |
| Member account lookup: name and accounts only (online and offline) | Not started. Needs a backend endpoint |
| Deposits and share payments (online and offline, with sync) | Not started. Needs the backend deposit endpoint |
| Corrections within 10 minutes | Not started. Needs backend support |
| Withdrawal requests | Not started. Needs backend support |
| Location tracking | Not started. Needs backend support |
| Transaction history | Not started |
| Daily cash submission and session ending | Not started. Needs backend support |

## Requirements

- Flutter SDK with Dart `^3.12.0` (see `pubspec.yaml`)
- Android SDK for device builds. Android package: `com.bynexlabs.cash_client`

## Run and test

```bash
flutter pub get
flutter run
flutter test
flutter analyze
```

`test/theme/app_theme_test.dart` checks every text/background colour pairing in both modes against WCAG AA (4.5:1), plus the input outline (3:1) and the 48dp touch target. If you change a colour and a test fails, the colour is the problem, not the test.

## Theme

Code lives in `lib/theme/`:

- `app_colors.dart`: the raw palette. Widgets shouldn't use it directly.
- `app_theme.dart`: `AppTheme.light` and `AppTheme.dark`, plus button, card and input styling.
- `app_status_colors.dart`: `AppStatusColors.of(context)` for status colours and the hero gradient, which have no place in Material's `ColorScheme`.

Surface roles, used the same way in both modes:

| Role | Use |
|---|---|
| `colorScheme.surface` | Page background |
| `colorScheme.surfaceContainerLow` | Cards |
| `colorScheme.surfaceContainerHigh` | Raised areas such as bottom sheets |
| `colorScheme.outlineVariant` | Hairline borders |
| `colorScheme.onSurfaceVariant` | Secondary text |

Status colours map to the backend's `TransactionStatus` and the app's sync state:

| Status | Colour |
|---|---|
| COMPLETED, SMS sent | `success` |
| PENDING, not yet synced | `warning` |
| FAILED, rejected | `danger` |
| REVERSED, inactive | `neutral` |

Design rules:

- Green means success only. It's never used as a brand colour.
- A status always shows an icon and a label, not colour alone.
- The hero gradient is only for hero surfaces (today's collections card, login header, receipt banner). Buttons, inputs and chips are solid.
- Amounts are neutral, not green or red: GH₵ with 2 decimals and tabular figures.
- One primary (filled) button per screen.
- A deposit shows success only after the backend confirms it.
- Anything tappable is at least 48dp.
