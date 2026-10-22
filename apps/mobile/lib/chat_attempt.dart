import 'api.dart';

/// Only an acknowledged terminal server failure permits a fresh mutation id.
/// Transport failures and IN_PROGRESS leave the original attempt ambiguous.
abstract final class ChatAttempt {
  static const terminalCodes = {
    'MODEL_UNCONFIGURED',
    'PROVIDER_ERROR',
    'AGENT_TIMEOUT',
    'INVALID_MODEL_OUTPUT',
    'INVALID_TOOL_ARGUMENTS',
    'TOOL_LIMIT',
    'AGENT_LIMIT',
    'AGENT_ERROR',
    'AGENT_FAILED',
    'RUN_INTERRUPTED',
  };
  static bool isTerminal(Map pending) => pending['_terminalError'] != null;

  static Map<String, dynamic> prepare(
    Map<String, dynamic> pending, {
    required String Function() newId,
    required String provider,
  }) {
    final request = {...pending};
    if (isTerminal(request)) {
      request['operationId'] = newId();
      request['provider'] = provider;
    }
    request.remove('_terminalError');
    return request;
  }

  static Map<String, dynamic> afterFailure(
    Map<String, dynamic> request,
    Object error,
  ) => {
    ...request,
    if (error is ApiFailure &&
        (terminalCodes.contains(error.code) ||
            (error.code == 'WEATHER_UNAVAILABLE' &&
                (error.status == 502 || error.status == 409)) ||
            (error.code == 'DATABASE_UNAVAILABLE' && error.status == 409)))
      '_terminalError': error.code,
  };
}
