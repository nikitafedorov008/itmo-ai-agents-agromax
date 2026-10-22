// Real backend/native integration. Creates isolated synthetic records; no mocks.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:integration_test/integration_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:agromax/api.dart';
import 'package:agromax/generated/api_routes.dart';
import 'package:agromax/main.dart' as app;
import 'package:agromax/model.dart';
import 'package:agromax/storage.dart';

Future<void> until(
  WidgetTester tester,
  bool Function() ready, {
  String reason = 'Expected native UI state',
  Duration timeout = const Duration(seconds: 60),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!ready()) {
    if (DateTime.now().isAfter(deadline)) {
      fail(reason);
    }
    await tester.pump(const Duration(milliseconds: 200));
  }
  await tester.pump(const Duration(milliseconds: 200));
}

Finder input(String label) => find.byWidgetPredicate(
  (w) =>
      (w is TextField && w.decoration?.labelText == label) ||
      (w is CupertinoTextField && w.placeholder == label),
);
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'normal account login, native photo outbox, server history and SQLite reopen',
    (tester) async {
      final suffix = DateTime.now().microsecondsSinceEpoch;
      final email = 'native-$suffix@example.test';
      const password = 'NativeFixture-2026-test';
      final session = await Api('').request(ApiRoutes.signup, {
        'email': email,
        'password': password,
        'name': 'Синтетический iOS тест',
      });
      expect(
        session['accessToken'],
        isA<String>(),
        reason:
            'Local Supabase must allow immediately confirmed synthetic signup',
      );
      expect(session['demo'], false);
      final api = Api(session['accessToken']);
      final field = await api.request(ApiRoutes.createField, {
        'operationId': uuid.v4(),
        'confirmed': true,
        'name': 'Тестовое мобильное поле $suffix',
        'crop': 'Пшеница',
        'areaHa': 1.25,
        'center': {'lat': 55.75, 'lng': 37.61},
        'boundary': <dynamic>[],
      });
      await AppModel.credentials.delete(key: 'session');
      await app.main();
      await tester.pump();
      await until(
        tester,
        () => input('Электронная почта').evaluate().isNotEmpty,
        reason: 'Login form did not open',
      );
      await tester.enterText(input('Электронная почта'), email);
      await tester.enterText(input('Пароль'), password);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.ensureVisible(find.text('Войти'));
      await tester.tap(find.text('Войти'));
      await until(
        tester,
        () => find
            .byWidgetPredicate(
              (w) => w is NavigationBar || w is CupertinoTabBar,
            )
            .evaluate()
            .isNotEmpty,
        reason: 'Real normal-account UI login failed',
      );
      final container = ProviderScope.containerOf(
        tester.element(find.byType(app.Home)),
      );
      final model = container.read(modelProvider.notifier);
      await until(
        tester,
        () => !model.busy && (model.data['fields'] as List? ?? []).isNotEmpty,
        reason: 'Bootstrap after login did not load',
      );
      expect(model.session?['demo'], false);
      expect(model.activeField, field['id']);
      final account = model.account;
      final note =
          'Синтетический осмотр iOS $suffix: тестовая фотография, не диагноз';
      await tester.tap(find.text('Осмотр'));
      await tester.pump();
      final noteInput = input('Что вы заметили?');
      await tester.scrollUntilVisible(
        noteInput,
        200,
        scrollable: find
            .descendant(
              of: find.byType(RefreshIndicator),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.ensureVisible(noteInput);
      await tester.pump();
      await tester.enterText(noteInput, note);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      // Use a valid generated PNG rather than pretending to exercise the camera.
      final temp = await getTemporaryDirectory();
      final picked = File('${temp.path}/fixture-$suffix.png');
      await picked.writeAsBytes(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNw6XD5DwAENAIQTV6YLQAAAABJRU5ErkJggg==',
        ),
      );
      await model.preservePhoto(XFile(picked.path));
      final durable = List<String>.from(model.draft['localPhotos']).single;
      expect(
        durable.startsWith((await getApplicationDocumentsDirectory()).path),
        true,
      );
      await picked.delete();
      expect(await File(durable).exists(), true);
      await tester.pump();
      final save = find.text('Сохранить и поставить в очередь');
      await tester.scrollUntilVisible(
        save,
        200,
        scrollable: find
            .descendant(
              of: find.byType(RefreshIndicator),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      await tester.tap(save);
      await until(
        tester,
        () =>
            model.queue.isNotEmpty &&
            model.queue.every((q) => q['status'] == 'synced'),
        reason: 'Actual photo/observation outbox did not sync: ${model.error}',
        timeout: const Duration(seconds: 90),
      );
      final synced = model.queue.single;
      final opId = synced['operationId'];
      final bootstrap = await api.request(ApiRoutes.bootstrap);
      final observation = (bootstrap['observations'] as List).singleWhere(
        (o) => o['note'] == note,
      );
      expect(observation['fieldId'], field['id']);
      expect(observation['status'], 'draft');
      final photoId = (observation['photoIds'] as List).single as String;
      final photo = await http.get(
        Uri.parse(apiBase).resolve(ApiRoutes.photo(photoId)),
        headers: {'Authorization': 'Bearer ${session['accessToken']}'},
      );
      expect(photo.statusCode, 200);
      expect(photo.headers['content-type'], contains('image/png'));
      expect(photo.bodyBytes.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
      await model.sync();
      final repeated = await api.request(ApiRoutes.bootstrap);
      expect(
        (repeated['observations'] as List)
            .where((o) => o['note'] == note)
            .length,
        1,
        reason: 'Retry must not duplicate observation',
      );
      await tester.tap(
        find.descendant(
          of: find.byWidgetPredicate(
            (w) => w is NavigationBar || w is CupertinoTabBar,
          ),
          matching: find.text('Поле'),
        ),
      );
      await tester.pump();
      await tester.scrollUntilVisible(
        find.text('История поля'),
        -200,
        scrollable: find
            .descendant(
              of: find.byType(RefreshIndicator),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      final screenshot = await binding.takeScreenshot(
        'agromax-native-real-history',
      );
      await File(
        '${(await getApplicationDocumentsDirectory()).path}/agromax-native-real-history.png',
      ).writeAsBytes(screenshot);
      // Dispose UI/timer before closing and reopening the real native SQLite DB.
      final store = container.read(storeProvider);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await store.db.close();
      final reopened = await LocalStore.open();
      final persisted = (await reopened.queue(account)).single;
      expect(persisted['operationId'], opId);
      expect(persisted['status'], 'synced');
      expect(persisted['payload']['photoIds'], [photoId]);
      expect(
        (await reopened.get(
          'cache:$account',
        ))['observations'].any((o) => o['id'] == observation['id']),
        true,
      );
      expect(await reopened.get('draft:$account:${field['id']}'), isEmpty);
      await reopened.db.close();
      await AppModel.credentials.delete(key: 'session');
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
