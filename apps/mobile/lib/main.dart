import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';
import 'api.dart';
import 'model.dart';
import 'generated/api_routes.dart';
import 'storage.dart';

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

class AgromaxApp extends StatelessWidget {
  const AgromaxApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'АГРОМАКС',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff346540)),
      scaffoldBackgroundColor: const Color(0xfff7f7ee),
      appBarTheme: const AppBarTheme(backgroundColor: Color(0xfff7f7ee)),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
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
  int tab = 0;
  String? fieldId;
  String provider = 'deepseek';
  String? conversationId;
  Timer? timer;
  bool chatBusy = false;
  Map<String, dynamic>? chatRetry;
  final List<Map<String, dynamic>> chat = [];
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toString())));
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
      await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Отмена'),
            ),
            FilledButton(
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
                TextField(
                  controller: name,
                  decoration: const InputDecoration(
                    labelText: 'Имя для регистрации',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Электронная почта',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: password,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Пароль'),
                ),
                if (model.error != null)
                  Text(model.error!, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 16),
                FilledButton(
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
                TextButton(
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
                OutlinedButton(
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
    if (!fields.any((f) => f['id'] == fieldId)) {
      fieldId = fields.firstOrNull?['id'];
    }
    return Scaffold(
      appBar: AppBar(
        title: SvgPicture.asset('assets/logo.svg', height: 32),
        actions: [
          IconButton(
            tooltip: 'Синхронизировать',
            onPressed: model.busy ? null : () => model.sync(),
            icon: const Icon(Icons.sync),
          ),
          IconButton(
            tooltip: 'Выйти',
            onPressed: () async {
              if (await confirm(
                'Выйти?',
                'Черновики и очередь останутся в аккаунте на этом устройстве.',
              )) {
                chat.clear();
                conversationId = null;
                await model.logout();
              }
            },
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: Column(
        children: [
          if (model.busy) const LinearProgressIndicator(),
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: DropdownButtonFormField<String>(
                initialValue: fieldId,
                decoration: const InputDecoration(labelText: 'Поле'),
                items: fields
                    .map(
                      (f) => DropdownMenuItem<String>(
                        value: f['id'],
                        child: Text(
                          '${f['name']} · ${f['crop']} · ${f['areaHa']} га',
                        ),
                      ),
                    )
                    .toList(),
                onChanged: chatBusy
                    ? null
                    : (v) async {
                        if (v == null) {
                          return;
                        }
                        await model.selectField(v);
                        if (!mounted) {
                          return;
                        }
                        setState(() {
                          fieldId = v;
                          chat.clear();
                          conversationId = null;
                          chatRetry = null;
                        });
                      },
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
                  if (tab == 1) ...observationView(),
                  if (tab == 2) ...taskView(),
                  if (tab == 3) ...chatView(),
                  if (tab == 4) ...queueView(),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.grass), label: 'Поле'),
          NavigationDestination(icon: Icon(Icons.edit_note), label: 'Осмотр'),
          NavigationDestination(icon: Icon(Icons.task_alt), label: 'Задачи'),
          NavigationDestination(
            icon: Icon(Icons.forum_outlined),
            label: 'Агент',
          ),
          NavigationDestination(
            icon: Icon(Icons.cloud_upload_outlined),
            label: 'Очередь',
          ),
        ],
      ),
    );
  }

  Future<void> createField() async {
    final pending = await model.store.get('field-create:${model.account}');
    if (!mounted) {
      return;
    }
    if (pending != null) {
      if (await confirm('Повторить создание поля?', pending['name'])) {
        await act(() async {
          final field = await model.api.request(
            ApiRoutes.createField,
            Map<String, dynamic>.from(pending),
          );
          await model.store.set('field-create:${model.account}', null);
          await model.refresh();
          await model.selectField(field['id']);
        });
      }
      return;
    }
    final values = List.generate(5, (_) => TextEditingController());
    final labels = [
      'Название поля',
      'Культура',
      'Площадь, га',
      'Широта центра',
      'Долгота центра',
    ];
    final save = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Новое поле'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Поле будет отмечено точкой. Контур можно уточнить позднее.',
              ),
              for (var i = 0; i < values.length; i++)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: TextField(
                    controller: values[i],
                    keyboardType: i >= 2
                        ? const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: true,
                          )
                        : TextInputType.text,
                    decoration: InputDecoration(labelText: labels[i]),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Создать'),
          ),
        ],
      ),
    );
    final text = values.map((v) => v.text.trim()).toList();
    if (save != true) {
      return;
    }
    await act(() async {
      final area = double.tryParse(text[2].replaceAll(',', '.'));
      final lat = double.tryParse(text[3].replaceAll(',', '.'));
      final lng = double.tryParse(text[4].replaceAll(',', '.'));
      if (text[0].isEmpty ||
          text[1].isEmpty ||
          area == null ||
          area <= 0 ||
          lat == null ||
          lat.abs() > 90 ||
          lng == null ||
          lng.abs() > 180) {
        throw Exception(
          'Заполните название, культуру, положительную площадь и корректные координаты.',
        );
      }
      final payload = <String, dynamic>{
        'operationId': uuid.v4(),
        'confirmed': true,
        'name': text[0],
        'crop': text[1],
        'areaHa': area,
        'center': {'lat': lat, 'lng': lng},
        'boundary': <dynamic>[],
      };
      await model.store.set('field-create:${model.account}', payload);
      final field = await model.api.request(ApiRoutes.createField, payload);
      await model.store.set('field-create:${model.account}', null);
      await model.refresh();
      await model.selectField(field['id']);
    });
  }

  Widget heading(String text) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 12),
    child: Text(
      text,
      style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
    ),
  );
  Widget card(String title, String body, {List<Widget> actions = const []}) =>
      Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
              const SizedBox(height: 8),
              SelectableText(body),
              ...actions,
            ],
          ),
        ),
      );
  List<Widget> fieldView() => [
    heading('История поля'),
    if (model.session?['user']['role'] == 'chief')
      OutlinedButton.icon(
        onPressed: createField,
        icon: const Icon(Icons.add_location_alt_outlined),
        label: const Text('Добавить поле'),
      ),
    if (fieldId != null)
      Text(
        'Координаты: ${items('fields').where((f) => f['id'] == fieldId).firstOrNull?['center']}',
      ),
    OutlinedButton.icon(
      onPressed: fieldId == null
          ? null
          : () => act(() async {
              final weather = await model.api.request(
                ApiRoutes.weather(fieldId!),
              );
              if (mounted) {
                await showDialog<void>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: const Text('Погода'),
                    content: Text(
                      '${weather['source']}\n${(weather['days'] as List).map((d) => '${d['date']}: ${d['minC']}…${d['maxC']} °C, ${d['rainMm']} мм').join('\n')}',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(c),
                        child: const Text('Закрыть'),
                      ),
                    ],
                  ),
                );
              }
            }),
      icon: const Icon(Icons.cloud_outlined),
      label: const Text('Погода из API'),
    ),
    for (final o in items('observations').where((o) => o['fieldId'] == fieldId))
      card(
        o['status'] == 'approved' ? 'Рекомендация утверждена' : 'Наблюдение',
        '${o['note']}\n${o['createdAt']}\nФото: ${(o['photoIds'] as List).length}',
        actions: [
          for (final id in o['photoIds'] as List)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Image.network(
                Uri.parse(apiBase).resolve(ApiRoutes.photo(id)).toString(),
                headers: {
                  'Authorization': 'Bearer ${model.session?['accessToken']}',
                },
                height: 180,
                errorBuilder: (c, e, s) =>
                    const Text('Фото недоступно без связи'),
              ),
            ),
          if (o['status'] == 'draft')
            TextButton(
              onPressed: () => approve(o),
              child: const Text('Проверить и утвердить'),
            ),
          TextButton(
            onPressed: () => act(() async {
              await model.editDraft('parentObservationId', o['id']);
              await model.editDraft('note', 'Повторный осмотр: ');
              setState(() => tab = 1);
            }),
            child: const Text('Повторный осмотр'),
          ),
        ],
      ),
    if (items('observations').where((o) => o['fieldId'] == fieldId).isEmpty)
      const Text('Наблюдений пока нет.'),
    heading('Уведомления'),
    for (final n in items('notifications'))
      card(
        n['title'],
        n['body'],
        actions: [
          if (n['read'] != true)
            TextButton(
              onPressed: () => act(() async {
                await model.api.request(
                  ApiRoutes.readNotification(n['id']),
                  {},
                );
                await model.refresh();
              }),
              child: const Text('Прочитано'),
            ),
        ],
      ),
  ];
  Future<void> approve(Map o, [Map? proposedTask]) async {
    if (!await confirm(
      'Утвердить рекомендацию?',
      '${o['note'] ?? o['body'] ?? ''}\n${proposedTask == null ? 'Запись станет неизменяемой.' : 'Будет создана задача: ${proposedTask['title']}'}',
    )) {
      return;
    }
    await act(() async {
      await model.enqueue('observation.approve', {
        'id': o['id'],
        'version': o['version'],
        'confirmed': true,
        'task': ?proposedTask,
      });
      await model.sync();
    });
  }

  List<Widget> observationView() => [
    heading('Новое наблюдение'),
    const Text('Черновик сохраняется на устройстве по мере ввода.'),
    const SizedBox(height: 16),
    TextFormField(
      key: ValueKey('note:${model.draft['parentObservationId']}'),
      initialValue: model.draft['note'],
      maxLines: 4,
      decoration: const InputDecoration(labelText: 'Что вы заметили?'),
      onChanged: (v) => model.editDraft('note', v),
    ),
    const SizedBox(height: 12),
    TextFormField(
      initialValue: model.draft['extent'],
      decoration: const InputDecoration(labelText: 'Масштаб / участок'),
      onChanged: (v) => model.editDraft('extent', v),
    ),
    Wrap(
      spacing: 8,
      children: [
        TextButton.icon(
          onPressed: () => pick(ImageSource.camera),
          icon: const Icon(Icons.camera_alt),
          label: const Text('Камера'),
        ),
        TextButton.icon(
          onPressed: () => pick(ImageSource.gallery),
          icon: const Icon(Icons.photo_library),
          label: const Text('Галерея'),
        ),
        TextButton.icon(
          onPressed: locate,
          icon: const Icon(Icons.my_location),
          label: const Text('Геопозиция'),
        ),
      ],
    ),
    if (model.draft['location'] != null)
      Text('Координаты: ${model.draft['location']}'),
    for (final photo in List<String>.from(model.draft['localPhotos'] ?? []))
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Image.file(File(photo), height: 160, fit: BoxFit.cover),
      ),
    if (model.draft['parentObservationId'] != null)
      const Text('Будет создано связанное повторное наблюдение.'),
    FilledButton(
      onPressed: fieldId == null
          ? null
          : () => act(() async {
              await model.saveDraft(fieldId!);
              if (mounted) {
                setState(() => tab = 4);
              }
            }),
      child: const Text('Сохранить и поставить в очередь'),
    ),
  ];
  Future<void> pick(ImageSource source) => act(() async {
    final file = await ImagePicker().pickImage(
      source: source,
      imageQuality: 85,
    );
    if (file != null) {
      await model.preservePhoto(file);
    }
  });
  Future<void> locate() => act(() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw Exception('Включите геолокацию в настройках устройства');
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever ||
        permission == LocationPermission.denied) {
      throw Exception(
        'Нет разрешения геопозиции. Разрешите доступ в настройках приложения.',
      );
    }
    final pos = await Geolocator.getCurrentPosition();
    await model.editDraft('location', {
      'lat': pos.latitude,
      'lng': pos.longitude,
    });
  });
  List<Widget> taskView() => [
    heading('Задачи хозяйства'),
    for (final task in items('tasks').where((t) => t['fieldId'] == fieldId))
      card(
        task['title'],
        '${fieldName(task['fieldId'])}\nСрок: ${task['dueAt']}\n${task['status'] == 'done' ? 'Выполнена: ${task['outcome']}' : 'Открыта'}',
        actions: [
          if (task['status'] == 'open')
            TextButton(
              onPressed: () => complete(task),
              child: const Text('Отметить выполнение'),
            ),
        ],
      ),
    if (items('tasks').isEmpty)
      const Text('Пока нет задач. Утвердите предложение агента с задачей.'),
  ];
  Future<void> complete(Map task) async {
    final controller = TextEditingController();
    final outcome = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Результат выполнения'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Что сделано / замечено?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, controller.text),
            child: const Text('Продолжить'),
          ),
        ],
      ),
    );
    if (outcome == null || outcome.trim().isEmpty) {
      return;
    }
    if (!await confirm('Завершить задачу?', outcome)) {
      return;
    }
    await act(() async {
      await model.enqueue('task.complete', {
        'id': task['id'],
        'version': task['version'],
        'confirmed': true,
        'outcome': outcome,
      });
      await model.sync();
    });
  }

  List<Widget> chatView() {
    chatRetry ??= model.pendingChat;
    final history = items(
      'conversations',
    ).where((c) => c['fieldId'] == fieldId).toList();
    final messages = chat.isEmpty
        ? (history.isEmpty ? <dynamic>[] : history.last['messages'] as List)
        : chat;
    return [
      heading('Агрономический агент'),
      DropdownButton<String>(
        value: provider,
        items: const [
          DropdownMenuItem(value: 'deepseek', child: Text('DeepSeek')),
          DropdownMenuItem(value: 'mimo', child: Text('MiMo')),
        ],
        onChanged: (v) => setState(() => provider = v!),
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
      if (chatBusy) const LinearProgressIndicator(),
      TextField(
        controller: message,
        maxLines: 3,
        decoration: const InputDecoration(labelText: 'Спросите о поле'),
      ),
      FilledButton(
        onPressed: chatBusy || fieldId == null ? null : sendChat,
        child: Text(chatRetry == null ? 'Отправить' : 'Повторить запрос'),
      ),
      if (chatRetry != null)
        TextButton(
          onPressed: () async {
            await model.store.set(
              'chat-pending:${model.account}:$fieldId',
              null,
            );
            model.pendingChat = null;
            if (mounted) {
              setState(() => chatRetry = null);
            }
          },
          child: const Text('Отменить повтор и написать новый запрос'),
        ),
    ];
  }

  List<Widget> replyWidgets(Map reply) => [
    Text('Модель: ${reply['model']} · ${reply['provider']}'),
    for (final source in reply['sources'] ?? [])
      SelectableText(
        '${source['title']}\n${source['url']}\n${source['excerpt']}',
      ),
    if (reply['artifact'] != null)
      card(
        reply['artifact']['title'],
        reply['artifact']['body'],
        actions: [
          if (reply['artifact']['kind'] == 'observation' &&
              reply['artifact']['observationId'] == null)
            TextButton(
              onPressed: () => act(() async {
                await model.editDraft('note', reply['artifact']['body']);
                setState(() => tab = 1);
              }),
              child: const Text('Открыть как черновик наблюдения'),
            ),
          if (reply['artifact']['observationId'] != null &&
              reply['artifact']['observationVersion'] != null)
            TextButton(
              onPressed: () => approve({
                'id': reply['artifact']['observationId'],
                'version': reply['artifact']['observationVersion'],
                'body': reply['artifact']['body'],
              }, reply['artifact']['proposedTask']),
              child: const Text('Проверить и утвердить'),
            ),
        ],
      ),
  ];
  Future<void> sendChat() => act(() async {
    if (chatRetry == null && message.text.trim().isEmpty) {
      return;
    }
    setState(() => chatBusy = true);
    final history = items(
      'conversations',
    ).where((c) => c['fieldId'] == fieldId).toList();
    chatRetry ??= {
      'operationId': uuid.v4(),
      'fieldId': fieldId,
      'message': message.text,
      'provider': provider,
      if (conversationId != null || history.isNotEmpty)
        'conversationId': conversationId ?? history.last['id'],
    };
    try {
      final retryKey = 'chat-pending:${model.account}:$fieldId';
      final saved = await model.store.get(retryKey);
      if (saved != null) {
        chatRetry = Map<String, dynamic>.from(saved);
      }
      await model.store.set(retryKey, chatRetry);
      model.pendingChat = chatRetry;
      final result = await model.api.request(ApiRoutes.chat, chatRetry);
      await model.store.set(retryKey, null);
      model.pendingChat = null;
      conversationId = result['conversation']['id'];
      chat.clear();
      chat.addAll(
        List<Map<String, dynamic>>.from(result['conversation']['messages']),
      );
      chatRetry = null;
      message.clear();
      await model.refresh();
    } finally {
      if (mounted) {
        setState(() => chatBusy = false);
      }
    }
  });
  List<Widget> queueView() => [
    heading('Очередь синхронизации'),
    const Text(
      'Фото отправляются перед наблюдением. Повтор запроса использует прежний идентификатор операции.',
    ),
    FilledButton.icon(
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
