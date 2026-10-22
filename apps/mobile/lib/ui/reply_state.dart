/// Read-only projection of a historical response against the current server
/// observation. Stored messages/evidence are retained; stale commands are not.
Map<String, dynamic> currentReply(
  Map reply,
  List<dynamic> observations, {
  String? contextObservationId,
}) {
  final result = Map<String, dynamic>.from(reply);
  if (reply['artifact'] is! Map) return result;
  final artifact = Map<String, dynamic>.from(reply['artifact']);
  final id = artifact['observationId'] ?? contextObservationId;
  final current = observations.where((o) => o['id'] == id).firstOrNull;
  final stale =
      artifact['observationId'] != null &&
      (current == null || artifact['observationVersion'] != current['version']);
  final approved = current?['status'] == 'approved';
  final canReview =
      !stale &&
      !approved &&
      current != null &&
      artifact['observationId'] == current['id'] &&
      artifact['observationVersion'] == current['version'];
  if (stale || approved) {
    artifact.remove('question');
    artifact.remove('proposedTask');
    artifact['actions'] = (artifact['actions'] as List? ?? [])
        .where(
          (a) => const [
            'open_history',
            'open_weather',
            'view_sources',
            'start_revisit',
          ].contains(a),
        )
        .toList();
    result['_artifactNotice'] = approved
        ? 'Наблюдение уже утверждено. Ответ сохранён как история; для новых сведений создайте повторный осмотр.'
        : 'Наблюдение изменилось после этого ответа. Источники и контекст сохранены; обновите анализ перед решением.';
    result['requiresConfirmation'] = false;
  }
  result['_canReview'] = canReview;
  result['_canRevisit'] = approved;
  result['_observationId'] = current?['id'];
  result['artifact'] = artifact;
  return result;
}
