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
}
