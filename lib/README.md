# Organizing `lib/`

Use a **feature-first** layout so customer and courier work can grow independently. Keep the structure lightweight at first: add a layer or folder when a feature needs it, rather than creating empty architecture everywhere.

```text
lib/
  main.dart                  App entry point; keep startup wiring here
  app/
    app.dart                 MaterialApp/CupertinoApp, theme, top-level setup
    router/                  App navigation and route definitions
    theme/                   Colors, typography, and shared theme setup
  core/                      App-wide technical foundations
    config/                  Environment and API base URL configuration
    errors/                  Shared error types and mapping
    network/                 HTTP client and common request behavior
    storage/                 Secure token/session storage abstractions
  shared/                    UI and utilities reused by multiple features
    widgets/
    extensions/
  features/
    auth/
      data/                  API/data sources, DTOs, repository implementations
      domain/                Feature models, repository contracts, use cases
      presentation/           Login screens, widgets, and view state
    customer/
      booking/
      tracking/
      history/
    courier/
      deliveries/
      proof_of_delivery/
      location/
```

The nested feature folders are examples, not a requirement to create all of them now. Start with `main.dart`, the app shell, and the first agreed feature. Add `data/`, `domain/`, and `presentation/` when they help keep UI, business rules, and API work separate.

## What belongs where

- **`main.dart`**: initialize app-wide dependencies and call `runApp`. Avoid putting screen code or feature logic here.
- **`app/`**: app shell, navigation, and theme. It can depend on features; individual features should not depend on unrelated features.
- **`core/`**: cross-feature infrastructure such as API configuration, a shared network client, and secure storage interfaces. Keep business-specific behavior out of `core/`.
- **`features/<feature>/presentation/`**: screens, feature widgets, and UI state. Screens render loading, error, empty, and success states and delegate work to a state/controller layer selected by the team.
- **`features/<feature>/data/`**: remote/local data sources, JSON DTOs, and repository implementations. Translate API responses here rather than spreading JSON parsing through widgets.
- **`features/<feature>/domain/`**: feature-level business models and repository contracts when the feature complexity justifies this layer.
- **`shared/`**: components that are truly reused across features. Keep a widget in its feature until a second feature needs it.
- **`test/`** (at repository root): mirror the `lib/` feature path for unit and widget tests.

Use clear, consistent Dart names: files and folders in `snake_case.dart`, types in `UpperCamelCase`, and variables/functions in `lowerCamelCase`. Prefer small widgets and explicit dependencies over large screens that own networking, parsing, and business rules.

## A practical coding sequence

1. Agree on the user story, acceptance criteria, and owning teammate. Keep work on a feature branch and avoid overlapping edits to the same feature files.
2. Check the relevant SwiftDrop requirement and confirm the API contract with the backend owner. The documentation currently has differing real-time endpoint descriptions; do not guess an endpoint or authentication rule.
3. Sketch the screen flow and data model. Identify loading, empty, success, validation, and network-error states before wiring the UI.
4. Implement a small vertical slice: screen/widget → feature state/controller → repository → API/data source. Add only the package dependencies the team has agreed to use.
5. Keep rotating refresh tokens in platform secure storage and short-lived access
   tokens in session memory. Never log credentials. Put deployment URLs behind
   the configuration boundary and use trusted HTTPS; do not add cleartext or
   certificate-validation exceptions for emulator development.
6. Add tests alongside the behavior: model/repository unit tests and widget tests for important UI states. Keep tests in the mirrored `test/` path.
7. Before review, format and check the change:

   ```powershell
   dart format lib test
   flutter analyze
   flutter test
   ```

8. Open a pull request describing the user-visible change, API contract used, screenshots for UI work, and any setup/configuration changes.

## Team decisions to make before feature work

Choose one shared navigation approach, state-management approach, and HTTP client as a group before adding dependencies. Keep those choices and package versions consistent across branches. The project documentation specifies Flutter/Dart and shared backend APIs, but it does not prescribe these Flutter architecture packages.

The Identity slice follows the existing booking branch's built-in Material
navigation, ChangeNotifier/ValueNotifier patterns and `http` transport. Its only
additional platform packages provide native Google sign-in and secure refresh
storage. Other features should integrate through the shared session/transport
ports instead of adding another credential owner.
