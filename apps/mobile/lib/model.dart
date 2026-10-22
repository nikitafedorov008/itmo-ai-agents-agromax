import 'dart:async';
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'generated/api_routes.dart';
import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';
import 'api.dart';
import 'storage.dart';
import 'sync.dart';

final storeProvider = Provider<LocalStore>((ref) => throw UnimplementedError());
final modelProvider = NotifierProvider<AppModel, int>(AppModel.new);
const uuid = Uuid();

class AppModel extends Notifier<int> {
  late LocalStore store;
  late SyncEngine engine;
  static const credentials = FlutterSecureStorage();
  Map<String, dynamic>? session;
  Map<String, dynamic> data = {};
  Map<String, dynamic> draft = {};
  String? activeField;
  Map<String, dynamic>? pendingChat;
  Map<String, String> conversationContexts = {};
  String get draftKey => 'draft:$account:${activeField ?? 'new'}';
  List<Map<String, dynamic>> queue = [];
  String? error;
  bool busy = false;
  String get account => '${session?['farm']['id']}:${session?['user']['id']}';
  Api get api => Api(session?['accessToken'] ?? '');
  @override
  int build() {
    store = ref.read(storeProvider);
    engine = SyncEngine(store);
    return 0;
  }

  void changed() => state++;
  Future<void> init() async {
    final saved = await credentials.read(key: 'session');
    session = saved == null
        ? null
        : Map<String, dynamic>.from(jsonDecode(saved));
    if (session != null) {
      await loadLocal();
      unawaited(sync());
    }
    changed();
  }

  Future<void> loadLocal() async {
    activeField = await store.get('activeField:$account');
    data = Map<String, dynamic>.from(await store.get('cache:$account') ?? {});
    draft = Map<String, dynamic>.from(await store.get(draftKey) ?? {});
    queue = await store.queue(account);
    pendingChat = await store.get('chat-pending:$account:$activeField');
    conversationContexts = Map<String, String>.from(
      await store.get('chat-contexts:$account:$activeField') ?? {},
    );
  }

  Future<void> login(
    String mode,
    String email,
    String password,
    String name,
  ) async {
    busy = true;
    error = null;
    changed();
    try {
      final result = await Api('').request(
        mode == 'demo'
            ? ApiRoutes.demo
            : mode == 'signup'
            ? ApiRoutes.signup
            : ApiRoutes.login,
        mode == 'demo'
            ? {}
            : {
                'email': email,
                'password': password,
                if (mode == 'signup') 'name': name,
              },
      );
      if (result['accessToken'] == null) {
        throw ApiFailure(400, 'Подтвердите почту перед входом');
      }
      session = result;
      await credentials.write(key: 'session', value: jsonEncode(session));
      await loadLocal();
      await refresh();
    } catch (e) {
      error = e is ApiFailure
          ? e.message
          : 'Не удалось подключиться к серверу.';
    } finally {
      busy = false;
      changed();
    }
  }

  Future<void> logout() async {
    session = null;
    data = {};
    draft = {};
    queue = [];
    await credentials.delete(key: 'session');
    changed();
  }

  Future<void> refresh() async {
    final scope = account;
    final remote = await api.request(ApiRoutes.bootstrap);
    await store.set('cache:$scope', remote);
    if (account == scope && session != null) {
      data = remote;
      if (activeField == null && (remote['fields'] as List).isNotEmpty) {
        await selectField(remote['fields'][0]['id']);
      }
      changed();
    }
  }

  Future<void> sync() async {
    if (session == null || busy) {
      return;
    }
    busy = true;
    error = null;
    changed();
    final scope = account;
    final client = api;
    try {
      await engine.drain(scope, client);
      if (account == scope && session != null) {
        await refresh();
      }
    } catch (e) {
      error = e is ApiFailure
          ? e.message
          : 'Нет связи с сервером. Локальные записи сохранены.';
    } finally {
      if (account == scope && session != null) {
        queue = await store.queue(scope);
        busy = false;
        changed();
      } else {
        busy = false;
      }
    }
  }

  Future<void> selectField(String id) async {
    activeField = id;
    pendingChat = await store.get('chat-pending:$account:$id');
    conversationContexts = Map<String, String>.from(
      await store.get('chat-contexts:$account:$id') ?? {},
    );
    await store.set('activeField:$account', id);
    draft = Map<String, dynamic>.from(await store.get(draftKey) ?? {});
    changed();
  }

  Future<void> editDraft(String key, dynamic value) async {
    draft[key] = value;
    await store.set(draftKey, draft);
    changed();
  }

  Future<void> preservePhoto(XFile file) async {
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory('${dir.path}/photos');
    await folder.create(recursive: true);
    final copied = await File(file.path).copy(
      '${folder.path}/${uuid.v4()}${p.extension(file.path).isEmpty ? '.jpg' : p.extension(file.path)}',
    );
    await editDraft('localPhotos', [
      ...List<String>.from(draft['localPhotos'] ?? []),
      copied.path,
    ]);
  }

  Future<void> recoverPhoto() async {
    if (!Platform.isAndroid || session == null) {
      return;
    }
    final response = await ImagePicker().retrieveLostData();
    for (final file in response.files ?? <XFile>[]) {
      await preservePhoto(file);
    }
    if (response.exception != null) {
      error = response.exception.toString();
      changed();
    }
  }

  Future<void> enqueue(String type, Map<String, dynamic> payload) async {
    await store.enqueue(account, uuid.v4(), type, payload);
    queue = await store.queue(account);
    changed();
  }

  Future<void> restoreConflict(Map<String, dynamic> operation) async {
    final payload = Map<String, dynamic>.from(operation['payload']);
    await selectField(payload['fieldId']);
    draft = {
      for (final key in [
        'note',
        'extent',
        'location',
        'photoIds',
        'localPhotos',
      ])
        if (payload[key] != null) key: payload[key],
      'parentObservationId': payload['id'],
    };
    await store.set(draftKey, draft);
    changed();
  }

  Future<void> saveDraft(String fieldId) async {
    if ((draft['note'] ?? '').toString().trim().isEmpty) {
      throw Exception('Добавьте описание наблюдения');
    }
    await store.queueDraft(account, uuid.v4(), draftKey, {
      'id': uuid.v4(),
      'fieldId': fieldId,
      'note': draft['note'],
      'extent': draft['extent'] ?? '',
      'photoIds': List<String>.from(draft['photoIds'] ?? []),
      if (draft['location'] != null) 'location': draft['location'],
      if (draft['parentObservationId'] != null)
        'parentObservationId': draft['parentObservationId'],
      'localPhotos': draft['localPhotos'] ?? [],
    });
    draft = {};
    queue = await store.queue(account);
    changed();
    unawaited(sync());
  }
}
