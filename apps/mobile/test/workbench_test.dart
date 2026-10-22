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
    expect(find.text('Проверенная история'), findsOneWidget);
    expect(find.text('НЕПОДТВЕРЖДЕННАЯ ПОГОДА'), findsNothing);
  });
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
