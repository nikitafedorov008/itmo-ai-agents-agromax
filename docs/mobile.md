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

Twelve tests (SQLite queue and retry-policy checks) verify offline retry across a database close/reopen, stable operation ids, photo checkpoint ordering, atomic draft-to-queue transfer, per-account isolation, recovery of `sending`, conflict preservation/dependency blocking and no resend of synced operations. `flutter analyze` passes.

Local validation on 2026-10-23: Android APK build could not start because no Android SDK is installed/discoverable. The generic universal iOS simulator build hits a Flutter 3.38.7 / Xcode 27 architecture-verification incompatibility. Targeting the booted iPhone 17 Pro (iOS 26.4) via `flutter run -d <id>` successfully builds and launches. The real-backend native integration test and its screenshot-export driver both pass: normal-account UI login, point-only field, durable synthetic PNG, upload/outbox, authenticated server retrieval, no duplicate on repeated sync, and native SQLite close/reopen. A separate manual process-stop/relaunch check with the API stopped preserved a typed draft and a queued operation; reconnect synced it successfully. The same native-created observation and photo were verified through normal login in the web app. Physical camera capture and GPS permission dialogs remain untested. See `docs/VERIFICATION.md` for evidence.

Official package guidance used: [image_picker durable images and lost-data recovery](https://github.com/flutter/packages/tree/main/packages/image_picker/image_picker), [path_provider app documents](https://github.com/flutter/packages/tree/main/packages/path_provider/path_provider).

## Observation workbench redesign (2026-10-23)

The production Flutter app now has four destinations: Поле, Осмотр, Задачи, Ещё. The durable outbox remains under Ещё. The observation workbench shows the real observation note and authenticated uploaded photo (or a visibly labelled botanical illustration), real field map, evidence from the returned tool list, model-returned questions/options, source disclosure, and a separate review/confirmation step. Contextual discussions are sheets reachable from field history and the workbench; answers use the existing durable chat attempt/retry mechanism and include the selected observation id. SQLite, photo checkpoint/operation ids, account isolation and offline sync remain in existing model/storage/sync modules.

On iOS the app uses Cupertino navigation/tab bars, inputs, buttons, alerts, action sheets, date/time picker and activity indicators; Android retains Material 3 controls. Shared identity uses forest/ivory/celery with readable 14–16px body text. UI lives in `lib/ui/` modules rather than a second app or HTML mock.

`flutter_map` 8.3.2 renders real field boundaries, centers and observation locations. The satellite option requests attributed Esri World Imagery; the scheme option uses attributed OpenStreetMap tiles. Satellite tile failures fall back to OSM. A tile failure state states that a connection is required, while real saved contours and points remain. Point-only fields are explicitly labelled. Tiles require network; they are not an offline imagery cache.

Static verification: `flutter analyze` and all fourteen tests passed during implementation (twelve existing queue/chat retry tests plus verified-evidence and native-input reset regressions). Native simulator execution is coordinated separately; this paragraph does not claim a simulator run of the new design.

Observation-specific conversation ids are stored locally per account/field/observation so model clarification answers continue the same context across restarts. Returned contextual actions open real field history, weather API, sources, repeat inspection and discussion flows. Map observation markers open a native detail sheet with actual note, coordinates, date and authenticated photos.

A separate actual-model native integration is available (requires the configured local backend and DeepSeek; creates a fresh synthetic normal account/field/observation):

```sh
flutter drive --driver=test_driver/workbench_backend_driver.dart --target=integration_test/workbench_backend_test.dart -d B11CC23A-CE56-48B9-87D1-21770AD2A548 --dart-define=API_BASE_URL=http://localhost:8787
```

It logs in through the Cupertino UI, preserves a real local draft, requests a real model clarification through the contextual sheet, displays the returned question/options in the workbench, taps an actual option, verifies the same server conversation and unchanged draft/observation with no task silently created, and exports three screenshots plus non-secret `workbench-proof.json` under `build/native-evidence/`. It intentionally retains the fixture session and local draft for normal app relaunch. Static analysis confirms this test compiles; execution is recorded separately.

Historical AI replies are projected against the latest observation version before rendering actions. Changed/missing observations retain historical text, tool reads, sources and evidence while obsolete questions, task proposals and approval commands disappear with a notice. Already approved observations suppress proposals and approval commands while retaining valid fresh clarification questions and read-only discussion actions. Approved observations offer a repeat inspection. The workbench uses one review button, which opens the native review/date/confirmation flow for a current draft, instead of repeating the AI body in an extra approval card. Four regression cases cover current, changed, approved and missing observations; all eighteen mobile tests pass.

The compact workbench follows the selected direction: photograph and six-line note preview share one row with native full-note disclosure, the real map starts as a 140px expandable peek, and the dark evidence surface uses the returned artifact summary plus two real history/weather status tiles. Tool-verified evidence details are collapsed and source count is small; full model text remains in contextual discussion. Nineteen mobile tests now pass. The native integration option scroll uses zero-duration alignment so it cannot await an animation without test-driven frames.

Pending model requests are checked against both field and observation before restoring or allocating an attempt. Switching to another observation requires explicitly returning to or cancelling the original pending request; the app never silently resends it under another observation. An in-flight context cannot change, and the send boundary rechecks its captured scope after storage access. Regression coverage confirms no new billable id is generated for a mismatched context, ambiguous retries preserve their original id, and approved current-version clarifications remain answerable. All 22 mobile tests pass. iOS outlined answers retain Cupertino buttons with a sage surface and visible rounded border.

Only the dedicated labelled retry action may resume a pending chat attempt. Generic workbench analysis/answer actions open the discussion without sending or allocating an id; the discussion shows the exact original pending message and explains a terminal retry may incur provider cost. Cancelling pending retry preserves newly typed text. History/weather evidence tiles now expose native tappable actions and button semantics. All 24 mobile tests pass, including explicit-retry and context-tile callback regressions. The synthetic native screenshot fixture uses rural coordinates 55.75/36.95.
