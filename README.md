# SwiftDrop Mobile

Flutter application for the SwiftDrop group project. Customer booking implements
pickup/delivery/recipient/package forms, server fee preview, explicit confirmation,
safe retry recovery and the committed server tracking result. The feature uses
injected session, HTTP and zone-catalog interfaces. IAM remains a separate task;
the normal app requires a Customer session and never selects a fictional user.
Courier manifest, details, stage/failure actions, temporary proof capture/upload
and terminal history are implemented using those shared integration ports.
See [Courier integration](docs/courier-integration.md) for contracts, concurrency,
Identity handoff, verification and native-device dependencies.

## Requirements

- Flutter SDK 3.x with a bundled Dart SDK that satisfies the `sdk` constraint in `pubspec.yaml` (currently `^3.13.2`). Keep the Flutter version consistent across the team and share the output of `flutter --version` when diagnosing setup differences.
- Android Studio with the Android SDK Platform, Platform Tools, and Android SDK Command-line Tools installed.
- An Android emulator or Android device. The project requirements specify Android API level 26 or later.
- Git and an editor with Flutter/Dart support, such as Android Studio or VS Code.

On Windows, install the Flutter SDK outside this repository (for example, `C:\src\flutter`) and add its `bin` directory to `Path`. Install the Flutter and Dart editor plugins/extensions, then run:

```powershell
flutter doctor -v
flutter doctor --android-licenses
flutter devices
```

Resolve Android toolchain issues reported by `flutter doctor` before building. See [Flutter's Android setup guide](https://docs.flutter.dev/platform-integration/android/setup?tab=virtual) for current installation steps.

## Run the normal app

From this folder:

```powershell
flutter pub get
flutter devices
flutter run
```

To select a device explicitly, use `flutter run -d <device-id>`. The normal app
shows a Customer sign-in requirement until the IAM owner supplies the session
and authenticated `RequestTransport` adapter. Both the root and `/book` compose
the same booking screen. No bearer-token field, test identity switch, refresh
manager or token storage was introduced.

The API base URL is public configuration, not a secret. The isolated test target
below reads `API_BASE_URL`; normal IAM integration supplies its authenticated
transport/base URL through the composition boundary.

## Work independently of IAM

The explicit `test_support/booking_harness.dart` entry point loads its actor,
roles and human-readable service zones from the separately started Delivery
test host. The actor is fixed by that server's startup, never by mobile request
headers. The server runs the actual quote/booking pipeline against disposable
PostgreSQL. It does not use live Neon secrets. Normal `lib/main.dart` does not
import this fixture entry point, and the fixture refuses release mode.

From this repository, start the sibling backend fixture in one terminal:

```powershell
dotnet run --project ../swiftdrop-backend/tests/SwiftDrop.Delivery.Harness --configuration Release -- --port 5088 --actor customer-a
```

For a browser test target (profile mode is intentional):

```powershell
flutter build web --profile --no-web-resources-cdn -t test_support/booking_harness.dart --output build/booking-harness
python test_support/serve_web_harness.py
```

Open `http://127.0.0.1:5181`. The loopback-only Python helper serves that separate
build and proxies `/api` and `/__test` to port 5088 without CORS changes. The
screen is labelled TEST DATA. Browser requests remain same-origin; no token or
private project secret is embedded in the build.

For an Android device/emulator with SDK tools installed, use loopback forwarding:

```powershell
adb reverse tcp:5088 tcp:5088
flutter run -t test_support/booking_harness.dart --dart-define=API_BASE_URL=http://127.0.0.1:5088
```

The Android debug network policy permits cleartext only for localhost/loopback;
release-wide cleartext is not enabled. Retain Android API level 26+. Real
non-loopback deployments require the agreed HTTPS/IAM integration.

A pure Dart check exercises the same HTTP API adapter, exact numeric codec and
server response parsing without an Android SDK:

```powershell
dart run test_support/booking_http_smoke.dart http://127.0.0.1:5088
```

This creates one fictional booking and replays the same key/body. It verifies
real HTTP/business persistence, not real JWT verification. Stop the backend
fixture with Ctrl-C or its `stop` command so it cleans up its private cluster.

Never commit access tokens, Google credentials, signing keys, or local `.env` files. Do not put private credentials in `--dart-define`; values compiled into an app are not secret.

## Repository layout

```text
lib/app/                Normal app composition and /book route
lib/core/               Session/HTTP ports and lossless numeric JSON
lib/features/customer/booking/
                        DTO/API, controller and booking form/preview/result
test/                   Codec, controller, transport and widget tests
test_support/           Explicit fixture target, HTTP smoke and loopback web proxy
android/                Android host project and build configuration
ios/                    iOS host project (requires macOS/Xcode to build for iOS)
web/, windows/, ...     Other Flutter-generated platform hosts
pubspec.yaml            Dependencies and Flutter package configuration
pubspec.lock            Resolved app dependencies; commit this file
analysis_options.yaml   Dart/Flutter lint rules
```

Keep platform-specific changes in the relevant host folder and application features in `lib/`. Do not commit build output, machine-local SDK paths, secrets, or signing files; see `.gitignore`.

The codec preserves numeric JSON tokens before any JavaScript/Dart floating-point
conversion. Fee totals come only from Delivery; confirmation sends exactly the
quoted value. An uncertain response retains the original owner/key/body even
after local quote expiry. New quotes after a definite expiry/price rejection
require fresh explicit acceptance. Session changes clear private form/result
state, and a pending attempt cannot be automatically replaced by another key.

```powershell
dart format --output=none --set-exit-if-changed lib test test_support
flutter analyze
flutter test
flutter build web --release --no-web-resources-cdn
```

Tests cover validation, quote-only preview/decline, explicit confirmation,
duplicate submission, expiry/repricing, unknown-outcome retries, large exact
amounts, stale responses and session changes. The normal release web build and
separate fixture build are distinct outputs. Android/device acceptance still
requires an installed Android SDK/device; desktop builds require platform tools.

## Team workflow

1. Start from the team's shared base branch and create a short-lived branch for one feature or fix (for example, `feat/courier-delivery-list`). Do not commit directly to the base branch.
2. Before coding a backend integration, confirm the current endpoint, request/response schema, authentication, and error behavior with the backend owner. The docs describe REST/GraphQL APIs, SSE customer tracking, and SignalR/WebSocket courier telemetry; some endpoint details differ between documents.
3. Keep each change focused. Put widgets and screens in their feature, API access behind a repository/data layer, and reusable app-wide code in `core/` or `shared/` as described in [lib/README.md](lib/README.md).
4. Include or update tests for changed behavior. Run formatting, analysis, and relevant tests before opening a pull request:

   ```powershell
   dart format lib test
   flutter analyze
   flutter test
   ```

5. Commit the Flutter app's `pubspec.lock` when dependencies change. Use clear commit messages, push the feature branch, and open a pull request for team review.

## Project references

- [SwiftDrop documentation repository](../swiftdrop-docs/README.md)
- [Software requirements](../swiftdrop-docs/requirements/srs.md)
- [REST API](../swiftdrop-docs/api/rest-api.md)
- [GraphQL API](../swiftdrop-docs/api/graphql-api.md)
- [Real-time tracking](../swiftdrop-docs/integration/realtime-tracking.md)
- [SignalR/WebSocket protocol](../swiftdrop-docs/api/websocket-protocol.md)
