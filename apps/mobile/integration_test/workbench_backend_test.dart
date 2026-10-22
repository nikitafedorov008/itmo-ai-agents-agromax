// Real native UI + backend + configured DeepSeek. No mocked model responses.
import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:agromax/api.dart';
import 'package:agromax/generated/api_routes.dart';
import 'package:agromax/main.dart' as app;
import 'package:agromax/model.dart';
import 'package:agromax/ui/adaptive.dart';
import 'native_backend_test.dart' as shared;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native workbench renders real model question and continues same observation',
    (tester) async {
      final suffix = DateTime.now().microsecondsSinceEpoch;
      final email = 'workbench-native-$suffix@example.test';
      const password = 'WorkbenchFixture-2026-test';
      final session = await Api('').request(ApiRoutes.signup, {
        'email': email,
        'password': password,
        'name': 'Синтетический тест workbench',
      });
      expect(session['accessToken'], isA<String>());
      final api = Api(session['accessToken']);
      final field = await api.request(ApiRoutes.createField, {
        'operationId': uuid.v4(),
        'confirmed': true,
        'name': 'Осмотр пшеницы $suffix',
        'crop': 'Озимая пшеница',
        'areaHa': 12.5,
        'center': {'lat': 55.75, 'lng': 37.61},
        'boundary': [
          {'lat': 55.749, 'lng': 37.608},
          {'lat': 55.752, 'lng': 37.608},
          {'lat': 55.752, 'lng': 37.613},
          {'lat': 55.749, 'lng': 37.613},
        ],
      });
      final observationId = uuid.v4();
      const note =
          'Синтетическое наблюдение: желтеют края нижних листьев пшеницы. Срок появления признаков пока неизвестен. Диагноз не установлен.';
      await api.request(ApiRoutes.saveObservation, {
        'operationId': uuid.v4(),
        'id': observationId,
        'fieldId': field['id'],
        'note': note,
        'extent': 'Край поля',
        'location': {'lat': 55.7505, 'lng': 37.6105},
        'photoIds': <String>[],
      });
      await AppModel.credentials.delete(key: 'session');
      await app.main();
      await tester.pump();
      await shared.until(
        tester,
        () => shared.input('Электронная почта').evaluate().isNotEmpty,
      );
      await tester.enterText(shared.input('Электронная почта'), email);
      await tester.enterText(shared.input('Пароль'), password);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.ensureVisible(find.text('Войти'));
      await tester.tap(find.text('Войти'));
      await shared.until(
        tester,
        () => find.byType(CupertinoTabBar).evaluate().isNotEmpty,
        reason: 'Native iOS navigation did not render',
      );
      expect(find.byType(CupertinoNavigationBar), findsOneWidget);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(app.Home)),
      );
      final model = container.read(modelProvider.notifier);
      await shared.until(
        tester,
        () =>
            !model.busy &&
            (model.data['observations'] as List? ?? []).any(
              (o) => o['id'] == observationId,
            ),
      );
      expect(model.session?['demo'], false);
      expect(model.activeField, field['id']);
      expect(
        (model.data['providers'] as List).any(
          (p) => p['id'] == 'deepseek' && p['configured'] == true,
        ),
        true,
        reason: 'A real configured DeepSeek provider is required',
      );
      await tester.tap(
        find.descendant(
          of: find.byType(CupertinoTabBar),
          matching: find.text('Осмотр'),
        ),
      );
      await tester.pump();
      Finder mainScroll() => find
          .descendant(
            of: find.byType(RefreshIndicator),
            matching: find.byType(Scrollable),
          )
          .first;
      // A real local draft must survive both chat turns unchanged.
      await tester.scrollUntilVisible(
        shared.input('Что вы заметили?'),
        200,
        scrollable: mainScroll(),
        maxScrolls: 30,
      );
      const localDraft =
          'Локальный черновик: уточнить признаки при повторном осмотре.';
      await tester.enterText(shared.input('Что вы заметили?'), localDraft);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      final draftBefore = jsonEncode(model.draft);
      await tester.scrollUntilVisible(
        find.text('Обсудить свободно'),
        -180,
        scrollable: mainScroll(),
        maxScrolls: 30,
      );
      await tester.tap(find.text('Обсудить свободно'));
      await tester.pump(const Duration(milliseconds: 500));
      final conversationScroll = find
          .ancestor(
            of: shared.input('Спросите о поле'),
            matching: find.byType(Scrollable),
          )
          .first;
      await tester.scrollUntilVisible(
        shared.input('Спросите о поле'),
        120,
        scrollable: conversationScroll,
      );
      await tester.enterText(
        shared.input('Спросите о поле'),
        'Для выбранного наблюдения пока не делай вывод о причине и не предлагай задачу. Сначала задай один уточняющий вопрос о том, когда появились признаки. Верни его в artifact.question с тремя короткими вариантами ответа в options и allowCustom=true. Используй kind=clarification и stage=context. Покажи только фактически прочитанный контекст, без диагноза и без анализа фото.',
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.ensureVisible(find.text('Отправить'));
      await tester.tap(find.text('Отправить'));
      List<dynamic> conversations() =>
          (model.data['conversations'] as List? ?? [])
              .where((c) => c['fieldId'] == field['id'])
              .toList();
      Map? lastReply() => conversations().isEmpty
          ? null
          : (conversations().single['messages'] as List).reversed
                .where((m) => m['reply'] != null)
                .firstOrNull?['reply'];
      await shared.until(
        tester,
        () => lastReply() != null && model.pendingChat == null,
        reason: 'Real first model turn failed: ${model.error}',
        timeout: const Duration(seconds: 120),
      );
      final firstConversation = conversations().single;
      final firstReply = Map<String, dynamic>.from(lastReply()!);
      final question = firstReply['artifact']?['question'];
      expect(
        question,
        isA<Map>(),
        reason:
            'Actual DeepSeek reply must contain a structured clarification: ${firstReply['text']}',
      );
      final prompt = question['prompt'] as String;
      final options = List<String>.from(question['options']);
      expect(options, isNotEmpty);
      expect(firstReply['tools'], contains('field_history'));
      expect(firstReply['provider'], 'deepseek');
      expect(
        model.conversationContexts[observationId],
        firstConversation['id'],
      );
      expect(jsonEncode(model.draft), draftBefore);
      await tester.tap(find.text('Готово').last);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.scrollUntilVisible(
        find.text(prompt),
        180,
        scrollable: mainScroll(),
        maxScrolls: 30,
      );
      expect(find.text(prompt), findsOneWidget);
      expect(find.widgetWithText(NativeButton, options.first), findsOneWidget);
      expect(find.byType(CupertinoTabBar), findsOneWidget);
      await tester.ensureVisible(find.text(options.last));
    await tester.pump(const Duration(milliseconds: 300));
    await binding.takeScreenshot('agromax-native-workbench-real-question');
      final answer = options.first;
      await tester.ensureVisible(find.text(answer));
      await tester.tap(find.text(answer));
      final originalMessageCount =
          (firstConversation['messages'] as List).length;
      await shared.until(
        tester,
        () =>
            conversations().length == 1 &&
            (conversations().single['messages'] as List).length >=
                originalMessageCount + 2 &&
            model.pendingChat == null,
        reason:
            'Actual option did not continue the same server conversation: ${model.error}',
        timeout: const Duration(seconds: 120),
      );
      final continued = conversations().single;
      expect(continued['id'], firstConversation['id']);
      expect(
        (continued['messages'] as List)
            .where((m) => m['role'] == 'user' && m['text'] == answer)
            .length,
        1,
      );
      expect(
        model.conversationContexts[observationId],
        firstConversation['id'],
      );
      expect(model.activeObservation, observationId);
      expect(jsonEncode(model.draft), draftBefore);
      expect(await model.store.get(model.draftKey), model.draft);
      final remote = await api.request(ApiRoutes.bootstrap);
      final actualObservation = (remote['observations'] as List).singleWhere(
        (o) => o['id'] == observationId,
      );
      expect(actualObservation['note'], note);
      expect(actualObservation['status'], 'draft');
      expect(
        remote['tasks'],
        isEmpty,
        reason: 'Chat option must not silently approve or create a task',
      );
      await binding.takeScreenshot('agromax-native-workbench-real-followup');
      // Also capture the botanical illustration + actual map and native chrome.
      final top = tester.state<ScrollableState>(mainScroll());
      top.position.jumpTo(0);
      await tester.pump(const Duration(seconds: 1));
      await binding.takeScreenshot('agromax-native-workbench-top');
      binding.reportData ??= {};
      binding.reportData!['workbenchProof'] = {
        'fieldId': field['id'],
        'observationId': observationId,
        'conversationId': firstConversation['id'],
        'provider': firstReply['provider'],
        'model': firstReply['model'],
        'question': prompt,
        'actualOptions': options,
        'selectedAnswer': answer,
        'tools': firstReply['tools'],
        'messageCountBefore': originalMessageCount,
        'messageCountAfter': (continued['messages'] as List).length,
        'draftUnchanged': true,
        'serverObservationStillDraft': true,
        'tasksCreated': 0,
      };
      // Leave credentials and the durable local draft for normal app relaunch.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
