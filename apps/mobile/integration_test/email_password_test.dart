// Native UI against the real configured API, using a disposable synthetic account.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:integration_test/integration_test.dart';
import 'package:agromax/main.dart' as app;
import 'package:agromax/model.dart';
import 'package:agromax/storage.dart';
import 'native_backend_test.dart' show input, until;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native signup without email and subsequent password login',
    (tester) async {
      final email =
          'native-signup-${DateTime.now().microsecondsSinceEpoch}@example.test';
      const password = 'SyntheticOnly-Agromax-2026!';
      await AppModel.credentials.delete(key: 'session');
      await app.main();
      await tester.pump();
      await until(
        tester,
        () => input('Электронная почта').evaluate().isNotEmpty,
      );
      await tester.enterText(
        input('Имя для регистрации'),
        'Проверка регистрации iOS',
      );
      await tester.enterText(input('Электронная почта'), email);
      await tester.enterText(input('Пароль'), password);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.ensureVisible(find.text('Создать аккаунт'));
      await tester.tap(find.text('Создать аккаунт'));
      final container = ProviderScope.containerOf(
        tester.element(find.byType(app.Home)),
      );
      final model = container.read(modelProvider.notifier);
      await until(
        tester,
        () => model.session != null && !model.busy,
        reason: 'Signup should immediately open the farm: ${model.error}',
        timeout: const Duration(seconds: 150),
      );
      expect(model.session?['demo'], false);
      final farm = model.session!['farm']['id'];
      final user = model.session!['user']['id'];
      await model.logout();
      await tester.pump();
      await until(
        tester,
        () => input('Электронная почта').evaluate().isNotEmpty,
      );
      await tester.enterText(input('Электронная почта'), email);
      await tester.enterText(input('Пароль'), password);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.ensureVisible(find.text('Войти'));
      await tester.tap(find.text('Войти'));
      await until(
        tester,
        () => model.session != null && !model.busy,
        reason: 'Password login failed: ${model.error}',
      );
      expect(model.session!['farm']['id'], farm);
      expect(model.session!['user']['id'], user);
      await binding.takeScreenshot('agromax-email-password-native');
      final store = container.read(storeProvider);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await store.db.close();
      await AppModel.credentials.delete(key: 'session');
    },
    timeout: const Timeout(Duration(minutes: 4)),
  );
}
