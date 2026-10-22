import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:agromax/api.dart';
import 'package:agromax/storage.dart';
import 'package:agromax/sync.dart';
import 'package:agromax/chat_attempt.dart';
import 'package:agromax/model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class FakeApi extends Api {
  FakeApi() : super('test');
  bool fail = false;
  String result = 'applied';
  final calls = <Map<String, dynamic>>[];
  final uploads = <String>[];
  final uploadIds = <String>[];
  final acceptedUploads = <String, String>{};
  bool loseNextPhotoResponse = false;
  Future<void> Function(String, String)? inspectUpload;
  @override
  Future<String> upload(String path, {required String operationId}) async {
    await inspectUpload?.call(path, operationId);
    uploads.add(path);
    uploadIds.add(operationId);
    final photo = acceptedUploads.putIfAbsent(
      operationId,
      () => 'photo-${acceptedUploads.length + 1}',
    );
    if (loseNextPhotoResponse) {
      loseNextPhotoResponse = false;
      throw const SocketException('Upload accepted, response lost');
    }
    return photo;
  }

  @override
  Future<Map<String, dynamic>> request(
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    calls.add(body!);
    if (fail) {
      throw const SocketException('offline');
    }
    return {
      'results': [
        {
          'operationId': body['operations'][0]['operationId'],
          'status': result,
          'error': result == 'applied' ? null : 'Версия изменена',
        },
      ],
    };
  }
}

