import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:agromax/ui/adaptive.dart';
import 'package:agromax/ui/workbench.dart';

void main() {
  testWidgets('evidence reports completed reads only for returned tools', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: EvidencePanel(
            busy: false,
            reply: {
              'text': 'Ответ по истории',
              'tools': ['field_history'],
              'artifact': {
                'evidence': [
                  {'kind': 'weather', 'summary': 'НЕПОДТВЕРЖДЕННАЯ ПОГОДА'},
                  {'kind': 'history', 'summary': 'Проверенная история'},
                ],
              },
            },
          ),
        ),
      ),
    );
    expect(
      find.textContaining('История поля\nПолучено из API'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Погода\nНе запрошено в этом ответе'),
      findsOneWidget,
    );
    expect(find.text('Проверенная история'), findsNothing);
    await tester.tap(find.text('Полученные данные'));
    await tester.pumpAndSettle();
    expect(find.text('Проверенная история'), findsOneWidget);
    expect(find.text('НЕПОДТВЕРЖДЕННАЯ ПОГОДА'), findsNothing);
  });
  testWidgets(
    'compact AI card uses the artifact summary and leaves full answer to chat',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EvidencePanel(
              busy: false,
              reply: {
                'text': 'ПОЛНЫЙ ДЛИННЫЙ ОТВЕТ ДЛЯ ОБСУЖДЕНИЯ',
                'tools': [],
                'sources': [],
                'artifact': {'body': 'Краткое сопоставление контекста'},
              },
            ),
          ),
        ),
      );
      expect(find.text('Краткое сопоставление контекста'), findsOneWidget);
      expect(find.text('ПОЛНЫЙ ДЛИННЫЙ ОТВЕТ ДЛЯ ОБСУЖДЕНИЯ'), findsNothing);
      expect(find.textContaining('Источники в ответе: 0'), findsOneWidget);
    },
  );
  testWidgets(
    'history and weather context tiles invoke their actual callbacks',
    (tester) async {
      var history = 0, weather = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EvidencePanel(
              busy: false,
              onHistory: () => history++,
              onWeather: () => weather++,
            ),
          ),
        ),
      );
      await tester.tap(find.textContaining('История поля'));
      await tester.tap(find.textContaining('Погода'));
      expect(history, 1);
      expect(weather, 1);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
  testWidgets(
    'iOS observation input uses native text field and clears after saved draft',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NativeInput(
              initialValue: 'Наблюдение',
              decoration: InputDecoration(labelText: 'Признаки'),
            ),
          ),
        ),
      );
      expect(find.byType(CupertinoTextField), findsOneWidget);
      expect(find.text('Наблюдение'), findsOneWidget);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: NativeInput(
              initialValue: '',
              decoration: InputDecoration(labelText: 'Признаки'),
            ),
          ),
        ),
      );
      expect(find.text('Наблюдение'), findsNothing);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
}
