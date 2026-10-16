# SwiftDrop Mobile

Flutter application for the SwiftDrop group project. The planned app supports customer and courier workflows and uses the shared SwiftDrop backend APIs. The current source is the initial Flutter scaffold; product screens and API integrations have not been implemented yet.

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

## Run the starter app

From this folder:

```powershell
flutter pub get
flutter devices
flutter run
```

To select a device explicitly, use `flutter run -d <device-id>`. For an Android emulator, the host computer is normally reachable at `10.0.2.2`; a physical device should use the computer's reachable LAN address. The backend gateway is documented at port `5000`. The starter scaffold does not yet read an API base URL, so configure one in app code before expecting API calls to work.

When configuration support is added, pass local values without committing them, for example:

```powershell
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:5000
```

Never commit access tokens, Google credentials, signing keys, or local `.env` files. Do not put private credentials in `--dart-define`; values compiled into an app are not secret.

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
