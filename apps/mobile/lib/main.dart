import 'dart:async';
import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'ui/adaptive.dart';
import 'ui/field_map.dart';
import 'ui/workbench.dart';
import 'ui/reply_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'api.dart';
import 'chat_attempt.dart';
import 'model.dart';
import 'generated/api_routes.dart';
import 'storage.dart';
part 'ui/home_workbench.dart';
part 'ui/home_records.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await LocalStore.open();
  runApp(
    ProviderScope(
      overrides: [storeProvider.overrideWithValue(store)],
      child: const AgromaxApp(),
    ),
  );
}

String coordinateText(dynamic point) {
  if (point is! Map || point['lat'] is! num || point['lng'] is! num) {
    return 'Не указаны';
  }
  return '${(point['lat'] as num).toStringAsFixed(5)}, ${(point['lng'] as num).toStringAsFixed(5)}';
}

String observationDate(dynamic value) {
  final date = DateTime.tryParse(value.toString())?.toLocal();
  if (date == null) {
    return 'Дата не указана';
  }
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(date.day)}.${two(date.month)}.${date.year} · ${two(date.hour)}:${two(date.minute)}';
}

class AgromaxApp extends StatelessWidget {
  const AgromaxApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'АГРОМАКС',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: forest),
      scaffoldBackgroundColor: ivory,
      cupertinoOverrideTheme: const CupertinoThemeData(
        primaryColor: forest,
        scaffoldBackgroundColor: ivory,
      ),
      textTheme: const TextTheme(
        bodyMedium: TextStyle(
          fontSize: 16,
          height: 1.4,
          color: Color(0xff172b23),
        ),
      ),
      appBarTheme: const AppBarTheme(backgroundColor: Color(0xfff7f7ee)),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),
      cardTheme: const CardThemeData(color: Colors.white, elevation: 0),
    ),
    home: const Home(),
  );
}

class Home extends ConsumerStatefulWidget {
  const Home({super.key});
  @override
  ConsumerState<Home> createState() => _HomeState();
}

