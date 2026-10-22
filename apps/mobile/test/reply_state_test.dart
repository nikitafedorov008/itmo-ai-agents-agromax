import 'package:flutter_test/flutter_test.dart';
import 'package:agromax/ui/reply_state.dart';

void main() {
  Map<String, dynamic> response() => {
    'id': 'reply',
    'text': 'Исторический ответ',
    'sources': [
      {'title': 'Источник'},
    ],
    'tools': ['field_history'],
    'requiresConfirmation': true,
    'artifact': {
      'kind': 'observation',
      'title': 'Решение',
      'body': 'Обоснование решения',
      'observationId': 'observation',
      'observationVersion': 1,
      'question': {
        'prompt': 'Когда?',
        'options': ['Сегодня'],
        'allowCustom': true,
      },
      'proposedTask': {
        'title': 'Повторить осмотр',
        'dueAt': '2026-10-24T09:00:00Z',
      },
      'actions': [
        'reply',
        'review_observation',
        'open_history',
        'view_sources',
      ],
    },
  };
  test(
    'current draft allows explicit review without mutating stored response',
    () {
      final raw = response();
      final view = currentReply(raw, [
        {'id': 'observation', 'version': 1, 'status': 'draft'},
      ]);
      expect(view['_canReview'], true);
      expect(view['artifact']['question'], isNotNull);
      expect(view['artifact']['proposedTask'], isNotNull);
      expect(raw.containsKey('_canReview'), false);
    },
  );
  test(
    'changed observation preserves history and strips stale questions and write actions',
    () {
      final raw = response();
      final view = currentReply(raw, [
        {'id': 'observation', 'version': 2, 'status': 'draft'},
      ]);
      expect(view['_canReview'], false);
      expect(view['_artifactNotice'], contains('изменилось'));
      expect(view['text'], raw['text']);
      expect(view['sources'], raw['sources']);
      expect(view['tools'], raw['tools']);
      expect(view['artifact']['body'], raw['artifact']['body']);
      expect(view['artifact']['question'], isNull);
      expect(view['artifact']['proposedTask'], isNull);
      expect(view['artifact']['actions'], ['open_history', 'view_sources']);
      expect(view['requiresConfirmation'], false);
      expect(raw['artifact']['question'], isNotNull);
    },
  );
  test(
    'approved current observation keeps fresh clarification but never another approval',
    () {
      final view = currentReply(response(), [
        {'id': 'observation', 'version': 1, 'status': 'approved'},
      ]);
      expect(view['_canReview'], false);
      expect(view['_canRevisit'], true);
      expect(view['_observationId'], 'observation');
      expect(view['_artifactNotice'], contains('уже утверждено'));
      expect(view['artifact']['question'], isNotNull);
      expect(view['artifact']['actions'], contains('reply'));
      expect(
        view['artifact']['actions'],
        isNot(contains('review_observation')),
      );
      expect(view['artifact']['proposedTask'], isNull);
    },
  );
  test('stale approved observation still hides obsolete clarification', () {
    final view = currentReply(response(), [
      {'id': 'observation', 'version': 2, 'status': 'approved'},
    ]);
    expect(view['artifact']['question'], isNull);
    expect(view['artifact']['actions'], isNot(contains('reply')));
    expect(view['_canReview'], false);
  });
  test('missing observation cannot expose historical approval command', () {
    final view = currentReply(response(), []);
    expect(view['_canReview'], false);
    expect(view['artifact']['proposedTask'], isNull);
    expect(view['artifact']['question'], isNull);
  });
}
