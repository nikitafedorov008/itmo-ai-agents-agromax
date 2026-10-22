# Мобильный АГРОМАКС

Flutter Android/iOS client in `apps/mobile`, with Riverpod, `sqflite`, `http`, `image_picker`, `geolocator` and Keychain/Keystore session storage. Native project id: `ru.agromax.agromax`. Minimum iOS version 15. Flutter used: 3.38.7. Package versions are locked in `pubspec.lock`.

## Run

Start the shared API and Supabase according to the repository setup. In a second terminal:

```sh
cd apps/mobile
flutter pub get
# iOS simulator (host machine API)
flutter run --dart-define=API_BASE_URL=http://localhost:8787
# Android emulator routes to host using 10.0.2.2
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8787
# Physical phone: use a reachable LAN host and permit local network access
flutter run --dart-define=API_BASE_URL=http://192.168.1.100:8787
```

`API_BASE_URL` defaults to `http://localhost:8787`. Use an HTTPS origin in production; development Android manifest currently permits cleartext traffic and iOS allows local networking. Configure release signing before store distribution; generated Android release configuration currently uses debug signing. Neither app-store distribution nor a release-signed build is claimed.

## Actual behavior

- Login/signup call the backend; email confirmation is shown as an explicit state if no session is returned. Demo requests an isolated server farm, with synthetic field labels. There is no silent seed/fake response fallback.
- Chief users can create a field by name, crop, hectares and center coordinates. Empty `boundary` means a point-only field, explicitly described in the form. Creation requires a connected server and confirmation; its pending operation id persists for retry.
- Fields, observations, tasks, conversations and notifications cache per farm/user in SQLite. A previously authenticated user can reopen the app offline. The session token is in platform secure storage, not SQLite. Draft forms are scoped to account and selected field and persist while typing. Cache and pending records do not switch accounts during logout/login.
- Camera/gallery images are copied into application documents **before** a draft records their path. Android startup runs `retrieveLostData`. Location requests foreground permission only and reports unavailable/denied permission. Historical private photos use authenticated API URLs; remote photo bytes are not cached for offline display.
- Saving an observation appends an outbox operation in SQLite. `local`, `sending`, `synced`, `error`, `conflict` statuses are visible. Sync runs manually, on resume and every 30 seconds while the app is running. Background execution while the OS suspends the app is not claimed.
- Every queued operation has a UUID fixed at creation. Retries and restart recovery reuse it. Each photo upload completes first and persists its returned id before the observation is sent. Each durable local photo gets its own UUID persisted before the upload request. Multipart `operationId` lets the backend return the same photo when its original response is lost, including after SQLite reopen; path removal and the returned photo id checkpoint together. The local path-to-upload-id map is stripped from observation JSON.
- Version conflicts preserve local payload and stop dependent approval of the same observation. The queue can explicitly restore the complete local observation (note, extent, location and uploaded/pending photo references) as a linked draft after confirmation, retaining the original conflicting operation. They do not overwrite the server. The UI asks the user to inspect current history and create a linked repeat observation; automatic merge is not implemented.
- Task completion requires an outcome and explicit confirmation. A repeat inspection creates a child draft with `parentObservationId`. Approval includes the expected version and `confirmed: true`; an agent's proposed task, when present, is passed in the same approval operation.
- Agent provider is selected explicitly (`deepseek` / `mimo`). Backend 503/errors are displayed. Conversation history, model, actual source references and returned artifacts are rendered. Proposed text without an observation id can be opened as a draft; saving is a separate explicit action. Pending chat request ids persist per account/field across retries. Network failures and `IN_PROGRESS` retain the original UUID; an acknowledged terminal model/provider/agent error is persisted and offers an explicit New attempt with a new UUID and optionally a different selected provider. No automatic fresh attempt is sent.
- No LiteRT, diagnosis model, push notifications, background mobile scheduler, field-boundary editor or map tiles are represented as implemented.

## Validation

```sh
flutter analyze
flutter test
flutter build apk --debug --dart-define=API_BASE_URL=http://10.0.2.2:8787
flutter build ios --simulator --debug --no-codesign
```

Nine tests (seven SQLite integration tests and two retry-policy tests) verify offline retry across a database close/reopen, stable operation ids, photo checkpoint ordering, atomic draft-to-queue transfer, per-account isolation, recovery of `sending`, conflict preservation/dependency blocking and no resend of synced operations. `flutter analyze` passes.

Local build results on 2026-10-23: Android APK build could not start because no Android SDK is installed/discoverable. iOS simulator build compiles native dependencies after setting all deployment targets to iOS 15; Flutter 3.38.7 then fails packaging `Flutter.framework` with `does not contain architectures "arm64 x86_64"` while its own `lipo -info` lists both. A targeted `flutter run` found no booted supported iOS device. Therefore device launch, camera permission interaction and native end-to-end flows remain unverified on this machine. The source projects and permission manifests are present; tests do not establish a successful native build.

Official package guidance used: [image_picker durable images and lost-data recovery](https://github.com/flutter/packages/tree/main/packages/image_picker/image_picker), [path_provider app documents](https://github.com/flutter/packages/tree/main/packages/path_provider/path_provider).
