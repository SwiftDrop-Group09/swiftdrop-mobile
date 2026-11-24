# SwiftDrop Mobile

The Flutter app provides dedicated customer and courier workspaces. Both modes use SwiftDrop Identity for sign-in, session restoration, and profile management. Courier access requires the Courier role assigned by the server.

| Mode | Workflows |
| --- | --- |
| Customer | Request quotes from the live zone catalog, confirm bookings, track parcels, view history and receipts, and use the delivery assistant. |
| Courier | Review assignments, update delivery status, capture and upload proof, report failed deliveries, and review completed work. |

## Requirements

- Flutter with a bundled Dart SDK that satisfies the constraint in [pubspec.yaml](pubspec.yaml).
- Android SDK, an emulator or physical device, and Android API level 26 or later.
- macOS and Xcode for iOS builds. See the [Identity handoff](docs/identity-handoff.md) for native sign-in configuration.

## Run locally

From the repository root, verify the toolchain and select a connected device.

```sh
flutter doctor -v
flutter pub get
flutter devices
```

Run either workspace with the corresponding `APP_MODE`.

```sh
flutter run --dart-define=API_BASE_URL=https://gateway.example.test --dart-define=APP_MODE=customer
flutter run --dart-define=API_BASE_URL=https://gateway.example.test --dart-define=APP_MODE=courier
```

Replace the example with the trusted HTTPS gateway origin reachable from the device. Use the origin only, without an API path, and pass `-d <device-id>` when selecting among multiple devices.

Password sign-in works with the gateway configuration alone. For native Google sign-in, provide the public `GOOGLE_SERVER_CLIENT_ID` and register the Android package and signing fingerprints. iOS also requires `GOOGLE_IOS_CLIENT_ID` and native URL scheme and Keychain configuration. Keep private credentials out of compiled `--dart-define` values. The app stores refresh tokens in native secure storage and keeps access tokens in memory.

## Develop and verify

Application source is under [lib/](lib/README.md), with unit and widget tests in [test/](test/). Keep Android and iOS host configuration in their respective platform directories.

```sh
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
```

See the [Identity handoff](docs/identity-handoff.md) and [Courier integration guide](docs/courier-integration.md) for setup, role requirements, and workflow checks.

## SwiftDrop repositories

| Repository | Responsibility |
| --- | --- |
| [Backend](https://github.com/SwiftDrop-Group09/swiftdrop-backend) | Gateway, APIs, background workers, and integration contracts |
| [Web frontend](https://github.com/SwiftDrop-Group09/swiftdrop-frontend) | React web application and role-based workspaces |
| [Mobile app](https://github.com/SwiftDrop-Group09/swiftdrop-mobile) | Flutter application for customers and couriers |
| [Infrastructure](https://github.com/SwiftDrop-Group09/swiftdrop-infra) | Local development, Docker Compose, and Kubernetes deployment |
| [Project documentation](https://github.com/SwiftDrop-Group09/swiftdrop-docs) | Requirements, architecture, integration design, and assessment evidence |
