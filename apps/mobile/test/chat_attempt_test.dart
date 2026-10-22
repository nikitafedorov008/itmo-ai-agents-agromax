import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:agromax/api.dart';
import 'package:agromax/chat_attempt.dart';

void main() {
  final request = <String, dynamic>{
    'operationId': 'original',
    'message': 'Проверь поле',
    'fieldId': 'field',
    'provider': 'deepseek',
  };
  test(
    'terminal model failures create a new attempt only when explicitly prepared',
    () {
      for (final code in ChatAttempt.terminalCodes) {
        final failed = ChatAttempt.afterFailure(
          request,
          ApiFailure(502, 'Ошибка', null, code),
        );
        expect(failed['operationId'], 'original');
        expect(ChatAttempt.isTerminal(failed), true);
        final next = ChatAttempt.prepare(
          failed,
          newId: () => 'new',
          provider: 'mimo',
        );
        expect(next['operationId'], 'new');
        expect(next['provider'], 'mimo');
        expect(next['message'], request['message']);
        expect(next.containsKey('_terminalError'), false);
      }
    },
  );
  test(
    'database outage is terminal only after server marks attempt failed',
    () {
      expect(
        ChatAttempt.isTerminal(
          ChatAttempt.afterFailure(
            request,
            ApiFailure(503, 'Погода недоступна', null, 'WEATHER_UNAVAILABLE'),
          ),
        ),
        false,
      );
      final unavailable = ChatAttempt.afterFailure(
        request,
        ApiFailure(503, 'Недоступно', null, 'DATABASE_UNAVAILABLE'),
      );
      expect(ChatAttempt.isTerminal(unavailable), false);
      expect(
        ChatAttempt.prepare(
          unavailable,
          newId: () => 'new',
          provider: 'mimo',
        )['operationId'],
        'original',
      );
      final terminal = ChatAttempt.afterFailure(
        request,
        ApiFailure(
          409,
          'Предыдущая попытка завершилась ошибкой',
          null,
          'DATABASE_UNAVAILABLE',
        ),
      );
      expect(ChatAttempt.isTerminal(terminal), true);
      expect(
        ChatAttempt.prepare(
          terminal,
          newId: () => 'new',
          provider: 'mimo',
        )['operationId'],
        'new',
      );
    },
  );
  test('weather failure including terminal409 can start new attempt', () {
    for (final status in [502, 409]) {
      final failed = ChatAttempt.afterFailure(
        request,
        ApiFailure(status, 'Погода недоступна', null, 'WEATHER_UNAVAILABLE'),
      );
      expect(ChatAttempt.isTerminal(failed), true);
    }
  });
  test('network timeout and IN_PROGRESS keep UUID and original provider', () {
    for (final error in [
      const SocketException('offline'),
      ApiFailure(409, 'Выполняется', null, 'IN_PROGRESS'),
      ApiFailure(409, 'Конфликт', null, 'IDEMPOTENCY_CONFLICT'),
    ]) {
      final next = ChatAttempt.prepare(
        ChatAttempt.afterFailure(request, error),
        newId: () => 'must-not-be-used',
        provider: 'mimo',
      );
      expect(next, request);
    }
  });
  test(
    'cross-observation pending request is blocked before generating a billable attempt id',
    () {
      final pending = <String, dynamic>{
        'fieldId': 'field',
        'observationId': 'A',
        'message': 'Original A',
        'operationId': 'stable-A',
        'provider': 'deepseek',
        '_terminalError': 'AGENT_ERROR',
      };
      var idsGenerated = 0;
      expect(
        ChatAttempt.matchesContext(
          pending,
          fieldId: 'field',
          observationId: 'B',
        ),
        false,
      );
      expect(
        () => ChatAttempt.prepareForContext(
          pending,
          fieldId: 'field',
          observationId: 'B',
          newId: () {
            idsGenerated++;
            return 'new';
          },
          provider: 'mimo',
        ),
        throwsStateError,
      );
      expect(idsGenerated, 0);
      expect(pending['operationId'], 'stable-A');
      expect(pending['message'], 'Original A');
    },
  );
  test(
    'explicit resume preserves ambiguous attempt id and original message in its own context',
    () {
      final pending = <String, dynamic>{
        'fieldId': 'field',
        'observationId': 'A',
        'message': 'Original A',
        'operationId': 'stable-A',
        'provider': 'deepseek',
      };
      final resumed = ChatAttempt.prepareForContext(
        pending,
        fieldId: 'field',
        observationId: 'A',
        newId: () => throw StateError('Must not allocate id'),
        provider: 'mimo',
      );
      expect(resumed, pending);
      expect(
        ChatAttempt.matchesContext(
          pending,
          fieldId: 'other-field',
          observationId: 'A',
        ),
        false,
      );
      expect(
        ChatAttempt.matchesContext(
          pending,
          fieldId: 'field',
          observationId: null,
        ),
        false,
      );
    },
  );
}
