import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'adaptive.dart';

class WorkbenchStages extends StatelessWidget {
  const WorkbenchStages({super.key, required this.stage});
  final String stage;
  @override
  Widget build(BuildContext context) {
    final selected = ['signs', 'context', 'decision'].indexOf(stage);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          for (var i = 0; i < 3; i++)
            Expanded(
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 1,
                          color: i == 0
                              ? Colors.transparent
                              : const Color(0xffcbd6c6),
                        ),
                      ),
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: i <= selected
                              ? forest
                              : const Color(0xffe7eedb),
                        ),
                        child: Icon(
                          i < selected
                              ? CupertinoIcons.check_mark
                              : CupertinoIcons.circle_fill,
                          size: i < selected ? 16 : 8,
                          color: i <= selected
                              ? celery
                              : const Color(0xffa9b5a7),
                        ),
                      ),
                      Expanded(
                        child: Container(
                          height: 1,
                          color: i == 2
                              ? Colors.transparent
                              : const Color(0xffcbd6c6),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    ['Признаки', 'Контекст', 'Решение'][i],
                    style: TextStyle(
                      fontSize: 14,
                      color: forest,
                      fontWeight: i == selected
                          ? FontWeight.w700
                          : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class ObservationPhoto extends StatelessWidget {
  const ObservationPhoto({
    super.key,
    this.localPath,
    this.url,
    this.headers,
    this.height = 190,
    this.showCaption = true,
  });
  final String? localPath, url;
  final double height;
  final bool showCaption;
  final Map<String, String>? headers;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: SizedBox(
          height: height,
          width: double.infinity,
          child: localPath != null
              ? Image.file(File(localPath!), fit: BoxFit.cover)
              : url != null
              ? Image.network(
                  url!,
                  headers: headers,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      const Center(child: Text('Фото недоступно без связи')),
                )
              : Image.asset(
                  'assets/wheat-leaf.png',
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const ColoredBox(
                    color: Color(0xffe7eedb),
                    child: Icon(
                      CupertinoIcons.leaf_arrow_circlepath,
                      color: forest,
                      size: 70,
                    ),
                  ),
                ),
        ),
      ),
      if (showCaption) const SizedBox(height: 6),
      if (showCaption)
        Text(
          localPath == null && url == null
              ? 'Ботаническая иллюстрация · добавьте своё фото'
              : 'Фотография наблюдения · анализ изображения не выполняется',
          style: const TextStyle(fontSize: 12, color: Color(0xff5c6d60)),
        ),
    ],
  );
}

class ObservationHero extends StatelessWidget {
  const ObservationHero({
    super.key,
    required this.photo,
    required this.note,
    required this.onRead,
    this.onChoose,
  });
  final ObservationPhoto photo;
  final String note;
  final VoidCallback onRead;
  final VoidCallback? onChoose;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SizedBox(
        height: 200,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: ObservationPhoto(
                localPath: photo.localPath,
                url: photo.url,
                headers: photo.headers,
                height: 200,
                showCaption: false,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xffeef2e7),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Вы отметили',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: forest,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Expanded(
                      child: Text(
                        note,
                        maxLines: 6,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 14,
                          height: 1.35,
                          color: Color(0xff172b23),
                        ),
                      ),
                    ),
                    if (isIOS)
                      CupertinoButton(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(0, 28),
                        onPressed: onRead,
                        child: const Text(
                          'Читать полностью',
                          style: TextStyle(fontSize: 13, color: forest),
                        ),
                      )
                    else
                      TextButton(
                        onPressed: onRead,
                        child: const Text(
                          'Читать полностью',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 6),
      Text(
        photo.localPath == null && photo.url == null
            ? 'Ботаническая иллюстрация · добавьте своё фото'
            : 'Фото наблюдения · анализ изображения не выполняется',
        style: const TextStyle(fontSize: 11, color: Color(0xff5c6d60)),
      ),
      if (onChoose != null)
        Align(
          alignment: Alignment.centerRight,
          child: isIOS
              ? CupertinoButton(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  minimumSize: const Size(0, 28),
                  onPressed: onChoose,
                  child: const Text(
                    'Выбрать наблюдение',
                    style: TextStyle(fontSize: 13, color: forest),
                  ),
                )
              : TextButton(
                  onPressed: onChoose,
                  child: const Text('Выбрать наблюдение'),
                ),
        ),
    ],
  );
}

