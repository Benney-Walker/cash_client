# Cash Client

Flutter mobile app for credit union collectors (the Penco system). Collectors use it in the field to record members' daily susu deposits, create withdrawal requests and submit the day's collections to the office.

The app is a client of the `bankingbackend` Spring Boot API. It holds no business rules of its own; the backend enforces permissions and records every transaction.

## Status

| Area | State |
|---|---|
| Light and dark theme (Indigo Aurora palette, lighter gradient tints, Inter font) | Done |
| Redesign with the lighter tints (12 Nov 2026) | Sign-in done. Home, History and Settings next, each after you pick a design |
| Home screen layout and bottom bar (Home, History, Settings) | Done. Shows an empty day until the backend endpoints exist |
| Settings: theme choice (system / light / dark) and sign-out | Done |
| Sign-in (collectors only) and sign-out | Done. Tokens kept in secure storage |
| Automatic token refresh; back to sign-in when the backend ends the session | Done |
| One device per collector | Not started. Waiting on backend decision D36 |
| Member account lookup: name and accounts only (online and offline) | Not started. Needs a backend endpoint |
| Deposits and share payments (online and offline, with sync) | Not started. Needs the backend deposit endpoint |
| Corrections within 10 minutes | Not started. Needs backend support |
| Withdrawal requests | Not started. Needs backend support |
| Location tracking | Not started. Needs backend support |
| Transaction history | Screen in place, empty. Needs backend support |
| Daily cash submission and session ending | Not started. Needs backend support |

## Requirements

- Flutter SDK with Dart `^3.12.0` (see `pubspec.yaml`)
- Android SDK for device builds. Android package: `com.bynexlabs.cash_client`. Minimum Android 7.0 (API 24), required by `shared_preferences` (`flutter_secure_storage` needs 6.0)
- A running `bankingbackend`

## Run and test

```bash
flutter pub get
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8080
flutter test
flutter analyze
```

`API_BASE_URL` is the backend's address, set at build time. `10.0.2.2` is how the Android emulator reaches the computer it runs on; use the computer's LAN address for a real phone. Without it, sign-in shows a "no server address" message instead of calling anything.

Debug builds may use plain `http` so a local backend works. Release builds use Android's default, which allows only `https`.

`test/theme/app_theme_test.dart` checks every text/background colour pairing in both modes against WCAG AA (4.5:1), plus the input outline (3:1) and the 48dp touch target. If you change a colour and a test fails, the colour is the problem, not the test.

## Sign-in

The screen is design option 2, "glass card": the pale gradient wash fills the screen, with the shield-and-lock picture, "Cash Client" and "Daily collections" at the top, the form in a frosted glass card with the gradient **Sign in** button and the "Collectors only" and "Protected" labels, and "Version … · Powered by Bynex Labs" in the bottom-right corner. The version is read from the installed app with `package_info_plus` (`lib/settings/app_info.dart`).

On the glass card all text uses the panel's main text colour, and in dark mode field error messages do too. The lighter secondary tone and the error reds fall below 4.5:1 on dark-mode glass where it crosses the teal glow; the field's red border still marks an error. Field labels stay inside the fields rather than floating up onto the glass.

- Calls `POST /api/auth/v1/login` with `staffId` and `password`. The backend returns `staffName`, `roles`, `authToken` and `refreshToken`; a wrong ID or password, or an inactive account, returns 401.
- The backend signs in any staff role, so the app checks for `COLLECTOR`. Anyone else sees a message pointing them to the desktop app, and their tokens are discarded, not stored. The backend still enforces permissions on every endpoint.
- The session (tokens, staff ID, name, roles) is stored with `flutter_secure_storage`, backed by the Android Keystore. The password is never stored. App backup is turned off so tokens never leave the phone.
- On launch, a stored session skips sign-in, so a collector stays signed in until they sign out or the backend ends the session.
- Signing out only forgets the tokens on the phone; the backend has no logout endpoint yet. The tokens stay valid until they expire. Their lifetimes are set by the backend's `JWT_ACCESS_EXPIRATION` and `JWT_REFRESH_EXPIRATION`.

