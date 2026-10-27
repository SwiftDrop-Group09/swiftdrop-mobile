# Part A Phase 8 Identity implementation

## Current status: 27 October 2026

Flutter **3.47.8** / Dart **3.13.7** are now available. Following the user's
instruction to resume integration, the earlier blocked checkpoint below has been
extended into an implemented Customer/Courier Identity feature. The shared base
remains `e9778c1` on `feat/identity-client-handoff`; all changes are uncommitted.
The independent booking branch is preserved without merging or copying its
business functionality.

Implemented local registration/login, native Google ID-token exchange and
cancellation, fresh-password explicit linking, own-profile read/update,
restoration, single-flight rotation, secure refresh persistence and logout.
`MaterialApp` and built-in `ChangeNotifier` follow the existing teammate patterns;
`http 1.6.0` matches the booking branch. The required platform adapters use
[google_sign_in 7.2.0](https://pub.dev/packages/google_sign_in) and
[flutter_secure_storage 11.2.0](https://pub.dev/packages/flutter_secure_storage).
No third-party router or state framework was introduced.

One controller serializes credential changes and refresh writes. It publishes an
authenticated user only after secure persistence succeeds, rejects late responses
after logout/account changes, and clears private state on denied restoration.
Failed storage writes attempt family revocation and fail closed. Logout clears
memory immediately and reports when secure deletion or server revocation cannot
be confirmed, including an abandoned in-flight login. Only refresh secrets use
OS storage; passwords/provider credentials never enter published session state.
Google cancellation causes no Identity login request, and a wrong fresh linking
password does not destroy the existing local session.

The HTTPS transport rejects redirects, external/traversing destinations,
caller-supplied identity/cookie headers and oversized payloads; its bounded
deadline aborts network work. Authenticated GET may refresh/retry once; booking
mutations are not replayed. Android INTERNET is enabled, cleartext traffic and
backups are disabled, and credential preferences are excluded from transfer.
Web/desktop fail closed before credential adapters are created.

Actual checks so far: `flutter pub get` passed, analyzer found no issues, and the
full **104-test** unit/widget suite passed after two logout-outcome regressions
were reproduced and fixed. Formatting passed. Package resolution initially hit
Windows symlink restrictions; only ignored workspace plugin-directory junctions
were created to the exact existing Pub cache targets. No OS/global setting was
changed. The standard Developer Mode/symlink setup remains recommended for fresh
Windows checkouts. Generated tracked plugin registration metadata reflects the
new packages; it does not enable desktop authentication.

`flutter build apk --debug --no-pub` was attempted and failed because **Android
SDK tools are not installed**. Native Google consent, real device Keystore/Keychain,
Android packaging and iOS/Xcode validation remain unverified. iOS Google URL-scheme
and Keychain host provisioning are still required. No live backend credentials
or signing material were invented. The standalone opt-in native API smoke in
`integration/identity_api_smoke.dart` is driven by the backend HTTPS harness,
using real Identity/PostgreSQL and a narrowly trusted temporary public certificate;
its actual result is recorded in the backend continuation report.

### Files and integration seams

- `lib/main.dart`, `lib/app/app.dart`: native configuration/bootstrap and shell.
- `lib/core/config/identity_config.dart`, `errors/identity_exception.dart`,
  `network/request_transport.dart`, `session/customer_session.dart`,
  `storage/refresh_token_store.dart`: technical adapters and compatible ports.
- `lib/features/auth/domain/{identity_models,google_identity_provider}.dart`,
  `data/{identity_api,native_google_identity_provider}.dart`,
  `presentation/{identity_controller,identity_screens}.dart`: one Identity feature.
- `test/core/*`, `test/features/auth/{data,presentation}/*`, `test/widget_test.dart`:
  adapter, controller and UI behavior, using platform/HTTP fixtures.
- `integration/identity_api_smoke.dart`: explicit real-server native API test;
  default `flutter test` does not require a deployed service.
- `pubspec.yaml`/lock, Android manifest/extraction rules, generated plugin
  registrants, README and this implementation record.

Use `IdentityAuthenticatedTransport(controller)` for the existing
`RequestTransport` seam and derive its `CustomerSession` from
`controller.customerSession`. Clear booking attempts/private feature state via
the controller's injected `clearPrivateData` callback. No second token store or
local role override is needed. Courier mode changes presentation; only the
server-returned Courier role authorizes future operations. Operational Courier
profiles, assignments and booking screens remain their owners' work.

## Historical 26 October discovery and unchanged server contract

### Original prerequisites

The original main branch contained only the generated counter app and its widget
test. `lib/README.md` explicitly requires the team to choose navigation,
state-management, and HTTP packages before feature work; none have been selected
or installed on main at that checkpoint. There was no session owner, secure-storage adapter,
environment configuration, API client, Google SDK adapter, or authentication
screen. Flutter/Dart were absent from PATH during that checkpoint, so
`flutter pub get`, `flutter analyze`, `flutter test`, Android builds, and device
tests were not executed. No mobile CI workflow exists on this baseline.

The fetched, independent `origin/feat/customer-quote-booking` branch (`4d0eecf`)
has real booking code. It must be preserved and integrated through its existing
ports after the owning teammate coordinates the shared base:

- `lib/core/network/request_transport.dart`: `RequestTransport.send(method,
  path, {body, headers})`, `ApiReply`, and ordinary `HttpRequestTransport`.
- `lib/core/session/customer_session.dart`: `CustomerSession(principalId,
  roles)`, with `canBook` requiring Customer.
- `lib/app/app.dart`: currently injects a signed-out `ValueNotifier` and an
  unavailable authenticated transport; replace those through shared session
  wiring when Identity is integrated, without duplicating booking logic.

Do not merge or copy that branch as part of this handoff. Its current dependencies
and transport conventions differ from the main scaffold and need team
coordination. This repository's old SignalR references conflict with the
canonical SSE baseline; Identity work does not add realtime infrastructure.

### Server/client contract retained by this implementation

The current SDK satisfies Dart `^3.13.2`. The client has one configurable HTTPS
Gateway origin, one authenticated transport, one session owner and platform storage.
Store rotating refresh tokens only in OS-protected storage. Never use plain
preferences, files, logs, URL parameters, or browser storage as a fallback.
Client IDs and Gateway URLs are public configuration; JWT signing keys and
Google client secrets must never ship in the app.

The app sends native JSON requests through the Gateway:

| Operation | Request | Success |
| --- | --- | --- |
| Local login | `POST /api/v1/auth/login` `{email,password}` | TokenPair |
| Google login | `POST /api/v1/auth/google` `{idToken}` | TokenPair |
| Refresh | `POST /api/v1/auth/refresh` `{refreshToken}` | TokenPair |
| Logout | `POST /api/v1/auth/logout` `{refreshToken}` plus app bearer | 204 |
| Own profile | `GET /api/v1/users/me` plus app bearer | Profile |
| Edit profile | `PUT /api/v1/users/me` `{fullName,phoneNumber,address}` plus bearer | Profile |
| Explicit link | `POST /api/v1/auth/google/link` `{idToken,currentPassword}` plus bearer | Profile |

TokenPair is `{accessToken,tokenType:"Bearer",expiresInSeconds:900,user,
refreshToken}` for native clients. Profile is `{id,email,fullName,phoneNumber,
address,roles,isActive}`. Identity assigns initial Customer on public signup and
new Google identities. Courier access requires an actual server-assigned Courier
role. Both Customer and Courier share authentication infrastructure, without
client-side role promotion or a separate Google identity model.

Use the native Google SDK's ID token and provision the correct platform audience,
package/signing fingerprints, and backend audience allowlist. The current native
contract has no trusted expected-nonce transport: ordinary SDK no-nonce tokens
are supported; nonce-bearing tokens must not be invented or bypassed. Browser
cookie/CSRF fields do not belong in native requests. Google cancellation performs
no API call. A 409 `account_link_required` requires local sign-in followed by
explicit password-confirmed linking; never merge by email. No backend Google
code/callback endpoint exists.

Serialize refresh across API operations. Replace the secure stored refresh token
only after a complete successful rotation; failure/reuse signs the user out and
clears private caches. Never automatically retry a booking mutation after an
ambiguous response. Restore via refresh, then server profile. Logout attempts
server revocation, clears secure storage and memory, and distinguishes an
unconfirmed server outcome. Existing access JWTs can remain valid for up to
900 seconds plus 30 seconds of clock skew after logout/deactivation; no immediate downstream revocation is
promised.

Profile editing requires fullName (trimmed 1–120) and the phoneNumber field
(nullable, at most 32), plus optional address within the API's 16 KiB JSON limit. Empty
phone/address normalize to null. IDs, email, roles, and account activation are
not self-editable. Backend policies enforce all permissions.

### Remaining device/deployment acceptance

Unit/widget tests cover form validation, login/Google outcomes, cancellation,
restoration, single-flight rotation, secure-storage updates/clearing, own-profile
editing, unauthorized role navigation, failed refresh/logout and linking errors.
Formatter, analyzer and tests have run; Android SDK installation is needed for
the native build. Exercise Customer and authorized Courier flows against the actual HTTPS
Gateway on an emulator/device, including Google audience verification and secure
storage behavior. Non-loopback traffic requires trusted HTTPS; do not add broad
cleartext exceptions to make physical-device testing pass.

The backend phase report and frontend `docs/identity-integration.md` provide the
implemented server/browser behavior. The original source specification remains
Proposed; this record does not amend it or claim live device/provider completion.
