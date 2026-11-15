# Cash Client

Flutter mobile app for credit union collectors (the Penco system). Collectors use it in the field to record members' daily susu deposits, create withdrawal requests and submit the day's collections to the office.

The app is a client of the `bankingbackend` Spring Boot API. It holds no business rules of its own; the backend enforces permissions and records every transaction.

## Status

| Area | State |
|---|---|
| Light and dark theme (Indigo Aurora palette, lighter gradient tints, Inter font) | Done |
| Redesign with the lighter tints (12 Nov 2026) | Done for every screen: sign-in, Home, History and Settings |
| Home screen layout and bottom bar (Home, History, Settings) | Done. Record deposit works; today's totals and recent list not connected yet |
| Settings: profile, theme choice (system / light / dark), app version and sign-out | Done |
| Sign-in (collectors only) and sign-out | Done. Tokens kept in secure storage |
| Automatic token refresh; back to sign-in when the backend ends the session | Done |
| One device per collector | Not started. Waiting on backend decision D36 |
| Member lookup: branch members' names and savings/shares accounts, saved for offline | Done (backend PR #14) |
| Savings deposits and share purchases | Online recording done (backend PR #14). Offline queue and sync not started |
| Corrections within 10 minutes | Not started (backend ready in PR #14). The saved screen counts the window down |
| Withdrawal requests | Not started (backend ready in PR #14) |
| Location tracking | Not started. Needs backend support |
| Transaction history | Screen in place, empty. Backend day summary in PR #14 |
| Daily cash submission and session ending | Not started. Needs backend support |

## Requirements

- Flutter SDK with Dart `^3.12.0` (see `pubspec.yaml`)
- Android SDK for device builds. Android package: `com.bynexlabs.cash_client`. Minimum Android 7.0 (API 24), required by `shared_preferences` (`flutter_secure_storage` needs 6.0)
- A running `bankingbackend`. Recording payments needs the collector endpoints from backend PR #14, merged with master from 14 Nov 2026 or later (the JWT filter fix for loading staff roles)

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

- Calls `POST /api/auth/v1/collector-login` with `staffId` and `password` (collectors have their own sign-in endpoint since 14 Nov 2026; the desktop app uses `staff-login`, which refuses collectors). The backend returns `staffName`, `roles`, `authToken` and `refreshToken`. A wrong ID or password, or an inactive account, returns 401; a valid account that isn't a collector returns 403.
- A 403, or a response without the `COLLECTOR` role, shows a message pointing the person to the desktop app, and any tokens are discarded, not stored. The backend still enforces permissions on every endpoint.
- The session (tokens, staff ID, name, roles) is stored with `flutter_secure_storage`, backed by the Android Keystore. The password is never stored. App backup is turned off so tokens never leave the phone.
- On launch, a stored session skips sign-in, so a collector stays signed in until they sign out or the backend ends the session.
- Signing out only forgets the tokens on the phone; the backend has no logout endpoint yet. The tokens stay valid until they expire. Their lifetimes are set by the backend's `JWT_ACCESS_EXPIRATION` and `JWT_REFRESH_EXPIRATION`.

- Password reset: the backend has a three-step reset (`/api/auth/v1/password-reset/request-code`, `confirm-code`, `new-password`), but it isn't in the collector app for now (owner decision, 13 Nov 2026).

Code: `lib/auth/` (`auth_api.dart`, `session_manager.dart`, `session_store.dart`, `login_screen.dart`, and the sign-in messages in `sign_in.dart`), the error mapping in `lib/api/api_exception.dart`, and the sign-in/home switch in `lib/main.dart`.

## Token refresh

Calls to protected endpoints go through `AuthenticatedClient` (`lib/api/authenticated_client.dart`). Future features use it instead of a plain `http.Client`.

- It adds `Authorization: Bearer <access token>` to every request.
- On a 401 it calls `POST /api/auth/v1/refresh-collector-token` with `{"refreshToken": …}`, saves the new access token and replays the request once, body included. That endpoint accepts only collector refresh tokens. Requests that hit a 401 at the same moment share one refresh call.
- The refresh endpoint answers with the new access token as the bare response body, not a JSON object (backend contract checked 14 Nov 2026 on `bankingbackend` master). A token in quotes is also accepted. The body must have the shape of the backend's signed JWTs (three dot-separated parts); anything else, such as a proxy error page, is treated as an unexpected response rather than saved as a token.
- The backend doesn't issue a new refresh token, so when the refresh token expires (or the collector is deactivated) the refresh gets a 401. The session then ends: the tokens are cleared and the app returns to sign-in with "Your session has ended." The same path will handle the backend ending the session after the day's submission is approved.
- If the refresh can't reach the server, the session is kept, so a collector isn't signed out for being offline.
- A 403 is passed straight through. It means the role isn't allowed, and a new token wouldn't change that.
- Multipart and streamed requests can't be replayed: on a 401 they still trigger a refresh, but the caller gets the 401 and has to retry.

## Home screen

After sign-in, a bottom bar switches between Home, History and Settings (`lib/home/home_shell.dart`). The tabs stay alive, so switching keeps each tab's scroll position.

Home (`lib/home/home_screen.dart`) keeps design A's layout, restyled as design H1, "wash header" (12 Nov 2026):

- The pale gradient wash across the top, running under the status bar, with rounded bottom corners. On it: a greeting for the time of day and the collector's name, shown in normal case (the backend sends it in upper case).
- Today's collections on a glass card inside the wash: total, number of records and, later, how many are waiting to send. All text on the glass uses the panel's main text colour, as on sign-in.
- On the plain page below: **Record deposit** (the screen's one gradient button) and **Withdrawal** side by side, with **Submit today's collections** full width beneath them.
- **Recent** records, with **See all** opening the History tab.

**Record deposit** opens the payment flow (below). Today's total and the recent list aren't connected yet: they show GH₵ 0.00 and "No collections recorded today". Withdrawal and Submit stay enabled and show a short message saying the feature isn't available yet, rather than being greyed out with no reason.

History (`lib/home/history_screen.dart`), design Y1, "wash header" (12 Nov 2026):

- The same wash header as home (`lib/common/wash_header.dart`), with the title and today's record count and total on a glass strip.
- Filter chips on the plain page: All, Deposits, Shares, Withdrawals. The selected chip uses the soft indigo pill (set in the theme's `chipTheme`).
- Until the backend can list a collector's records, the count and total show zero and the list shows an empty state that names the selected filter ("No share payments yet"). Which record types each filter matches will follow the backend's transaction types.

If the session ends while a screen is open on top of the tabs (such as the payment screens), the app closes it and goes back to sign-in.

## Recording a payment

Design P1, "two screens" (15 Nov 2026), in `lib/collector/`. Collectors record two kinds of payment, matching the backend's `CollectorPaymentType`: a **savings deposit** (into the member's savings account) and a **share purchase** (into their shares account).

1. **Choose member** (`member_picker_screen.dart`). The branch member list from `GET /api/collector/v1/members`: names and savings/shares account numbers only, never other member details. Search by name or account number. When two members share a name, their account numbers show so they can be told apart.
2. **Record payment** (`record_payment_screen.dart`). Savings or Shares (only the types the member has an account for), the account number, the amount in GH₵ and an optional note (up to 500 characters). Amounts are cedis and pesewas, 2 decimal places (owner decision, 15 Nov 2026), up to GH₵ 999,999,999.99.
3. **Confirm payment** (`confirm_payment_screen.dart`). Member, account and amount are checked before anything is sent; only this screen sends the payment. Edit goes back.
4. **Payment saved** (`payment_saved_screen.dart`). Shown once the backend has saved it. The payment is **Pending** for its 10-minute correction window, counted down from the window length the server sent (on the phone's monotonic clock, so a wrong phone clock can't change it); the member's balance and SMS follow when it closes. Done (or back) goes home, never to the confirm screen.

Sending (`collector_api.dart`):

- `POST /api/collector/v1/payments` with `idempotencyKey`, `type` (SAVINGS or SHARES), `accountNumber`, `amount` and optional `description`, through the authenticated client.
- The amount is held as whole pesewas (`lib/common/money.dart`) and written into the JSON as an exact decimal literal such as `50.50`, so it reaches the backend's `BigDecimal` without passing through a floating-point number.
- Each payment gets a random UUID idempotency key when the confirm screen opens. If the connection drops, the collector is told the app couldn't confirm the payment was saved and to tap Record payment again: the retry sends the same key, so the backend never records it twice.
- The backend's own messages for refused payments are shown as they are, for example "This member's first deposit must be made at the office" (409), "This member isn't in your branch" (403), or an account that isn't active (409).

Member list on the phone (`member_cache.dart`, `member_directory.dart`):

- Saved in SQLite through `sqflite` (owner decision, 15 Nov 2026), in `cash_client.db`: tables `members`, `member_accounts` and `sync_meta` (when the list was downloaded). Each download replaces the whole list in one transaction.
- The picker shows the saved list straight away and downloads a fresh one in the background. Offline, the saved list still works, with a notice saying when it was saved; with nothing saved, it offers Try again.
- The list is cleared when the collector signs out or the session ends.
- The SQLite code itself isn't covered by tests (that needs a native SQLite library on the test machine); the logic around it is tested with an in-memory cache.

Not in this step: recording offline and syncing later, corrections within the 10 minutes, and connecting home's totals and the History tab to the backend.

## Settings

The Settings tab (`lib/settings/`), design S1, "profile header" (12 Nov 2026):

- **Profile:** the same wash header as home and history, with the collector's initials (on the button gradient, like the desktop app's "CC" mark), name and "Staff ID … · Collector" on a glass card.
- **Appearance:** System (follow the phone, the default), Light or Dark. The change applies straight away and is saved on the phone with `shared_preferences`, then read before the first frame at launch so the app doesn't flash the wrong theme. It's a phone setting, not tied to the collector, so it stays after sign-out.
- **About:** the installed app version, read with `package_info_plus` (the same value as the sign-in screen's corner).
- **Sign out**, outlined. The screen has no primary action, so no gradient button.

## Theme

Code lives in `lib/theme/`:

- `app_colors.dart`: the raw palette. Widgets shouldn't use it directly.
- `app_theme.dart`: `AppTheme.light` and `AppTheme.dark`, plus button, card and input styling.
- `app_status_colors.dart`: `AppStatusColors.of(context)` for status colours and the hero gradient, which have no place in Material's `ColorScheme`.
- `app_gradients.dart`: `AppGradients.of(context)` for the lighter gradient tints shared with the desktop app (12 Nov 2026): the pale wash and its glows, the illustration gradient, glass fill and border, page glows, and the primary button gradient. The values in `app_colors.dart` are an identical copy of the desktop app's; change both or neither.

Shared pieces built on them, in `lib/common/`: `GradientButton` (every primary button; it also takes a `padding` override, the one difference from the desktop app's copy), `GradientWash` (the pale wash with glows, full-screen or as a header), `GlassCard` (frosted card) and `GlassLabel` (frosted pill). The older deep hero gradient in `AppStatusColors` is no longer used on any screen; it's kept for now in case a later screen, such as a receipt, wants it.

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
- Every primary button uses the gradient (`GradientButton`), as in the desktop app. Other gradients are only for hero surfaces such as the sign-in wash and the home header. Inputs and chips are solid.
- Amounts are neutral, not green or red: GH₵ with 2 decimals and tabular figures.
- One primary button per screen.
- A deposit shows success only after the backend confirms it.
- Anything tappable is at least 48dp.