Code: `lib/auth/` (`auth_api.dart`, `session_manager.dart`, `session_store.dart`, `login_screen.dart`, and the sign-in messages in `sign_in.dart`), the error mapping in `lib/api/api_exception.dart`, and the sign-in/home switch in `lib/main.dart`.

## Token refresh

Calls to protected endpoints go through `AuthenticatedClient` (`lib/api/authenticated_client.dart`). Future features use it instead of a plain `http.Client`.

- It adds `Authorization: Bearer <access token>` to every request.
- On a 401 it calls `POST /api/auth/v1/refresh-token`, saves the new access token and replays the request once, body included. Requests that hit a 401 at the same moment share one refresh call.
- The backend doesn't issue a new refresh token, so when the refresh token expires (or the collector is deactivated) the refresh gets a 401. The session then ends: the tokens are cleared and the app returns to sign-in with "Your session has ended." The same path will handle the backend ending the session after the day's submission is approved.
- If the refresh can't reach the server, the session is kept, so a collector isn't signed out for being offline.
- A 403 is passed straight through. It means the role isn't allowed, and a new token wouldn't change that.
- Multipart and streamed requests can't be replayed: on a 401 they still trigger a refresh, but the caller gets the 401 and has to retry.

## Home screen

After sign-in, a bottom bar switches between Home, History and Settings (`lib/home/home_shell.dart`). The tabs stay alive, so switching keeps each tab's scroll position.

Home (`lib/home/home_screen.dart`), design A as approved:

- A greeting for the time of day and the collector's name, shown in normal case (the backend sends it in upper case).
- Today's collections on the hero gradient: total, number of records and, later, how many are waiting to send.
- **Record deposit** and **Withdrawal** side by side, with **Submit today's collections** full width beneath them.
- **Recent** records, with **See all** opening the History tab.

None of this has backend data yet. Today's total shows GH₵ 0.00 and the recent list shows "No collections recorded today". The three action buttons stay enabled and show a short message saying the feature isn't available yet, rather than being greyed out with no reason. History (`lib/home/history_screen.dart`) shows an empty state.

If the session ends while a screen is open on top of the tabs (such as the future deposit screens), the app closes it and goes back to sign-in.

## Settings

The Settings tab (`lib/settings/`):

- **Appearance:** System (follow the phone, the default), Light or Dark. The change applies straight away and is saved on the phone with `shared_preferences`, then read before the first frame at launch so the app doesn't flash the wrong theme. It's a phone setting, not tied to the collector, so it stays after sign-out.
- **Account:** the signed-in collector's name and staff ID, and **Sign out**.

## Theme

Code lives in `lib/theme/`:

- `app_colors.dart`: the raw palette. Widgets shouldn't use it directly.
- `app_theme.dart`: `AppTheme.light` and `AppTheme.dark`, plus button, card and input styling.
- `app_status_colors.dart`: `AppStatusColors.of(context)` for status colours and the hero gradient, which have no place in Material's `ColorScheme`.
- `app_gradients.dart`: `AppGradients.of(context)` for the lighter gradient tints shared with the desktop app (12 Nov 2026): the pale wash and its glows, the illustration gradient, glass fill and border, page glows, and the primary button gradient. The values in `app_colors.dart` are an identical copy of the desktop app's; change both or neither.

Shared pieces built on them, in `lib/common/`: `GradientButton` (every primary button), `GradientWash` (the pale wash with glows) and `GlassLabel` (frosted pill).

Font: Inter, bundled in `assets/fonts/inter/` (licence in `OFL.txt` there), so the app matches the desktop app on every phone.

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
- Every primary button uses the gradient (`GradientButton`), as in the desktop app. Other gradients are only for hero surfaces such as the sign-in wash and today's collections card. Inputs and chips are solid.
- Amounts are neutral, not green or red: GH₵ with 2 decimals and tabular figures.
- One primary button per screen.
- A deposit shows success only after the backend confirms it.
- Anything tappable is at least 48dp.
