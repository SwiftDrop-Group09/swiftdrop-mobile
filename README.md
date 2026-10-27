# SwiftDrop Mobile

Flutter Customer/Courier Identity client for SwiftDrop. This branch implements
local and Google authentication, session restoration/rotation, own-profile editing,
explicit Google linking and logout. Customer/Courier use one session owner; the
Courier mode requires an actual server-assigned role and grants no privileges.
See [Identity implementation and verification](docs/identity-handoff.md).

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

## Run the Identity client

From this folder:

```powershell
flutter pub get
flutter devices
flutter run --dart-define=API_BASE_URL=https://gateway.example.test --dart-define=APP_MODE=customer
```

Replace the example origin with the team's reachable, trusted HTTPS Gateway
origin. Select an Android device with `-d` when needed; the SDK and emulator must
be installed first. Use `APP_MODE=courier` for the same Identity/profile flow with
Courier authorization status. HTTP, embedded URL credentials, and API subpaths
in the origin are rejected. No cleartext/TLS-validation exception is provided.

Google is optional for local password authentication. Set public
`GOOGLE_SERVER_CLIENT_ID` to the configured Web OAuth ID and register the Android
package/signing fingerprints with Google. iOS additionally needs
`GOOGLE_IOS_CLIENT_ID`, its URL scheme and Keychain host setup. No client secret
belongs in these values. Without the audience configuration Google buttons are
disabled. Browser/desktop authentication is intentionally unsupported; use React
for the browser.

Never commit tokens, private signing keys or local secrets. Do not put private
credentials in `--dart-define`; compiled configuration is not secret. Refresh
tokens use native secure storage; access tokens remain in memory. Passwords and
provider credentials are transient inputs, never stored in session state.

## Repository layout

```text
lib/                    Application source; see [lib/README.md](lib/README.md)
test/                   Unit and widget tests
android/                Android host project and build configuration
ios/                    iOS host project (requires macOS/Xcode to build for iOS)
web/, windows/, ...     Other Flutter-generated platform hosts
pubspec.yaml            Dependencies and Flutter package configuration
pubspec.lock            Resolved app dependencies; commit this file
analysis_options.yaml   Dart/Flutter lint rules
```

Keep platform-specific changes in the relevant host folder and application features in `lib/`. Do not commit build output, machine-local SDK paths, secrets, or signing files; see `.gitignore`.

## Team workflow

1. Start from the team's shared base branch and create a short-lived branch for one feature or fix (for example, `feat/courier-delivery-list`). Do not commit directly to the base branch.
2. Confirm current endpoint, request/response and authorization contracts before
   integrating other features. Identity follows the existing REST contracts;
   canonical tracking uses SSE. Earlier SignalR prose remains a documentation
   mismatch and does not authorize adding competing realtime infrastructure.
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
