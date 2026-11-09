import 'package:flutter/foundation.dart';

import '../models/monitoring_record.dart';
import '../services/legacy_history_migrator.dart';
import '../services/monitoring_repository.dart';
import '../services/plant_api_service.dart';

class MonitoringProvider extends ChangeNotifier {
  MonitoringProvider({
    MonitoringRepository? repository,
    PlantApiService? api,
  })  : _repository = repository ?? MonitoringRepository(),
        _api = api ?? PlantApiService();

  final MonitoringRepository _repository;
  final PlantApiService _api;
  List<MonitoringRecord> _records = [];
  bool isBusy = false;
  String? errorMessage;

  List<MonitoringRecord> get records => List.unmodifiable(_records);

  Future<void> initialize() async {
    try {
      final legacyRecords = await LegacyHistoryMigrator.loadUnmigratedRecords();
      for (final legacyRecord in legacyRecords) {
        final maskBase64 = legacyRecord.maskBase64.isEmpty
            ? ''
            : await _repository.prepareMask(legacyRecord.maskBase64);
        await _repository.saveRecord(
          legacyRecord.copyWith(maskBase64: maskBase64),
        );
      }
      await LegacyHistoryMigrator.markMigrationComplete();
      _records = await _repository.getRecords();
      notifyListeners();
    } catch (error) {
      errorMessage = 'Tidak dapat memuat riwayat Firebase: $error';
      notifyListeners();
    }
  }

  Future<MonitoringRecord?> analyze({
    required Uint8List imageBytes,
    required String imageName,
    required String plantId,
    required String location,
    required bool flipHorizontal,
    required int hueMin,
    required int hueMax,
    required int saturationMin,
    required int valueMin,
    required int kernelSize,
  }) async {
    isBusy = true;
    errorMessage = null;
    notifyListeners();
    try {
      final result = await _api.analyze(
        imageBytes: imageBytes,
        imageName: imageName,
        plantId: plantId,
        location: location,
        flipHorizontal: flipHorizontal,
        hueMin: hueMin,
        hueMax: hueMax,
        saturationMin: saturationMin,
        valueMin: valueMin,
        kernelSize: kernelSize,
      );
      final maskBase64 = result['mask_base64'] as String?;
      if (maskBase64 == null || maskBase64.isEmpty) {
        throw const FormatException('The API response did not contain a mask.');
      }
      result['mask_base64'] = await _repository.prepareMask(maskBase64);
      final record = MonitoringRecord.fromApi(result);
      await _repository.saveRecord(record);
      _records = await _repository.getRecords();
      return record;
    } catch (error) {
      errorMessage = 'Analisis tanaman gagal: $error';
      return null;
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }
}
