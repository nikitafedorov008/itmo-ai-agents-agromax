part of '../main.dart';

extension _Workbench on _HomeState {
  bool bindObservation(String? id) {
    if (observationId != id && (chatBusy || chatPreparing)) {
      unawaited(
        adaptiveDialog<void>(
          context: context,
          builder: (c) => NativeAlert(
            title: const Text('Запрос выполняется'),
            content: const Text('Дождитесь ответа перед сменой наблюдения.'),
            actions: [
              NativeButton(
                onPressed: () => Navigator.pop(c),
                child: const Text('Понятно'),
              ),
            ],
          ),
        ),
      );
      return false;
    }
    final pending = chatRetry ?? model.pendingChat;
    if (!ChatAttempt.matchesContext(
      pending,
      fieldId: fieldId,
      observationId: id,
    )) {
      unawaited(showPendingContext(pending!));
      return false;
    }
    if (observationId != id) {
      observationId = id;
      model.activeObservation = id;
      unawaited(
        model.store.set(
          'chat-active-observation:${model.account}:$fieldId',
          id,
        ),
      );
      conversationId = null;
      chat.clear();
    }
    return true;
  }

  Future<void> showPendingContext(Map pending) => adaptiveDialog<void>(
    context: context,
    builder: (c) => NativeAlert(
      title: const Text('Есть незавершённый запрос'),
      content: const Text(
        'Он относится к другому наблюдению. Вернитесь к его обсуждению, чтобы явно повторить или отменить запрос. Новый запрос сейчас не отправлен.',
      ),
      actions: [
        NativeButton(
          onPressed: () => Navigator.pop(c),
          child: const Text('Закрыть'),
        ),
        NativeButton(
          onPressed: () {
            Navigator.pop(c);
            if (bindObservation(pending['observationId'])) openConversation();
          },
          child: const Text('К обсуждению запроса'),
        ),
      ],
    ),
  );

  Map? get selectedField =>
      items('fields').where((f) => f['id'] == fieldId).firstOrNull;
  List<dynamic> get fieldObservations =>
      (items('observations').where((o) => o['fieldId'] == fieldId).toList()
        ..sort(
          (a, b) =>
              a['createdAt'].toString().compareTo(b['createdAt'].toString()),
        ));
  Map? get selectedObservation =>
      fieldObservations.where((o) => o['id'] == observationId).firstOrNull ??
      fieldObservations.lastOrNull;
  List<dynamic> get contextMessages {
    if (chat.isNotEmpty) return chat;
    final history = items(
      'conversations',
    ).where((c) => c['fieldId'] == fieldId).toList();
    final contextId =
        conversationId ?? model.conversationContexts[observationId ?? 'field'];
    final contextual = history.where((c) => c['id'] == contextId).firstOrNull;
    if (contextual != null) return List<dynamic>.from(contextual['messages']);
    if (observationId != null) return [];
    history.sort((a, b) => _lastMessageDate(a).compareTo(_lastMessageDate(b)));
    return history.isEmpty ? [] : List<dynamic>.from(history.last['messages']);
  }

  String _lastMessageDate(Map conversation) =>
      (conversation['messages'] as List? ?? []).lastOrNull?['createdAt']
          ?.toString() ??
      '';

  Map? get latestReply {
    final raw = contextMessages.reversed
        .where((m) => m['reply'] != null)
        .firstOrNull?['reply'];
    return raw == null
        ? null
        : currentReply(
            raw,
            items('observations'),
            contextObservationId: observationId,
          );
  }

