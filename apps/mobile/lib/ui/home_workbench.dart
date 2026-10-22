part of '../main.dart';

extension _Workbench on _HomeState {
  Map? get selectedField =>
      items('fields').where((f) => f['id'] == fieldId).firstOrNull;
  List<dynamic> get fieldObservations =>
      items('observations').where((o) => o['fieldId'] == fieldId).toList();
  Map? get selectedObservation =>
      fieldObservations.where((o) => o['id'] == observationId).firstOrNull ??
      fieldObservations.lastOrNull;
  List<dynamic> get contextMessages {
    if (chat.isNotEmpty) return chat;
    final history = items(
      'conversations',
    ).where((c) => c['fieldId'] == fieldId).toList();
    return history.isEmpty ? [] : List<dynamic>.from(history.last['messages']);
  }

  Map? get latestReply => contextMessages.reversed
      .where((m) => m['reply'] != null)
      .firstOrNull?['reply'];
  Future<void> choose(
    String title,
    Map<String, String> options,
    ValueChanged<String> onSelect,
  ) async {
    String? choice;
    if (isIOS) {
      choice = await showCupertinoModalPopup<String>(
        context: context,
        builder: (c) => CupertinoActionSheet(
          title: Text(title),
          actions: [
            for (final e in options.entries)
              CupertinoActionSheetAction(
                onPressed: () => Navigator.pop(c, e.key),
                child: Text(e.value),
              ),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(c),
            child: const Text('Отмена'),
          ),
        ),
      );
    } else {
      choice = await showModalBottomSheet<String>(
        context: context,
        builder: (c) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(title: Text(title)),
              for (final e in options.entries)
                ListTile(
                  title: Text(e.value),
                  onTap: () => Navigator.pop(c, e.key),
                ),
            ],
          ),
        ),
      );
    }
    if (choice != null) onSelect(choice);
  }

  void selectFieldSheet() => choose(
    'Выберите поле',
    {
      for (final f in items('fields'))
        f['id']: '${f['name']} · ${f['crop']} · ${f['areaHa']} га',
    },
    (id) async {
      await model.selectField(id);
      if (mounted) {
        updateUI(() {
          fieldId = id;
          observationId = null;
          chat.clear();
          conversationId = null;
          chatRetry = null;
        });
      }
    },
  );
  void providerSheet() => choose('Модель агента', {
    for (final p in items('providers'))
      p['id']:
          '${p['id'] == 'deepseek' ? 'DeepSeek' : 'MiMo'}${p['configured'] == true ? '' : ' · не настроена'}',
  }, (id) => updateUI(() => provider = id));
  Future<void> showSheet(String title, List<Widget> Function() content) async {
    Widget sheet(BuildContext c) => Material(
      color: ivory,
      child: SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .88,
          child: Column(
            children: [
              if (isIOS)
                CupertinoNavigationBar(
                  middle: Text(title),
                  trailing: CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () => Navigator.pop(c),
                    child: const Text('Готово'),
                  ),
                )
              else
                ListTile(
                  title: Text(title),
                  trailing: IconButton(
                    onPressed: () => Navigator.pop(c),
                    icon: const Icon(Icons.close),
                  ),
                ),
              Expanded(
                child: Consumer(
                  builder: (c, ref, _) {
                    ref.watch(modelProvider);
                    return ListView(
                      padding: const EdgeInsets.all(20),
                      children: content(),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (isIOS) {
      await showCupertinoModalPopup<void>(context: context, builder: sheet);
    } else {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: sheet,
      );
    }
  }

  Future<DateTime?> taskDate(DateTime initial) async {
    final now = DateTime.now();
    final start = initial.isBefore(now)
        ? now.add(const Duration(minutes: 1))
        : initial;
    if (!isIOS) {
      return showDatePicker(
        context: context,
        initialDate: start,
        firstDate: DateTime(now.year, now.month, now.day),
        lastDate: DateTime(now.year + 5),
      );
    }
    var selected = start;
    return showCupertinoModalPopup<DateTime>(
      context: context,
      builder: (c) => Container(
        height: 340,
        color: ivory,
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CupertinoButton(
                    onPressed: () => Navigator.pop(c),
                    child: const Text('Отмена'),
                  ),
                  const Text('Срок задачи'),
                  CupertinoButton(
                    onPressed: () => Navigator.pop(c, selected),
                    child: const Text('Далее'),
                  ),
                ],
              ),
              Expanded(
                child: CupertinoDatePicker(
                  initialDateTime: start,
                  minimumDate: now,
                  mode: CupertinoDatePickerMode.dateAndTime,
                  use24hFormat: true,
                  onDateTimeChanged: (date) => selected = date,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> openConversation() => showSheet('Обсуждение поля', chatView);
  Future<void> expandMap() async {
    if (selectedField == null) return;
    await showSheet(
      'Карта поля',
      () => [
        SizedBox(
          height: MediaQuery.sizeOf(context).height * .65,
          child: FieldMap(
            field: selectedField!,
            observations: fieldObservations,
            expanded: true,
          ),
        ),
        if (selectedField?['demo'] == true)
          const Text('Демо-контур · синтетические границы'),
        Text('${selectedField?['name']} · ${selectedField?['crop']}'),
      ],
    );
  }

  List<Widget> workbenchView() {
    final o = selectedObservation;
    final reply = latestReply;
    final artifact = reply?['artifact'];
    final local = List<String>.from(model.draft['localPhotos'] ?? []);
    final photoIds = o?['photoIds'] as List? ?? [];
    final hasDraft =
        (model.draft['note'] ?? '').toString().isNotEmpty || local.isNotEmpty;
    final photoId = !hasDraft && photoIds.isNotEmpty ? photoIds.first : null;
    return [
      WorkbenchStages(
        stage: artifact?['stage'] ?? (reply != null ? 'context' : 'signs'),
      ),
      ObservationPhoto(
        localPath: local.firstOrNull,
        url: photoId == null
            ? null
            : Uri.parse(apiBase).resolve(ApiRoutes.photo(photoId)).toString(),
        headers: {'Authorization': 'Bearer ${model.session?['accessToken']}'},
      ),
      const SizedBox(height: 16),
      if (hasDraft)
        card(
          'Вы отметили',
          model.draft['note'] ?? 'Добавьте описание наблюдения ниже',
        ),
      if (o != null && !hasDraft)
        card(
          'Вы отметили',
          o['note'] ?? '',
          actions: [
            Text(
              observationDate(o['createdAt']),
              style: const TextStyle(fontSize: 13),
            ),
            NativeButton(
              onPressed: () => choose(
                'Наблюдение для обсуждения',
                {
                  for (final item in fieldObservations)
                    item['id']: item['note'].toString(),
                },
                (id) => updateUI(() {
                  observationId = id;
                  chat.clear();
                  conversationId = null;
                }),
              ),
              child: const Text('Выбрать наблюдение'),
            ),
          ],
        ),
      if (selectedField != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: FieldMap(
            field: selectedField!,
            observations: fieldObservations,
            onExpand: expandMap,
          ),
        ),
      EvidencePanel(reply: reply, busy: chatBusy),
      if (reply?['artifact']?['question'] != null)
        ...questionWidgets(reply!['artifact']['question']),
      if (reply != null) SourceDisclosure(sources: reply['sources'] ?? []),
      if (artifact != null &&
          artifact['observationId'] != null &&
          artifact['observationVersion'] != null)
        card(
          artifact['title'],
          artifact['body'],
          actions: [
            if (artifact['proposedTask'] != null)
              Text(
                'Предлагаемая задача: ${artifact['proposedTask']['title']}\nСрок: ${artifact['proposedTask']['dueAt']}',
              ),
            NativeButton(
              filled: true,
              onPressed: () => approve({
                'id': artifact['observationId'],
                'version': artifact['observationVersion'],
                'body': artifact['body'],
              }, artifact['proposedTask']),
              child: const Text('Проверить и утвердить'),
            ),
          ],
        ),
      const SizedBox(height: 12),
      NativeButton(
        filled: true,
        onPressed: chatBusy || fieldId == null
            ? null
            : () {
                observationId = o?['id'];
                message.text = o == null
                    ? 'Помоги провести осмотр поля. Какие признаки нужно описать?'
                    : 'Проанализируй выбранное наблюдение: ${o['note']}. Сопоставь с историей поля, погодой и проверенными источниками. Уточни недостающие сведения.';
                sendChat();
              },
        child: Text(
          chatBusy
              ? 'Ожидаем ответ модели…'
              : reply == null
              ? 'Сопоставить контекст'
              : 'Обновить анализ',
        ),
      ),
      NativeButton.icon(
        onPressed: openConversation,
        icon: const Icon(CupertinoIcons.chat_bubble_2, color: forest),
        label: const Text('Обсудить свободно'),
      ),
      ...observationView(),
    ];
  }

  List<Widget> questionWidgets(Map question) => [
    heading('Нужно уточнение'),
    Text(
      question['prompt'].toString(),
      style: const TextStyle(
        fontSize: 21,
        fontWeight: FontWeight.w700,
        color: forest,
      ),
    ),
    const SizedBox(height: 12),
    Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final option in question['options'] as List? ?? [])
          NativeButton(
            outlined: true,
            onPressed: chatBusy
                ? null
                : () {
                    observationId ??= selectedObservation?['id'];
                    message.text = option.toString();
                    sendChat();
                  },
            child: Text(option.toString()),
          ),
      ],
    ),
    if (question['allowCustom'] == true) ...[
      NativeInput(
        controller: message,
        maxLines: 2,
        decoration: const InputDecoration(labelText: 'Ваш ответ'),
      ),
      NativeButton(
        filled: true,
        onPressed: chatBusy ? null : sendChat,
        child: const Text('Добавить ответ и продолжить'),
      ),
    ],
  ];
  List<Widget> moreView() => [
    heading('Хозяйство'),
    Text(
      '${model.session?['farm']['name']} · ${model.session?['user']['role'] == 'chief' ? 'Руководитель' : 'Агроном'}',
    ),
    NativeButton.icon(
      onPressed: openConversation,
      icon: const Icon(CupertinoIcons.chat_bubble_2),
      label: const Text('Обсуждение выбранного поля'),
    ),
    NativeButton.icon(
      onPressed: providerSheet,
      icon: const Icon(CupertinoIcons.slider_horizontal_3),
      label: Text('Модель: $provider'),
    ),
    ...queueView(),
    const SizedBox(height: 20),
    NativeButton(
      onPressed: chatBusy
          ? null
          : () async {
              if (await confirm(
                'Выйти?',
                'Черновики и очередь останутся в аккаунте на этом устройстве.',
              )) {
                chat.clear();
                conversationId = null;
                observationId = null;
                chatRetry = null;
                fieldId = null;
                await model.logout();
              }
            },
      child: const Text('Выйти из аккаунта'),
    ),
  ];
}
