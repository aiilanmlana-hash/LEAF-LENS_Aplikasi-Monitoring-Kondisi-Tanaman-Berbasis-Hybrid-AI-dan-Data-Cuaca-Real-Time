import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/plant_analysis.dart';

class MonitoringRepository {
  static const _historyLimit = 100;
  MonitoringRepository({FirebaseFirestore? firestore, FirebaseAuth? auth})
    : _firestore = firestore ?? FirebaseFirestore.instance,
      _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  CollectionReference<Map<String, dynamic>> get _records =>
      _firestore.collection('monitoring_records');

  Stream<List<Map<String, dynamic>>> watchRecords() {
    final user = _auth.currentUser;
    if (user == null) {
      return Stream.error(StateError('Silakan masuk untuk melihat riwayat.'));
    }
    // Fetch only the newest records. Loading every base64 mask for a long
    // history makes initial login and scrolling increasingly expensive.
    return _records
        .where('user_id', isEqualTo: user.uid)
        .orderBy('timestamp', descending: true)
        .limit(_historyLimit)
        .snapshots()
        .map(
          (snapshot) => snapshot.docs
              .map(
                (document) => {...document.data(), '_document_id': document.id},
              )
              .toList(),
        );
  }

  Future<void> saveAnalysis({
    required PlantAnalysis analysis,
    required Uint8List maskThumbnail,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Silakan masuk sebelum menyimpan data.');

    final maskBase64 = base64Encode(maskThumbnail);
    if (maskBase64.length > 650000) {
      throw StateError(
        'Mask masih terlalu besar untuk disimpan aman di Firestore.',
      );
    }

    final record = <String, Object?>{
      'user_id': user.uid,
      'plant_id': analysis.plantId,
      'location': analysis.location,
      'timestamp': Timestamp.fromDate(analysis.createdAt),
      'green_ratio': analysis.greenRatio,
      'yellow_ratio': analysis.dryRatio,
      'prediction': analysis.prediction,
      'plant_name': analysis.plantName,
      'disease_name': analysis.diseaseName,
      'confidence': analysis.aiConfidence,
      'ann_prediction': analysis.annPrediction,
      'ann_confidence': analysis.annConfidence,
      'health_score': analysis.healthScore,
      'severity': analysis.severity,
      'status_label': analysis.statusLabel,
      'care_priority': analysis.carePriority,
      'care_summary': analysis.careSummary,
      'care_actions': analysis.careActions,
      'care_disclaimer': analysis.careDisclaimer,
      'organic_recommendations': analysis.organicRecommendations,
      'chemical_recommendations': analysis.chemicalRecommendations,
      'untreated_impact': analysis.untreatedImpact,
      'temperature_c': analysis.temperatureC,
      'humidity_pct': analysis.humidityPct,
      'precipitation_mm': analysis.precipitationMm,
      'weather_source': analysis.weatherSource,
      'weather_station': analysis.weatherStation,
      'weather_error': analysis.weatherError,
      'mask_base64': maskBase64,
    };

    await _records.doc().set(record);
  }

  Future<void> deleteRecord(String documentId) async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Silakan masuk sebelum menghapus data.');
    final document = _records.doc(documentId);
    final snapshot = await document.get();
    if (snapshot.data()?['user_id'] != user.uid) {
      throw StateError('Dokumen ini bukan milik akun yang sedang masuk.');
    }
    await document.delete();
  }

  Future<int> deleteAllRecords() async {
    final user = _auth.currentUser;
    if (user == null) throw StateError('Silakan masuk sebelum menghapus data.');

    final snapshot = await _records.where('user_id', isEqualTo: user.uid).get();
    var deleted = 0;
    for (var start = 0; start < snapshot.docs.length; start += 450) {
      final batch = _firestore.batch();
      final documents = snapshot.docs.skip(start).take(450);
      for (final document in documents) {
        batch.delete(document.reference);
        deleted++;
      }
      await batch.commit();
    }
    return deleted;
  }

  static Uint8List? decodeMask(String? value) {
    if (value == null || value.isEmpty) return null;
    return base64Decode(value);
  }
}
