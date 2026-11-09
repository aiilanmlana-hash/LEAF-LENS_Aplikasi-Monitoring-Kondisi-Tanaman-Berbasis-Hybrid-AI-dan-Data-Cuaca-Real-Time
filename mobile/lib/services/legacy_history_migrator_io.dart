import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:sqflite/sqflite.dart';

import '../models/monitoring_record.dart';

const _migrationTable = 'app_migrations';
const _migrationId = 'firestore_history_v1';

Future<Database?> _openLegacyDatabase() async {
  final databasePath = path.join(await getDatabasesPath(), 'smart_plant.db');
  if (!await databaseExists(databasePath)) return null;
  return openDatabase(databasePath);
}

Future<bool> _hasCompletedMigration(Database database) async {
  final tables = await database.rawQuery(
    "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
    [_migrationTable],
  );
  if (tables.isEmpty) return false;
  final rows = await database.query(
    _migrationTable,
    where: 'migration_id = ?',
    whereArgs: [_migrationId],
    limit: 1,
  );
  return rows.isNotEmpty;
}

Future<List<MonitoringRecord>> loadUnmigratedRecords() async {
  final database = await _openLegacyDatabase();
  if (database == null) return [];
  try {
    if (await _hasCompletedMigration(database)) return [];
    final tables = await database.rawQuery(
      "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
      ['monitoring_records'],
    );
    if (tables.isEmpty) return [];
    final rows = await database.query('monitoring_records');
    final records = <MonitoringRecord>[];
    for (final row in rows) {
      final pathValue = row['mask_path'] as String? ?? '';
      final maskFile = pathValue.isEmpty ? null : File(pathValue);
      final maskBase64 = maskFile != null && await maskFile.exists()
          ? base64Encode(await maskFile.readAsBytes())
          : '';
      records.add(
        MonitoringRecord.fromMap({
          ...row,
          'mask_base64': maskBase64,
        }),
      );
    }
    return records;
  } finally {
    await database.close();
  }
}

Future<void> markMigrationComplete() async {
  final database = await _openLegacyDatabase();
  if (database == null) return;
  try {
    await database.execute('''
      CREATE TABLE IF NOT EXISTS $_migrationTable (
        migration_id TEXT PRIMARY KEY,
        completed_at TEXT NOT NULL
      )
    ''');
    await database.insert(
      _migrationTable,
      {
        'migration_id': _migrationId,
        'completed_at': DateTime.now().toUtc().toIso8601String(),
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  } finally {
    await database.close();
  }
}
