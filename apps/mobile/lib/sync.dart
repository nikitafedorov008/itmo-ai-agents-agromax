import 'api.dart';
import 'generated/api_routes.dart';
import 'storage.dart';

class SyncEngine {
  SyncEngine(this.store);
  final LocalStore store;
  bool _busy = false;
  Future<void> drain(String account, Api api) async {
    if (_busy) {
      return;
    }
    _busy = true;
    try {
      await store.recover(account);
      final blocked = <String>{};
      for (final op in await store.queue(account)) {
        if (op['status'] == 'synced') {
          continue;
        }
        final id = op['operationId'] as String;
        final payload = Map<String, dynamic>.from(op['payload'] as Map);
        final entity = (payload['id'] ?? '').toString();
        if (op['status'] == 'conflict' || blocked.contains(entity)) {
          blocked.add(entity);
          continue;
        }
        await store.update(id, 'sending');
        try {
          if (op['type'] == 'observation.upsert') {
            final paths = List<String>.from(payload['localPhotos'] ?? []);
            final photos = List<String>.from(payload['photoIds'] ?? []);
            while (paths.isNotEmpty) {
              photos.add(await api.upload(paths.first));
              paths.removeAt(0);
              payload['photoIds'] = photos;
              payload['localPhotos'] = paths;
              await store.update(id, 'sending', payload: payload);
            }
          }
          final wire = {...payload}..remove('localPhotos');
          final result = await api.request(ApiRoutes.sync, {
            'operations': [
              {'operationId': id, 'type': op['type'], 'payload': wire},
            ],
          });
          final item = (result['results'] as List).single as Map;
          if (item['status'] == 'applied') {
            await store.update(id, 'synced', payload: payload);
          } else {
            await store.update(
              id,
              item['status'] == 'conflict' ? 'conflict' : 'error',
              error: item['error']?.toString() ?? 'Конфликт версии',
              payload: payload,
            );
            blocked.add(entity);
          }
        } catch (e) {
          await store.update(
            id,
            e is ApiFailure && e.status == 409 ? 'conflict' : 'error',
            error: e.toString(),
            payload: payload,
          );
          break;
        }
      }
    } finally {
      _busy = false;
    }
  }
}
