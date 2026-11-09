import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:image/image.dart' as img;

import '../models/monitoring_record.dart';

class MonitoringRepository {
  MonitoringRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _providedFirestore = firestore,
        _providedAuth = auth;

  final FirebaseFirestore? _providedFirestore;
  final FirebaseAuth? _providedAuth;

  FirebaseFirestore get _firestore =>
      _providedFirestore ?? FirebaseFirestore.instance;

  FirebaseAuth get _auth => _providedAuth ?? FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> get _records {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Sign in before accessing monitoring history.');
    }
    return _firestore
        .collection('users')
        .doc(user.uid)
        .collection('monitoring_records');
  }

  Future<String> prepareMask(String base64Mask) async {
    final decoded = img.decodeImage(base64Decode(base64Mask));
    if (decoded == null) {
      throw const FormatException('The API returned an invalid mask image.');
    }
    final scale = math.min(1.0, 320 / math.max(decoded.width, decoded.height));
    final thumbnail = img.copyResize(
      decoded,
      width: math.max(1, (decoded.width * scale).round()),
      height: math.max(1, (decoded.height * scale).round()),
      interpolation: img.Interpolation.average,
    );
    return base64Encode(img.encodePng(thumbnail));
  }

  Future<void> saveRecord(MonitoringRecord record) async {
    await _records.doc(record.id).set(record.toFirestore());
  }

  Future<List<MonitoringRecord>> getRecords() async {
    final snapshot =
        await _records.orderBy('timestamp', descending: true).get();
    return snapshot.docs
        .map((document) => MonitoringRecord.fromFirestore(document.data()))
        .toList(growable: false);
  }
}
