part of '../main.dart';

extension _Records on _HomeState {
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
    final save = await adaptiveDialog<bool>(
      context: context,
      builder: (c) => NativeAlert(
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
                  child: NativeInput(
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
          NativeButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Отмена'),
          ),
          NativeButton(
            filled: true,
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
      NativeButton.icon(
        outlined: true,
        onPressed: createField,
        icon: const Icon(Icons.add_location_alt_outlined),
        label: const Text('Добавить поле'),
      ),
    if (fieldId != null)
      Text(
        'Координаты: ${coordinateText(items('fields').where((f) => f['id'] == fieldId).firstOrNull?['center'])}',
      ),
    NativeButton.icon(
      outlined: true,
      onPressed: fieldId == null
          ? null
          : () => act(() async {
              final weather = await model.api.request(
                ApiRoutes.weather(fieldId!),
              );
              if (mounted) {
                await adaptiveDialog<void>(
                  context: context,
                  builder: (c) => NativeAlert(
                    title: const Text('Погода'),
                    content: Text(
                      '${weather['source']}\n${(weather['days'] as List).map((d) => '${d['date']}: ${d['minC']}…${d['maxC']} °C, ${d['rainMm']} мм').join('\n')}',
                    ),
                    actions: [
                      NativeButton(
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
        '${o['note']}\n${observationDate(o['createdAt'])}\nФото: ${(o['photoIds'] as List).length}',
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
          NativeButton.icon(
            onPressed: () {
              observationId = o['id'];
              conversationId = null;
              chat.clear();
              openConversation();
            },
            icon: const Icon(CupertinoIcons.chat_bubble_2),
            label: const Text('Обсудить наблюдение'),
          ),
          if (o['status'] == 'draft')
            NativeButton(
              onPressed: () => approve(o),
              child: const Text('Проверить и утвердить'),
            ),
          NativeButton(
            onPressed: () => act(() async {
              await model.editDraft('parentObservationId', o['id']);
              await model.editDraft('note', 'Повторный осмотр: ');
              updateUI(() => tab = 1);
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
            NativeButton(
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
    if (proposedTask != null) {
      final due = await taskDate(
        DateTime.tryParse(proposedTask['dueAt'].toString()) ??
            DateTime.now().add(const Duration(days: 1)),
      );
      if (due == null) return;
      proposedTask = {...proposedTask, 'dueAt': due.toUtc().toIso8601String()};
    }
    if (!await confirm(
      'Утвердить рекомендацию?',
      '${o['note'] ?? o['body'] ?? ''}\n${proposedTask == null ? 'Запись станет неизменяемой.' : 'Будет создана задача: ${proposedTask['title']} · ${observationDate(proposedTask['dueAt'])}'}',
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
    NativeInput(
      key: ValueKey(
        'note:${model.account}:$fieldId:${model.draft['parentObservationId']}',
      ),
      initialValue: model.draft['note'],
      maxLines: 4,
      decoration: const InputDecoration(labelText: 'Что вы заметили?'),
      onChanged: (v) => model.editDraft('note', v),
    ),
    const SizedBox(height: 12),
    NativeInput(
      key: ValueKey('extent:${model.account}:$fieldId'),
      initialValue: model.draft['extent'],
      decoration: const InputDecoration(labelText: 'Масштаб / участок'),
      onChanged: (v) => model.editDraft('extent', v),
    ),
    Wrap(
      spacing: 8,
      children: [
        NativeButton.icon(
          onPressed: () => pick(ImageSource.camera),
          icon: const Icon(Icons.camera_alt),
          label: const Text('Камера'),
        ),
        NativeButton.icon(
          onPressed: () => pick(ImageSource.gallery),
          icon: const Icon(Icons.photo_library),
          label: const Text('Галерея'),
        ),
        NativeButton.icon(
          onPressed: locate,
          icon: const Icon(Icons.my_location),
          label: const Text('Геопозиция'),
        ),
      ],
    ),
    if ((model.draft['photoIds'] as List?)?.isNotEmpty == true)
      Text('Сохранённых фото: ${(model.draft['photoIds'] as List).length}'),
    if (model.draft['location'] != null)
      Text('Координаты: ${coordinateText(model.draft['location'])}'),
    for (final photo in List<String>.from(model.draft['localPhotos'] ?? []))
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Image.file(File(photo), height: 160, fit: BoxFit.cover),
      ),
    if (model.draft['parentObservationId'] != null)
      const Text('Будет создано связанное повторное наблюдение.'),
    NativeButton(
      filled: true,
      onPressed: fieldId == null
          ? null
          : () => act(() async {
              await model.saveDraft(fieldId!);
              if (mounted) {
                updateUI(() => tab = 3);
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
            NativeButton(
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
    final outcome = await adaptiveDialog<String>(
      context: context,
      builder: (c) => NativeAlert(
        title: const Text('Результат выполнения'),
        content: NativeInput(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Что сделано / замечено?',
          ),
        ),
        actions: [
          NativeButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Отмена'),
          ),
          NativeButton(
            filled: true,
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
}