class EvidencePanel extends StatelessWidget {
  const EvidencePanel({super.key, this.reply, required this.busy});
  final Map? reply;
  final bool busy;
  @override
  Widget build(BuildContext context) {
    final tools = List<String>.from(reply?['tools'] ?? []);
    final evidence = (reply?['artifact']?['evidence'] as List? ?? []);
    final verified = evidence
        .where((item) => item is Map && _verified(item['kind'], tools))
        .toList();
    const names = {'field_history': 'История поля', 'weather': 'Погода'};
    final summary =
        reply?['artifact']?['body'] ??
        (reply == null
            ? 'Опишите признаки. Сопоставим наблюдение с историей поля и погодой.'
            : 'Контекст получен. Полный ответ доступен в обсуждении поля.');
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: forest,
        borderRadius: BorderRadius.circular(24),
      ),
      child: DefaultTextStyle(
        style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(CupertinoIcons.sparkles, color: celery),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    busy
                        ? 'Агент готовит ответ'
                        : reply == null
                        ? 'Сопоставим контекст'
                        : 'Контекст наблюдения',
                    style: const TextStyle(
                      fontSize: 21,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              summary,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final entry in names.entries) ...[
                  if (entry.key != 'field_history') const SizedBox(width: 8),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: .08),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Text(
                        '${tools.contains(entry.key) ? '✓' : '○'} ${entry.value}\n${tools.contains(entry.key) ? 'Получено из API' : 'Не запрошено в этом ответе'}',
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            Text(
              'Источники в ответе: ${(reply?['sources'] as List? ?? []).length}',
              style: const TextStyle(fontSize: 12, color: Color(0xffdce9cd)),
            ),
            if (verified.isNotEmpty)
              Theme(
                data: Theme.of(
                  context,
                ).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  dense: true,
                  iconColor: celery,
                  collapsedIconColor: celery,
                  title: const Text(
                    'Полученные данные',
                    style: TextStyle(fontSize: 13, color: Colors.white),
                  ),
                  children: [
                    for (final item in verified)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: Text(
                          item['summary'].toString(),
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xffe7eedb),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            if (busy)
              const Padding(
                padding: EdgeInsets.only(top: 14),
                child: CupertinoActivityIndicator(color: celery),
              ),
          ],
        ),
      ),
    );
  }

  bool _verified(dynamic kind, List<String> tools) => switch (kind) {
    'history' => tools.contains('field_history'),
    'weather' => tools.contains('weather'),
    'source' => tools.contains('source_search'),
    'observation' =>
      tools.contains('observation_get') || tools.contains('field_history'),
    _ => false,
  };
}

class SourceDisclosure extends StatelessWidget {
  const SourceDisclosure({super.key, required this.sources});
  final List<dynamic> sources;
  @override
  Widget build(BuildContext context) => ExpansionTile(
    tilePadding: EdgeInsets.zero,
    leading: const Icon(CupertinoIcons.book, color: forest),
    title: Text(
      'Обоснование · ${sources.length} источника',
      style: const TextStyle(fontSize: 15),
    ),
    children: [
      if (sources.isEmpty)
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text('В этом ответе нет процитированных источников.'),
        ),
      for (final s in sources)
        Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: SelectableText(
            '${s['title']}\n${s['excerpt']}\n${s['url']}',
            style: const TextStyle(fontSize: 14),
          ),
        ),
    ],
  );
}
