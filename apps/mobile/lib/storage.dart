import 'dart:convert';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;

class LocalStore {
  LocalStore(this.db);
  final Database db;
  static Future<LocalStore> open() async => LocalStore(
    await openDatabase(
      p.join(await getDatabasesPath(), 'agromax.db'),
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
  );
  Future<dynamic> get(String key) async {
    final rows = await db.query('kv', where: 'key=?', whereArgs: [key]);
    return rows.isEmpty ? null : jsonDecode(rows.first['value'] as String);
  }

  Future<void> set(String key, dynamic value) async {
    await db.insert('kv', {
      'key': key,
      'value': jsonEncode(value),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> enqueue(
    String account,
    String id,
    String type,
    Map<String, dynamic> payload,
  ) async {
    await db.insert('outbox', {
      'operationId': id,
      'account': account,
      'type': type,
      'payload': jsonEncode(payload),
      'status': 'local',
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<void> queueDraft(
    String account,
    String operationId,
    String draftKey,
    Map<String, dynamic> payload,
  ) async {
    await db.transaction((tx) async {
      await tx.insert('outbox', {
        'operationId': operationId,
        'account': account,
        'type': 'observation.upsert',
        'payload': jsonEncode(payload),
        'status': 'local',
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      });
      await tx.insert('kv', {
        'key': draftKey,
        'value': '{}',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    });
  }

  Future<List<Map<String, dynamic>>> queue(String account) async =>
      (await db.query(
            'outbox',
            where: 'account=?',
            whereArgs: [account],
            orderBy: 'createdAt ASC, rowid ASC',
          ))
          .map((r) => {...r, 'payload': jsonDecode(r['payload'] as String)})
          .toList();
  Future<void> update(
    String id,
    String status, {
    String? error,
    Map<String, dynamic>? payload,
  }) async {
    await db.update(
      'outbox',
      {
        'status': status,
        'error': error,
        if (payload != null) 'payload': jsonEncode(payload),
      },
      where: 'operationId=?',
      whereArgs: [id],
    );
  }

  Future<void> recover(String account) async {
    await db.rawUpdate(
      "UPDATE outbox SET status='local' WHERE account=? AND status='sending'",
      [account],
    );
  }
}
