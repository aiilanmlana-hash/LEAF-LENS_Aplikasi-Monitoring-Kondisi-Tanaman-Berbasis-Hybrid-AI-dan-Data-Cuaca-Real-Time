import '../models/monitoring_record.dart';
import 'legacy_history_migrator_stub.dart'
    if (dart.library.io) 'legacy_history_migrator_io.dart' as implementation;

abstract final class LegacyHistoryMigrator {
  static Future<List<MonitoringRecord>> loadUnmigratedRecords() =>
      implementation.loadUnmigratedRecords();

  static Future<void> markMigrationComplete() =>
      implementation.markMigrationComplete();
}