void main() {
  late LocalStore store;
  late Directory dir;
  late String path;
  setUpAll(() => sqfliteFfiInit());
  Future<LocalStore> reopen() async => LocalStore(
    await databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: 1,
        onCreate: (db, _) async {
          await db.execute(
            'CREATE TABLE kv (key TEXT PRIMARY KEY, value TEXT NOT NULL)',
          );
          await db.execute(
            'CREATE TABLE outbox (operationId TEXT PRIMARY KEY, account TEXT NOT NULL, type TEXT NOT NULL, payload TEXT NOT NULL, status TEXT NOT NULL, error TEXT, createdAt TEXT NOT NULL)',
          );
        },
      ),
    ),
  );
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('agromax-test');
    path = '${dir.path}/db.sqlite';
    store = await reopen();
  });
  tearDown(() async {
    await store.db.close();
    await dir.delete(recursive: true);
  });
  test(
    'offline retry retains id, draft, photo upload checkpoint across database reopen',
    () async {
      await store.set('draft:alice', {'note': 'Пятна'});
      await store.enqueue('alice', 'stable-op', 'observation.upsert', {
        'id': 'obs',
        'note': 'Пятна',
        'photoIds': [],
        'localPhotos': ['durable.jpg'],
      });
      final api = FakeApi()..fail = true;
      await SyncEngine(store).drain('alice', api);
      expect((await store.queue('alice')).single['status'], 'error');
      expect(api.uploads, ['durable.jpg']);
      await store.db.close();
      store = await reopen();
      api.fail = false;
      await SyncEngine(store).drain('alice', api);
      expect((await store.get('draft:alice'))['note'], 'Пятна');
      expect((await store.queue('alice')).single['status'], 'synced');
      expect(api.uploads.length, 1);
      expect(api.calls.map((c) => c['operations'][0]['operationId']), [
        'stable-op',
        'stable-op',
      ]);
      expect(api.calls.last['operations'][0]['payload']['photoIds'], [
        'photo-1',
      ]);
      expect(
        api.calls.last['operations'][0]['payload'].containsKey('localPhotos'),
        false,
      );
      expect(
        api.calls.last['operations'][0]['payload'].containsKey(
          'photoOperationIds',
        ),
        false,
      );
    },
  );
  test(
    'accepted photo with lost response reuses persisted upload UUID after reopen',
    () async {
      await store.enqueue('alice', 'obs-op', 'observation.upsert', {
        'id': 'obs',
        'photoIds': [],
        'localPhotos': ['/durable/photo.png'],
      });
      final api = FakeApi()..loseNextPhotoResponse = true;
      api.inspectUpload = (path, id) async {
        expect(
          (await store.queue(
            'alice',
          )).single['payload']['photoOperationIds'][path],
          id,
          reason: 'Upload UUID must be committed before network request',
        );
      };
      await SyncEngine(store).drain('alice', api);
      expect((await store.queue('alice')).single['status'], 'error');
      expect(api.acceptedUploads.length, 1);
      expect(api.calls, isEmpty);
      await store.db.close();
      store = await reopen();
      await SyncEngine(store).drain('alice', api);
      expect(api.uploadIds.length, 2);
      expect(api.uploadIds.first, api.uploadIds.last);
      expect(
        api.acceptedUploads.length,
        1,
        reason: 'Server reused the accepted photo',
      );
      final payload = api.calls.single['operations'][0]['payload'];
      expect(payload['photoIds'], ['photo-1']);
      expect(payload.containsKey('photoOperationIds'), false);
      expect((await store.queue('alice')).single['status'], 'synced');
    },
  );
  test('account isolation and sending recovery', () async {
    await store.enqueue('alice', 'a', 'task.complete', {'id': 't1'});
    await store.enqueue('bob', 'b', 'task.complete', {'id': 't2'});
    await store.update('a', 'sending');
    final api = FakeApi();
    await SyncEngine(store).drain('alice', api);
    expect(api.calls.length, 1);
    expect(api.calls.single['operations'][0]['operationId'], 'a');
    expect((await store.queue('bob')).single['status'], 'local');
  });
  test(
    'conflict retains local changes and blocks dependent approval',
    () async {
      await store.enqueue('alice', 'a', 'observation.upsert', {
        'id': 'obs',
        'note': 'Локальная версия',
        'photoIds': [],
      });
      await store.enqueue('alice', 'b', 'observation.approve', {
        'id': 'obs',
        'version': 1,
        'confirmed': true,
      });
      final api = FakeApi()..result = 'conflict';
      final engine = SyncEngine(store);
      await engine.drain('alice', api);
      await store.db.close();
      store = await reopen();
      await SyncEngine(store).drain('alice', api);
      final queue = await store.queue('alice');
      expect(api.calls.length, 1);
      expect(queue.first['status'], 'conflict');
      expect(queue.first['payload']['note'], 'Локальная версия');
      expect(queue.last['status'], 'local');
    },
  );
  test('draft becomes queued atomically and retains photos', () async {
    await store.set('draft:alice:field', {'note': 'Пятна'});
    await store.queueDraft('alice', 'op', 'draft:alice:field', {
      'note': 'Пятна',
      'localPhotos': ['/durable/photo.jpg'],
    });
    await store.db.close();
    store = await reopen();
    expect(await store.get('draft:alice:field'), isEmpty);
    expect((await store.queue('alice')).single['payload']['localPhotos'], [
      '/durable/photo.jpg',
    ]);
  });

  test(
    'terminal chat marker persists until explicit retry after restart',
    () async {
      final failed = ChatAttempt.afterFailure({
        'operationId': 'original',
        'message': 'Осмотр',
        'provider': 'deepseek',
      }, ApiFailure(504, 'Таймаут', null, 'AGENT_TIMEOUT'));
      await store.set('chat-pending:alice:field', failed);
      await store.db.close();
      store = await reopen();
      final saved = Map<String, dynamic>.from(
        await store.get('chat-pending:alice:field'),
      );
      expect(saved['operationId'], 'original');
      final next = ChatAttempt.prepare(
        saved,
        newId: () => 'next',
        provider: 'mimo',
      );
      expect(next['operationId'], 'next');
      expect(next['message'], 'Осмотр');
    },
  );

  test(
    'conflict restoration retains original queue and all inspection data',
    () async {
      final payload = <String, dynamic>{
        'id': 'obs',
        'fieldId': 'field',
        'note': 'Локальный текст',
        'extent': 'Южная часть',
        'location': {'lat': 55.0, 'lng': 37.0},
        'photoIds': ['uploaded'],
        'localPhotos': ['/documents/pending.jpg'],
      };
      await store.enqueue(
        'farm:user',
        'conflicted',
        'observation.upsert',
        payload,
      );
      await store.update('conflicted', 'conflict');
      final container = ProviderContainer(
        overrides: [storeProvider.overrideWithValue(store)],
      );
      final model = container.read(modelProvider.notifier);
      model.session = {
        'farm': {'id': 'farm'},
        'user': {'id': 'user'},
      };
      await model.restoreConflict((await store.queue('farm:user')).single);
      expect(model.draft['note'], payload['note']);
      expect(model.draft['extent'], payload['extent']);
      expect(model.draft['location'], payload['location']);
      expect(model.draft['photoIds'], ['uploaded']);
      expect(model.draft['localPhotos'], ['/documents/pending.jpg']);
      expect(model.draft['parentObservationId'], 'obs');
      container.dispose();
      await store.db.close();
      store = await reopen();
      expect((await store.queue('farm:user')).single['payload'], payload);
      expect(
        (await store.get('draft:farm:user:field'))['note'],
        payload['note'],
      );
    },
  );

  test('synced operations are never resent', () async {
    await store.enqueue('alice', 'a', 'task.complete', {'id': 't'});
    final api = FakeApi();
    final engine = SyncEngine(store);
    await engine.drain('alice', api);
    await engine.drain('alice', api);
    expect(api.calls.length, 1);
  });
}
