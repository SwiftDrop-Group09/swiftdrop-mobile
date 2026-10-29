# Courier clients — Phase 7

This branch extends Customer Booking main `b819b42` without merging Identity or
altering booking requests, calculations, retries or confirmation behavior.
`MyApp` keeps Booking as its home and adds `/courier`; Booking and Courier have
navigation entries. Courier uses built-in Navigator and ChangeNotifier.

## Shared Identity boundary

`AppSession` is one shared snapshot; `CustomerSession` remains a compatible type
alias with the same constructors and `canBook`. `canCourier` adds the Courier
role check. No login, token storage, user picker or Courier ID is introduced.
The normal app starts signed out with UnavailableTransport. The IAM host injects
one ValueListenable<AppSession> and its authenticated RequestTransport through
MyApp (plus the existing ZoneCatalog for Booking), or supplies owned feature
controllers. The host must publish logout/account/role changes immediately and
prevent old requests from using another session's credentials.

The separate `origin/feat/identity-client-handoff` at `8d2d9d4` contains actual
native Identity implementation, despite its name. It was inspected and remains
unmerged. Its `IdentityAuthenticatedTransport(controller)` implements the same
JSON RequestTransport, deriving CustomerSession from `controller.customerSession`
and clearing private state through its existing IAM callback. That wrapper does
not yet support multipart. At the authorized integration checkpoint, its owner
must implement MultipartRequestTransport using the same authenticated request
lifecycle, generation checks, trusted origin and token refresh policy. Do not
bypass it with an unauthenticated second client or add a token field to Courier.

`HttpRequestTransport` now implements an optional multipart capability on its
existing client; RequestTransport.send is unchanged, so Booking and existing
test doubles remain compatible. A host already supplying an authenticated
http.Client may reuse that same instance for JSON and multipart. Proof fails
closed when the injected transport lacks the optional capability. No storage
credential or public proof URL enters the feature.

## Delivery contracts and proof

Courier uses only the five verified `/api/v1` endpoints: assignments, private
parcel details, status, pod, and terminal self history. Date/overdue/paging are
supported on manifest; history has paging only. Its six-field summary contract
does not reopen closed private details or expose failure reasons/proof URLs.
ExactNumber preserves 64-bit versions and decimal prices on native and web.

The next stage requires a private note (1–500 code units). Failed requires an
explicit RecipientUnavailable, AddressUnreachable, Damaged or Other reason;
optional notes are retained. Proof requires OutForDelivery, a recipient name
(1–120 code units), JPEG/PNG photo or drawn signature, or both, up to 5 MiB each.
Only a matching backend 200 receipt confirms Delivered. Multipart byte progress
reaching 100% means sent, followed by waiting for backend confirmation.

Camera/gallery uses [image_picker](https://pub.dev/packages/image_picker).
Image selection requests no full metadata, bounds image dimensions and size,
checks JPEG/PNG signatures, and stores a defensive immutable copy in memory.
Native picked cache files are deleted only after resolving their paths inside
the app's own [temporary directory](https://pub.dev/packages/path_provider).
Original gallery files outside that boundary are never deleted. Recovered lost
Android captures are discarded from owned cache rather than rebound to another
parcel or identity. No persistent proof queue or retention store is created.
Signature strokes and exported PNG are held in memory and released with forms.
iOS declares scoped camera/library descriptions; macOS declares user-selected
read access and network client access. Android internet and existing debug-only
loopback policy are preserved; no broader cleartext or storage permission is added.

## Concurrency and recovery

Each mutation freezes payload, version, immutable bytes and a secure random key.
An uncertain result retains that attempt, disables new actions and allows an
explicit identical retry after Retry-After. No automatic write retry occurs.
Unexpected 201/202 or other non-200 success responses also remain uncertain;
they cannot confirm delivery or discard the original key before a retry.
Undocumented redirects are equally unconfirmed. The shared JSON/multipart
transport requires HTTPS outside loopback, rejects credential-bearing bases,
foreign URL references and raw/encoded path traversal, and never follows a
redirect. Redirect responses become safe transport errors, preserving Booking
and Courier's existing uncertain-outcome recovery. Legitimate API paths, bodies,
headers, same-client authentication and loopback test traffic are retained.
Stale/invalid transitions clear the old detail and reload before a new action.
401/403 purge private state and ignore outstanding reads; 404 hides lost ownership.
Session changes clear lists/details, pending proof, receipt, forms and late
responses. Leaving a detail screen preserves an uncertain attempt in its host
controller; destroying that controller releases it. An app restart starts with
fresh reads, never an automatic new-key replay. Proof transport has a bounded
120-second wait; existing JSON transport deadlines remain unchanged.

## Checks and remaining integration

```text
flutter pub get --enforce-lockfile
flutter analyze
flutter test
flutter build web --release
flutter build apk --debug
```

Pinned dependencies are recorded in pubspec.lock. On this Windows machine the
SDK initially failed on plugin symlinks. Ignored workspace junctions to the exact
installed Pub cache targets allowed locked restore to finish; no Developer Mode,
registry or global SDK setting was changed. Fresh checkouts should use Flutter's
normal Windows symlink setup. Generated platform registrants come from the SDK.

Tests cover existing Booking and new Courier contract/controller/widget behavior,
including multipart/progress, exact numbers, proof validation/capture, stale state,
uncertain recovery, role/session changes and terminal history. The explicit
`dart run test_support/courier_http_smoke.dart` uses the backend's loopback-only
`--courier-workflow` fixture with its disposable PostgreSQL cluster. It shares
the fresh test dataset with React's smoke and uses signature-only completion.
No test principal is compiled into normal main.dart.

Live Identity/JWT wiring, native camera/gallery permissions and cancellation,
Android lost-activity behavior, Keystore/Keychain, Android SDK/emulator and
iOS/Xcode/device checks remain deployment integration dependencies. Web/HTTP
and widget tests cannot establish those native-device claims. Private bucket
KMS/IAM/TLS and outbox delivery acceptance remain backend integration work.
Proceed to Phase 8 only on explicit instruction.