class _HomeState extends ConsumerState<Home> with WidgetsBindingObserver {
  final email = TextEditingController(),
      password = TextEditingController(),
      name = TextEditingController(),
      message = TextEditingController();
  int tab = 1;
  String? observationId;
  String? fieldId;
  String provider = 'deepseek';
  String? conversationId;
  Timer? timer;
  bool chatBusy = false;
  bool chatPreparing = false;
  Map<String, dynamic>? chatRetry;
  final List<Map<String, dynamic>> chat = [];
  void updateUI(VoidCallback action) => setState(action);
  AppModel get model => ref.read(modelProvider.notifier);
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(() async {
      await model.init();
      await model.recoverPhoto();
    });
    timer = Timer.periodic(const Duration(seconds: 30), (_) => model.sync());
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    email.dispose();
    password.dispose();
    name.dispose();
    message.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      model.sync();
    }
  }

  Future<void> act(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is ApiFailure
                  ? e.message
                  : 'Не удалось выполнить действие. Проверьте соединение и разрешения приложения.',
            ),
          ),
        );
      }
    }
  }

  List<dynamic> items(String key) => List<dynamic>.from(model.data[key] ?? []);
  String fieldName(dynamic id) =>
      items(
        'fields',
      ).where((f) => f['id'] == id).map((f) => f['name']).firstOrNull ??
      'Поле';
  Future<bool> confirm(String title, String body) async =>
      await adaptiveDialog<bool>(
        context: context,
        builder: (context) => NativeAlert(
          title: Text(title),
          content: Text(body),
          actions: [
            NativeButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена'),
            ),
            NativeButton(
              filled: true,
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Подтвердить'),
            ),
          ],
        ),
      ) ??
      false;
  @override
  Widget build(BuildContext context) {
    ref.watch(modelProvider);
    if (model.session == null) {
      return Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(24),
              children: [
                SvgPicture.asset('assets/logo.svg', height: 64),
                const SizedBox(height: 24),
                const Text(
                  'Ваш помощник в поле',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),
                NativeInput(
                  controller: name,
                  decoration: const InputDecoration(
                    labelText: 'Имя для регистрации',
                  ),
                ),
                const SizedBox(height: 12),
                NativeInput(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Электронная почта',
                  ),
                ),
                const SizedBox(height: 12),
                NativeInput(
                  controller: password,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Пароль'),
                ),
                if (model.error != null)
                  Text(model.error!, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 16),
                NativeButton(
                  filled: true,
                  onPressed: model.busy
                      ? null
                      : () => model.login(
                          'login',
                          email.text,
                          password.text,
                          name.text,
                        ),
                  child: const Text('Войти'),
                ),
                NativeButton(
                  onPressed: model.busy
                      ? null
                      : () => model.login(
                          'signup',
                          email.text,
                          password.text,
                          name.text,
                        ),
                  child: const Text('Создать аккаунт'),
                ),
                NativeButton(
                  outlined: true,
                  onPressed: model.busy
                      ? null
                      : () => model.login('demo', '', '', ''),
                  child: const Text('Попробовать демо'),
                ),
                const Text(
                  'Демо создаёт отдельное хозяйство. Требуется сервер.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }
    final fields = items('fields');
    fieldId = model.activeField ?? fieldId;
    observationId ??= model.activeObservation;
    if (!fields.any((f) => f['id'] == fieldId)) {
      fieldId = fields.firstOrNull?['id'];
    }
    return Scaffold(
      appBar: isIOS
          ? CupertinoNavigationBar(
              middle: SvgPicture.asset('assets/logo.svg', height: 30),
              backgroundColor: ivory,
            )
          : AppBar(title: SvgPicture.asset('assets/logo.svg', height: 32)),
      body: Column(
        children: [
          if (model.busy) const NativeSpinner(),
          if (model.session?['demo'] == true)
            const Material(
              color: Color(0xffe2ead5),
              child: ListTile(
                dense: true,
                leading: Icon(Icons.science_outlined),
                title: Text('Демо-хозяйство · контуры полей синтетические'),
              ),
            ),
          if (model.error != null)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Text(
                model.error!,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          if (fields.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xffd8dfd1)),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: NativeButton.icon(
                  onPressed: chatBusy ? null : selectFieldSheet,
                  icon: const Icon(
                    CupertinoIcons.leaf_arrow_circlepath,
                    color: forest,
                  ),
                  label: Text(
                    '${fields.firstWhere((f) => f['id'] == fieldId, orElse: () => fields.first)['name']} · ${fields.firstWhere((f) => f['id'] == fieldId, orElse: () => fields.first)['crop']}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: model.sync,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (fields.isEmpty)
                    const Text(
                      'Поля пока не загружены. Подключитесь к серверу и обновите.',
                    ),
                  if (tab == 0) ...fieldView(),
                  if (tab == 1) ...workbenchView(),
                  if (tab == 2) ...taskView(),
                  if (tab == 3) ...moreView(),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: isIOS
          ? CupertinoTabBar(
              currentIndex: tab,
              activeColor: forest,
              backgroundColor: ivory,
              onTap: (i) => setState(() => tab = i),
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(CupertinoIcons.leaf_arrow_circlepath),
                  label: 'Поле',
                ),
                BottomNavigationBarItem(
                  icon: Icon(CupertinoIcons.pencil_ellipsis_rectangle),
                  label: 'Осмотр',
                ),
                BottomNavigationBarItem(
                  icon: Icon(CupertinoIcons.check_mark_circled),
                  label: 'Задачи',
                ),
                BottomNavigationBarItem(
                  icon: Icon(CupertinoIcons.ellipsis_circle),
                  label: 'Ещё',
                ),
              ],
            )
          : NavigationBar(
              selectedIndex: tab,
              onDestinationSelected: (i) => setState(() => tab = i),
              destinations: const [
                NavigationDestination(icon: Icon(Icons.grass), label: 'Поле'),
                NavigationDestination(
                  icon: Icon(Icons.edit_note),
                  label: 'Осмотр',
                ),
                NavigationDestination(
                  icon: Icon(Icons.task_alt),
                  label: 'Задачи',
                ),
                NavigationDestination(
                  icon: Icon(Icons.more_horiz),
                  label: 'Ещё',
                ),
              ],
            ),
    );
  }

  List<Widget> chatView() {
    chatRetry ??= model.pendingChat;
    final messages = contextMessages;
    return [
      heading('Агрономический агент'),
      NativeButton.icon(
        onPressed: chatBusy ? null : providerSheet,
        icon: const Icon(CupertinoIcons.slider_horizontal_3),
        label: Text('Модель: ${provider == 'deepseek' ? 'DeepSeek' : 'MiMo'}'),
      ),
      const Text(
        'Ответы агента требуют проверки. Утверждение выполняется отдельно.',
      ),
      for (final m in messages)
        card(
          m['role'] == 'user' ? 'Вы' : 'Агент',
          m['text'] ?? '',
          actions: [if (m['reply'] != null) ...replyWidgets(m['reply'])],
        ),
      if (chatBusy) const NativeSpinner(),
      if (chatRetry != null) ...[
        heading('Незавершённый запрос'),
        SelectableText(chatRetry!['message'].toString()),
        Text(
          ChatAttempt.isTerminal(chatRetry!)
              ? 'Новая попытка отправит именно этот запрос с новым идентификатором. Провайдер может списать оплату за новый ответ.'
              : 'Повтор отправит именно этот запрос с прежним идентификатором. Новый текст ниже пока не отправляется.',
        ),
      ],
      NativeInput(
        controller: message,
        maxLines: 3,
        decoration: const InputDecoration(labelText: 'Спросите о поле'),
      ),
      NativeButton(
        filled: true,
        onPressed: chatBusy || fieldId == null
            ? null
            : () => sendChat(explicitRetry: chatRetry != null),
        child: Text(
          chatRetry == null
              ? 'Отправить'
              : ChatAttempt.isTerminal(chatRetry!)
              ? 'Новая попытка'
              : 'Повторить запрос',
        ),
      ),
      if (chatRetry != null && ChatAttempt.isTerminal(chatRetry!))
        const Text(
          'Предыдущая попытка завершилась ошибкой модели. Новая попытка создаст отдельный запрос; можно выбрать другого провайдера.',
        ),
      if (chatRetry != null)
        NativeButton(
          onPressed: () async {
            await model.store.set(
              'chat-pending:${model.account}:$fieldId',
              null,
            );
            model.pendingChat = null;
            if (mounted) {
              setState(() => chatRetry = null);
              model.changed();
            }
          },
          child: const Text('Отменить повтор и написать новый запрос'),
        ),
    ];
  }

  List<Widget> replyWidgets(Map rawReply) {
    final reply = currentReply(
      rawReply,
      items('observations'),
      contextObservationId: observationId,
    );
    return [
      Text('Модель: ${reply['model']} · ${reply['provider']}'),
      SourceDisclosure(sources: reply['sources'] ?? []),
      ...replyDecisionWidgets(reply),
      if (reply['artifact'] != null)
        ...artifactActions(reply['artifact'], reply['sources'] ?? []),
      if (reply['artifact']?['question'] != null &&
          reply['id'] == latestReply?['id'])
        ...questionWidgets(reply['artifact']['question']),
      if (reply['artifact']?['kind'] == 'observation' &&
          reply['artifact']['observationId'] == null &&
          reply['_artifactNotice'] == null)
        NativeButton(
          onPressed: () => act(() async {
            await model.editDraft('note', reply['artifact']['body']);
            setState(() => tab = 1);
          }),
          child: const Text('Открыть как черновик наблюдения'),
        ),
    ];
  }

  Future<void> sendChat({bool explicitRetry = false}) => act(() async {
    if (chatBusy || chatPreparing) return;
    chatPreparing = true;
    final requestField = fieldId;
    final requestObservation = observationId;
    final requestAccount = model.account;
    final retryKey = 'chat-pending:${model.account}:$fieldId';
    var restoringPending = false;
    try {
      final saved = await model.store.get(retryKey);
      if (fieldId != requestField ||
          observationId != requestObservation ||
          model.account != requestAccount) {
        return;
      }
      final pending = saved == null
          ? (chatRetry ?? model.pendingChat)
          : Map<String, dynamic>.from(saved);
      if (!ChatAttempt.matchesContext(
        pending,
        fieldId: fieldId,
        observationId: observationId,
      )) {
        if (mounted) await showPendingContext(pending!);
        return;
      }
      restoringPending = pending != null;
      chatRetry = pending == null ? null : Map<String, dynamic>.from(pending);
      if (pending != null && !explicitRetry) {
        model.changed();
        unawaited(openConversation());
        return;
      }
    } finally {
      chatPreparing = false;
    }
    if (chatRetry == null && message.text.trim().isEmpty) {
      return;
    }
    setState(() => chatBusy = true);
    model.changed();
    final history = items(
      'conversations',
    ).where((c) => c['fieldId'] == fieldId).toList();
    chatRetry ??= {
      'operationId': uuid.v4(),
      'fieldId': fieldId,
      'message': message.text,
      'provider': provider,
      if (observationId != null) 'observationId': observationId,
      if (conversationId != null ||
          model.conversationContexts[observationId ?? 'field'] != null ||
          (observationId == null && history.isNotEmpty))
        'conversationId':
            conversationId ??
            model.conversationContexts[observationId ?? 'field'] ??
            history.last['id'],
    };
    try {
      chatRetry = restoringPending
          ? ChatAttempt.prepareForContext(
              chatRetry!,
              fieldId: fieldId,
              observationId: observationId,
              explicitRetry: explicitRetry,
              newId: uuid.v4,
              provider: provider,
            )
          : ChatAttempt.prepare(chatRetry!, newId: uuid.v4, provider: provider);
      await model.store.set(retryKey, chatRetry);
      model.pendingChat = chatRetry;
      final result = await model.api.request(ApiRoutes.chat, chatRetry);
      await model.store.set(retryKey, null);
      model.pendingChat = null;
      conversationId = result['conversation']['id'];
      model.conversationContexts[chatRetry?['observationId'] ?? 'field'] =
          conversationId!;
      await model.store.set(
        'chat-contexts:${model.account}:$fieldId',
        model.conversationContexts,
      );
      chat.clear();
      chat.addAll(
        List<Map<String, dynamic>>.from(result['conversation']['messages']),
      );
      chatRetry = null;
      message.clear();
      await model.refresh();
    } catch (error) {
      if (chatRetry != null) {
        chatRetry = ChatAttempt.afterFailure(chatRetry!, error);
        model.pendingChat = chatRetry;
        await model.store.set(retryKey, chatRetry);
      }
      rethrow;
    } finally {
      if (mounted) {
        setState(() => chatBusy = false);
        model.changed();
      }
    }
  });
  List<Widget> queueView() => [
    heading('Очередь синхронизации'),
    const Text(
      'Фото отправляются перед наблюдением. Повтор запроса использует прежний идентификатор операции.',
    ),
    NativeButton.icon(
      filled: true,
      onPressed: model.busy ? null : model.sync,
      icon: const Icon(Icons.sync),
      label: const Text('Повторить синхронизацию'),
    ),
    for (final op in model.queue.reversed)
      card(
        {
              'local': 'На устройстве',
              'sending': 'Отправляется',
              'synced': 'Синхронизировано',
              'error': 'Ошибка',
              'conflict': 'Конфликт',
            }[op['status']] ??
            op['status'],
        '${op['type']}\n${op['payload']['note'] ?? op['payload']['outcome'] ?? op['payload']['id']}\n${op['error'] ?? ''}',
        actions: [
          if (op['status'] == 'conflict' && op['type'] == 'observation.upsert')
            NativeButton(
              onPressed: () => act(() async {
                if (await confirm(
                  'Открыть локальную версию?',
                  'Она заменит текущий черновик этого поля. Исходная запись останется в очереди; сохранение создаст связанное повторное наблюдение.',
                )) {
                  await model.restoreConflict(op);
                  setState(() => tab = 1);
                }
              }),
              child: const Text(
                'Открыть локальную версию как повторный осмотр',
              ),
            ),
          if (op['status'] == 'conflict')
            const Text(
              'Локальная версия сохранена. Обновите историю и создайте повторный осмотр с актуальными данными.',
            ),
        ],
      ),
    if (model.queue.isEmpty)
      const Text('Все изменения сохранены. Очередь пуста.'),
  ];
}
