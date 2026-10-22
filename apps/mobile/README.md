# АГРОМАКС — Flutter

Android/iOS client. See [mobile setup](../../docs/mobile.md) for runtime configuration, offline behavior and verification limits.

## Real native integration test

With the local API and Supabase running (synthetic signup must return a session):

```sh
flutter test integration_test/native_backend_test.dart -d <ios-simulator-id> --dart-define=API_BASE_URL=http://localhost:8787
```

Every run creates a separate normal synthetic account and point-only field. It enters email/password/note through Flutter's test API, saves a valid synthetic PNG through the production durable-photo and outbox path, checks the actual authenticated server photo and observation, repeats sync to check deduplication, and closes/reopens native SQLite to verify cache/queue persistence. It clears the saved session before and after the run. It does not simulate camera/gallery permissions or claim an OS process-kill test. A history screenshot is saved as `agromax-native-real-history.png` in the simulator app's Documents directory. No real account data or server configuration is changed.

To export the genuine native history screenshot to the host (plain `flutter test` removes its simulator app container after completion):

```sh
flutter drive --driver=test_driver/native_backend_driver.dart --target=integration_test/native_backend_test.dart -d <ios-simulator-id> --dart-define=API_BASE_URL=http://localhost:8787
```

The host driver writes `build/native-evidence/agromax-native-real-history.png`.

Photo upload retries persist a UUID per durable local path in SQLite before the HTTP request. Multipart `operationId` lets the backend return the same photo after a lost response; uploaded photo ids and pending-path removal checkpoint together. The local path-to-operation map never enters observation JSON. Unit/SQLite tests include an accepted upload with its response lost followed by database reopen and a retry with the identical UUID.