  List<Widget> replyDecisionWidgets(Map reply) => [
    if (reply['_artifactNotice'] != null)
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(
          reply['_artifactNotice'],
          style: const TextStyle(fontSize: 14, color: forest),
        ),
      ),
    if (reply['_canReview'] == true)
      NativeButton(
        filled: true,
        onPressed: () => reviewCurrentArtifact(reply),
        child: const Text('Проверить и утвердить'),
      ),
    if (reply['_canRevisit'] == true)
      NativeButton.icon(
        onPressed: () => startRevisit(reply['_observationId']),
        icon: const Icon(CupertinoIcons.arrow_clockwise),
        label: const Text('Повторный осмотр'),
      ),
  ];
  Future<void> startRevisit(String? id) async {
    if (id == null) return;
    await model.editDraft('parentObservationId', id);
    await model.editDraft('note', 'Повторный осмотр: ');
    if (mounted) updateUI(() => tab = 1);
  }

  Future<void> reviewCurrentArtifact(Map reply) async {
    // Recheck at the tap boundary as sync may have replaced the observation.
    final current = currentReply(
      reply,
      items('observations'),
      contextObservationId: observationId,
    );
    if (current['_canReview'] != true) {
      model.changed();
      return;
    }
    final artifact = current['artifact'];
    await approve({
      'id': artifact['observationId'],
      'version': artifact['observationVersion'],
      'body': artifact['body'],
    }, artifact['proposedTask']);
  }

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
  void providerSheet() => choose(
    'Модель агента',
    {
      for (final p in items('providers'))
        p['id']:
            '${p['id'] == 'deepseek' ? 'DeepSeek' : 'MiMo'}${p['configured'] == true ? '' : ' · не настроена'}',
    },
    (id) {
      updateUI(() => provider = id);
      model.changed();
    },
  );
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
  Future<void> observationSheet(Map o) => showSheet(
    'Наблюдение на карте',
    () => [
      heading(o['note'].toString()),
      Text(observationDate(o['createdAt'])),
      Text('Координаты: ${coordinateText(o['location'])}'),
      for (final id in o['photoIds'] as List? ?? [])
        ObservationPhoto(
          url: Uri.parse(apiBase).resolve(ApiRoutes.photo(id)).toString(),
          headers: {'Authorization': 'Bearer ${model.session?['accessToken']}'},
        ),
      NativeButton(
        filled: true,
        onPressed: () {
          if (bindObservation(o['id'])) openConversation();
        },
        child: const Text('Обсудить наблюдение'),
      ),
    ],
  );
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
            onObservationTap: observationSheet,
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
      ObservationHero(
        photo: ObservationPhoto(
          localPath: local.firstOrNull,
          url: photoId == null
              ? null
              : Uri.parse(apiBase).resolve(ApiRoutes.photo(photoId)).toString(),
          headers: {'Authorization': 'Bearer ${model.session?['accessToken']}'},
        ),
        note: hasDraft
            ? (model.draft['note'] ?? 'Добавьте описание наблюдения ниже')
            : (o?['note'] ??
                  'Добавьте фото и опишите, что вы заметили на поле.'),
        onRead: () => showSheet(
          'Вы отметили',
          () => [
            SelectableText(
              hasDraft
                  ? (model.draft['note'] ?? '')
                  : (o?['note'] ?? 'Наблюдение ещё не добавлено.'),
            ),
            if (o != null && !hasDraft) Text(observationDate(o['createdAt'])),
          ],
        ),
        onChoose: fieldObservations.length > 1
            ? () => choose(
                'Наблюдение для обсуждения',
                {
                  for (final item in fieldObservations)
                    item['id']: item['note'].toString(),
                },
                (id) => updateUI(() => bindObservation(id)),
              )
            : null,
      ),
      if (selectedField != null)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: FieldMap(
            field: selectedField!,
            observations: fieldObservations,
            onObservationTap: observationSheet,
            onExpand: expandMap,
          ),
        ),
      EvidencePanel(
        reply: reply,
        busy: chatBusy,
        onHistory: () =>
            performArtifactAction('open_history', reply?['sources'] ?? []),
        onWeather: () =>
            performArtifactAction('open_weather', reply?['sources'] ?? []),
      ),
      if (reply?['artifact']?['question'] != null)
        ...questionWidgets(reply!['artifact']['question']),
      if (reply != null) SourceDisclosure(sources: reply['sources'] ?? []),
      if (artifact != null)
        ...artifactActions(artifact, reply?['sources'] ?? []),
      if (reply != null) ...replyDecisionWidgets(reply),
      const SizedBox(height: 12),
      NativeButton(
        filled: true,
        onPressed: chatBusy || fieldId == null
            ? null
            : () {
                if (!bindObservation(o?['id'])) return;
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
        onPressed: () {
          if (bindObservation(o?['id'])) openConversation();
        },
        icon: const Icon(CupertinoIcons.chat_bubble_2, color: forest),
        label: const Text('Обсудить свободно'),
      ),
      ...observationView(),
    ];
  }

  List<Widget> artifactActions(Map artifact, List<dynamic> sources) => [
    Wrap(
      spacing: 8,
      children: [
        for (final action in artifact['actions'] as List? ?? [])
          if (const [
            'reply',
            'open_history',
            'open_weather',
            'start_revisit',
            'view_sources',
          ].contains(action))
            NativeButton(
              outlined: true,
              onPressed: chatBusy
                  ? null
                  : () => performArtifactAction(action.toString(), sources),
              child: Text(
                const {
                  'reply': 'Обсудить',
                  'open_history': 'История поля',
                  'open_weather': 'Погода',
                  'start_revisit': 'Повторный осмотр',
                  'view_sources': 'Источники',
                }[action]!,
              ),
            ),
      ],
    ),
  ];
  Future<void> performArtifactAction(
    String action,
    List<dynamic> sources,
  ) async {
    switch (action) {
      case 'reply':
        await openConversation();
      case 'open_history':
        updateUI(() => tab = 0);
      case 'view_sources':
        await showSheet(
          'Источники ответа',
          () => [SourceDisclosure(sources: sources)],
        );
      case 'start_revisit':
        final o = selectedObservation;
        if (o != null) {
          await model.editDraft('parentObservationId', o['id']);
          await model.editDraft('note', 'Повторный осмотр: ');
          if (mounted) updateUI(() => tab = 1);
        }
      case 'open_weather':
        if (fieldId == null) return;
        await act(() async {
          final weather = await model.api.request(ApiRoutes.weather(fieldId!));
          if (!mounted) return;
          await showSheet(
            'Погода поля',
            () => [
              Text('${weather['source']}'),
              Text('Получено: ${observationDate(weather['fetchedAt'])}'),
              for (final d in weather['days'] as List)
                Text(
                  '${d['date']}: ${d['minC']}…${d['maxC']} °C · осадки ${d['rainMm']} мм',
                ),
            ],
          );
        });
    }
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
        onPressed: chatBusy
            ? null
            : () {
                sendChat();
              },
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
