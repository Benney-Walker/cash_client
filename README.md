# Cash Client

Flutter mobile app for credit union collectors (the Penco system). Collectors use it in the field to record members' daily savings deposits and share purchases, and submit the day's collections to the office.

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
| Savings deposits and share purchases | Done online and offline, with sync in the background and the Outbox (backend PR #14) |
| Corrections within 10 minutes | Not started (backend ready in PR #14). The saved screen counts the window down |
| Withdrawal requests | Removed (owner decision, 15 Nov 2026). Members withdraw at a branch office |
| Location tracking | Not started. Needs backend support |
| Transaction history | Screen in place, empty. Backend day summary in PR #14 |
| Daily cash submission and session ending | Done (backend PR #14, decision D35). No rejection step: the approver records the cash counted |

## Requirements

- Flutter SDK with Dart `^3.12.0` (see `pubspec.yaml`)
- Android SDK for device builds. Android package: `com.bynexlabs.cash_client`. Minimum Android 7.0 (API 24), required by `shared_preferences` (`flutter_secure_storage` needs 6.0)
- The database (`cash_client.db`) is at version 3: member list (1), outbox (2), shared locks (3)
- Android builds use core library desugaring (`android/app/build.gradle.kts`), which `flutter_local_notifications` needs
- A running `bankingbackend` with backend PR #14 at `df9f555` or later (15 Nov 2026): collector payments, rotating refresh tokens, logout and the daily submission. Earlier backends answer refresh with a bare token, which this app no longer reads

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

- Calls `POST /api/auth/v1/collector-login` with `staffId`, `password` and `deviceId` (collectors have their own sign-in endpoint since 14 Nov 2026; the desktop app uses `staff-login`, which refuses collectors). The backend returns `staffName`, `roles`, `authToken` and `refreshToken`. A wrong ID or password, or an inactive account, returns 401; a valid account that isn't a collector returns 403.
- `deviceId` is the phone's own device ID, Android's `Settings.Secure.ANDROID_ID`, read through a platform channel in `MainActivity.kt` (`lib/auth/device_id.dart`). It needs no permission and survives reinstalling the app. The backend registers one phone per collector (owner decision 23 Nov 2026, D36): the first sign-in registers it, and another phone is refused (403) until the branch's agent or an administrator releases it. The ID is saved with the session and sent with every refresh, because the backend binds each session to its phone; that also lets the background sync refresh. If the phone gives no ID, sign-in says so and sends nothing.
- A 403 shows the backend's own message: "Only collector accounts can sign in here"; "This account is registered to another phone…"; "This account is locked after 5 wrong passwords…" (backend, 24 Nov 2026); or, once the collector's day has been approved, "…You can sign in again tomorrow" (backend, 15 Nov 2026). A response without the `COLLECTOR` role points the person to the desktop app. Either way any tokens are discarded, not stored. The backend still enforces permissions on every endpoint.
- The session (tokens, staff ID, name, roles) is stored with `flutter_secure_storage`, backed by the Android Keystore. The password is never stored. App backup is turned off so tokens never leave the phone.
- On launch, a stored session skips sign-in, so a collector stays signed in until they sign out or the backend ends the session.
- Signing out forgets the tokens on the phone at once, then calls `POST /api/auth/v1/logout` with the refresh token, so the backend ends the session and its tokens stop working (always 204). If that call can't get through, the session on the server runs out when its refresh token expires. Token lifetimes are set by the backend's `JWT_ACCESS_EXPIRATION` and `JWT_REFRESH_EXPIRATION`.

- Password reset: the backend has a three-step reset (`/api/auth/v1/password-reset/request-code`, `confirm-code`, `new-password`), but it isn't in the collector app for now (owner decision, 13 Nov 2026).

Code: `lib/auth/` (`auth_api.dart`, `session_manager.dart`, `session_store.dart`, `login_screen.dart`, and the sign-in messages in `sign_in.dart`), the error mapping in `lib/api/api_exception.dart`, and the sign-in/home switch in `lib/main.dart`.

## Token refresh

Calls to protected endpoints go through `AuthenticatedClient` (`lib/api/authenticated_client.dart`). Future features use it instead of a plain `http.Client`.

- It adds `Authorization: Bearer <access token>` to every request.
- On a 401 it calls `POST /api/auth/v1/refresh-collector-token` with `{"refreshToken": …}`, saves both new tokens and replays the request once, body included. That endpoint accepts only collector refresh tokens. Requests that hit a 401 at the same moment share one refresh call.
- The saved `deviceId` goes with every refresh; a different or missing one gets a 401 for a session bound to a phone. Sessions saved by builds before 24 Nov 2026 have no ID and refresh without one.
- Refresh tokens rotate (backend PR #14, 15 Nov 2026): the response is `{ "authToken", "refreshToken" }` and the refresh token sent is used up. The access token must have the shape of the backend's signed JWTs (three dot-separated parts) and the refresh token must be present; anything else, such as a proxy error page, is an unexpected response and nothing is saved.
- Spending a used refresh token again ends the whole session on the backend, so the app is careful never to:
  - The open app and the background sync each have a session manager, in separate isolates. Only one refreshes at a time, through a lock row (`app_locks`) in the app's SQLite database with a 40-second lease (`lib/auth/refresh_lock.dart`). Each first re-reads the stored session: if the other already refreshed, it takes those tokens instead of refreshing; if the other found the session ended, it ends here too.
  - A refresh that doesn't get through is retried once, straight away, with the same token. The backend accepts that token again for 30 seconds after a refresh whose response was lost, and refresh requests time out after 10 seconds so the retry lands inside that grace.
- When the refresh gets a 401 (refresh token expired, revoked or reused, collector deactivated, or the day's submission approved), the session ends: the tokens are cleared and the app returns to sign-in with "Your session has ended. … If today's collections were approved, you can sign in again tomorrow."
- If the refresh can't reach the server, the session is kept, so a collector isn't signed out for being offline.
- A 403 is passed straight through. It means the role isn't allowed, and a new token wouldn't change that.
- Multipart and streamed requests can't be replayed: on a 401 they still trigger a refresh, but the caller gets the 401 and has to retry.

## Home screen

After sign-in, a bottom bar switches between Home, History and Settings (`lib/home/home_shell.dart`). The tabs stay alive, so switching keeps each tab's scroll position.

Home (`lib/home/home_screen.dart`) keeps design A's layout, restyled as design H1, "wash header" (12 Nov 2026):

- The pale gradient wash across the top, running under the status bar, with rounded bottom corners. On it: a greeting for the time of day and the collector's name, shown in normal case (the backend sends it in upper case).
- Today's collections on a glass card inside the wash: total, number of records and, later, how many are waiting to send. All text on the glass uses the panel's main text colour, as on sign-in.
- An **Outbox** row on the plain page, only when payments are waiting on the phone or were refused: "3 waiting · 1 refused", opening the Outbox (design R2, 15 Nov 2026).
- On the plain page below: **Record deposit** (the screen's one gradient button) full width, with **Submit today's collections** beneath it. Design A had a **Withdrawal** button beside Record deposit; it was removed with collector withdrawal requests (owner decision, 15 Nov 2026).
- **Recent** records, with **See all** opening the History tab.

**Record deposit** opens the payment flow (below), and **Submit today's collections** the Submit today screen (see Submitting the day). Once the day is submitted, Record deposit says no more payments can be recorded until it's approved, with a View link back to the submission. Today's total and the recent list on home aren't connected yet: they show GH₵ 0.00 and "No collections recorded today".

History (`lib/home/history_screen.dart`), design Y1, "wash header" (12 Nov 2026):

- The same wash header as home (`lib/common/wash_header.dart`), with the title and today's record count and total on a glass strip.
- Filter chips on the plain page: All, Deposits, Shares (Withdrawals was dropped with collector withdrawal requests, 15 Nov 2026). The selected chip uses the soft indigo pill (set in the theme's `chipTheme`).
- Until the backend can list a collector's records, the count and total show zero and the list shows an empty state that names the selected filter ("No share payments yet"). Which record types each filter matches will follow the backend's transaction types.

If the session ends while a screen is open on top of the tabs (such as the payment screens), the app closes it and goes back to sign-in.

## Recording a payment

Design P1, "two screens" (15 Nov 2026), in `lib/collector/`. Collectors record two kinds of payment, matching the backend's `CollectorPaymentType`: a **savings deposit** (into the member's savings account) and a **share purchase** (into their shares account).

1. **Choose member** (`member_picker_screen.dart`). The branch member list from `GET /api/collector/v1/members`: names and savings/shares account numbers only, never other member details. Search by name or account number. When two members share a name, their account numbers show so they can be told apart.
2. **Record payment** (`record_payment_screen.dart`). Savings or Shares (only the types the member has an account for), the account number, the amount in GH₵ and an optional note (up to 500 characters). Amounts are cedis and pesewas, 2 decimal places (owner decision, 15 Nov 2026), up to GH₵ 999,999,999.99.
3. **Confirm payment** (`confirm_payment_screen.dart`). Member, account and amount are checked before anything is sent; only this screen sends the payment. Edit goes back.
4. **Payment saved** (`payment_saved_screen.dart`). Shown once the backend has saved it, or **Saved on this phone** when it couldn't be reached (see Offline payments). The payment is **Pending** for its 10-minute correction window, counted down from the window length the server sent (on the phone's monotonic clock, so a wrong phone clock can't change it); the member's balance and SMS follow when it closes. Done (or back) goes home, never to the confirm screen.

Sending (`collector_api.dart`):

- `POST /api/collector/v1/payments` with `idempotencyKey`, `type` (SAVINGS or SHARES), `accountNumber`, `amount` and optional `description`, through the authenticated client.
- The amount is held as whole pesewas (`lib/common/money.dart`) and written into the JSON as an exact decimal literal such as `50.50`, so it reaches the backend's `BigDecimal` without passing through a floating-point number.
- Each payment gets a random UUID idempotency key when the confirm screen opens. Every attempt to send that payment, including later syncs, uses the same key, so the backend never records it twice.
- When the backend refuses a payment, its own message is shown on the confirm screen word for word and nothing is saved, for example "This member's first deposit must be made at the office" (409), "This member isn't in your branch" (403), or an account that isn't active (409).

Member list on the phone (`member_cache.dart`, `member_directory.dart`):

- Saved in SQLite through `sqflite` (owner decision, 15 Nov 2026), in `cash_client.db`: tables `members`, `member_accounts` and `sync_meta` (when the list was downloaded). Each download replaces the whole list in one transaction.
- The picker shows the saved list straight away and downloads a fresh one in the background. Offline, the saved list still works, with a notice saying when it was saved; with nothing saved, it offers Try again.
- The list is cleared when the collector signs out or the session ends.
- The SQLite code itself isn't covered by tests (that needs a native SQLite library on the test machine); the logic around it is tested with an in-memory cache.

Not in this step: corrections within the 10 minutes, and connecting home's totals and the History tab to the backend.

## Submitting the day

Design D1, "Submit screen" (16 Nov 2026), in `lib/submission/`, against backend PR #14 (decision D35, 15 Nov 2026).

- **Before submitting** (`submit_day_screen.dart`): the screen first sends whatever is ready in the outbox, then loads today's totals (`GET /api/collector/v1/payments`: count, savings, shares, total) and the latest submission. It shows the total and count on a glass card, savings and shares below, and two checks:
  - **The outbox.** Nothing waiting on the phone ✓, or payments still on the phone (they go after their 10 minutes once online), or refused payments: "call your admin", which opens the Outbox.
  - **The 10-minute windows.** No payments in their 10 minutes ✓, or a countdown to when the last one closes.
- **Submit is blocked** while either check isn't clear. Tapping it says why instead of sending. Refused payments block it until the admin sorts them out (owner decision, 16 Nov 2026), because the backend doesn't know about them and the submission's expected cash would leave them out.
- **Submitting** asks for confirmation ("You'll hand in GH₵ … No more payments can be recorded until it's approved, and approval signs you out until tomorrow"), then sends `POST /api/collector/v1/submissions`. The backend's refusals are shown word for word, for example "…You can submit after 17:50". Sending it again while waiting returns the same submission, so a retry after a lost response is safe.
- **Waiting for approval**: the same screen shows a "Waiting for approval" chip, the cash to hand in (the backend's `expectedAmount`), when it was submitted, the payment count, and any failed payments counted separately. It checks the latest submission every 30 seconds.
- **Approval** (by the branch's agent or an administrator, with the cash counted; there's no rejection) ends all the collector's sessions at once. The next request gets a 401, the refresh is refused, and the app returns to sign-in. Signing in is refused (403) for the rest of the day, with the backend's message.
- **The day closed on the phone** (`day_closure.dart`): the app keeps a note in `sync_meta` while a submission waits, so Record deposit can explain the day is closed instead of taking a payment offline that the server would refuse. The note is updated from the backend at sign-in and on the submit screen, and cleared when the session ends.

## Offline payments

Owner decisions of 7 and 15 Nov 2026, built in `lib/outbox/` and `lib/sync/`.

Saving on the phone:

- When the confirm screen can't reach the backend (no connection, a timeout or a 5xx), the payment is saved in the `outbox` table of `cash_client.db` with the phone's time (`recordedAt`, in UTC) and the idempotency key it was just sent with. The collector sees **Saved on this phone** with a "Waiting · 9:59" countdown.
- If that attempt did reach the backend after all, the later sync sends the same key and gets the saved payment back instead of a second one.
- The app counts the 10 minutes from `recordedAt` and sends the payment only after them, with `recordedAt`, so it arrives final and the backend applies it straight away (decision D40). The backend accepts device times up to 5 minutes ahead of its clock.
- Times go to the backend as Accra time, which is UTC all year.

Sync (`payment_sync.dart`):

- Each payment is sent on its own. A refusal (400, 403, 404, 409 or another 4xx) never stops the others: the payment stays in the outbox with the backend's reason, and the collector gets one phone notification ("Payment refused … Report it to your admin").
- Refused payments are tried again automatically on every sync (owner decision, 15 Nov 2026), without notifying again. Once the office fixes the cause, the next sync sends it.
- No connection, a timeout, a 5xx or an ended session isn't a refusal: the payment just waits for the next sync, with no notification. No connection or an ended session stops the sync; a 5xx on one payment doesn't stop the rest.
- Sent payments are removed from the outbox.
- The app and the background sync can run at once. Each payment is claimed in the database for 2 minutes before it's sent, so the two never send the same one at the same moment.

When it syncs (`sync_scheduler.dart`, `background_sync.dart`):

- While the app is open: at sign-in and launch, when the app returns to the foreground, when the phone gets a connection (`connectivity_plus`), when a waiting payment's 10 minutes are up, and when the collector taps **Try again now** in the Outbox.
- While the app is closed: Android's WorkManager (`workmanager`) runs a sync about every 15 minutes whenever there's a connection, plus one when each payment's 10 minutes are up. Android may run these a little late, so a closed app can send a payment some minutes after its 10 minutes.
- Only the signed-in collector's payments are sent. Signing out, or the session ending, keeps them on the phone; they go after the same collector signs in again (owner decision, 15 Nov 2026). Sign out warns when payments haven't been sent.
- A payment saved on the phone after the day was submitted is refused by the backend (409) until the next day, so the app stops Record deposit while a submission waits (see Submitting the day).

The Outbox (`outbox_screen.dart`), design R2 (15 Nov 2026):

- Refused payments first, with the backend's reason, when they were recorded and refused, and **Try again now**. They can't be changed or removed on the phone (owner decision, 15 Nov 2026); the admin sorts out the cause.
- Then waiting payments with "Waiting · 6:12", or "Sends when online" once their 10 minutes are up.
- Tapping a refused-payment notification opens the Outbox. The notification permission (Android 13+) is asked for when the first payment is saved on the phone.

Not yet: cancelling a payment before it's sent and correcting it within its 10 minutes (owner decision 7 Nov 2026), which come with corrections. The outbox SQLite code, WorkManager and notifications aren't covered by tests; the sync rules, the Outbox screen and the offline flow are, with in-memory stand-ins.

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
