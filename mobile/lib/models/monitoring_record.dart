import 'package:cloud_firestore/cloud_firestore.dart';

class MonitoringRecord {
  const MonitoringRecord({
    required this.id,
    required this.timestamp,
    required this.plantId,
    required this.location,
    required this.greenRatio,
    required this.yellowRatio,
    required this.prediction,
    required this.confidence,
    required this.healthScore,
    required this.severity,
    required this.maskBase64,
  });

  final String id;
  final DateTime timestamp;
  final String plantId;
  final String location;
  final double greenRatio;
  final double yellowRatio;
  final String prediction;
  final double confidence;
  final double healthScore;
  final String severity;
  final String maskBase64;

  factory MonitoringRecord.fromApi(Map<String, dynamic> json) {
    return MonitoringRecord(
      id: json['id'] as String,
      timestamp: DateTime.parse(json['timestamp'] as String).toUtc(),
      plantId: json['plant_id'] as String,
      location: json['location'] as String,
      greenRatio: (json['green_ratio'] as num).toDouble(),
      yellowRatio: (json['yellow_ratio'] as num).toDouble(),
      prediction: json['prediction'] as String,
      confidence: (json['confidence'] as num).toDouble(),
      healthScore: (json['health_score'] as num).toDouble(),
      severity: json['severity'] as String,
      maskBase64: json['mask_base64'] as String,
    );
  }

  factory MonitoringRecord.fromMap(Map<String, Object?> map) {
    return MonitoringRecord(
      id: map['id']! as String,
      timestamp: DateTime.parse(map['timestamp']! as String),
      plantId: map['plant_id']! as String,
      location: map['location']! as String,
      greenRatio: (map['green_ratio']! as num).toDouble(),
      yellowRatio: (map['yellow_ratio']! as num).toDouble(),
      prediction: map['prediction']! as String,
      confidence: (map['confidence']! as num).toDouble(),
      healthScore: (map['health_score']! as num).toDouble(),
      severity: map['severity']! as String,
      maskBase64: map['mask_base64'] as String? ?? '',
    );
  }

  factory MonitoringRecord.fromFirestore(Map<String, dynamic> map) {
    return MonitoringRecord(
      id: map['id'] as String,
      timestamp: (map['timestamp'] as Timestamp).toDate(),
      plantId: map['plant_id'] as String,
      location: map['location'] as String,
      greenRatio: (map['green_ratio'] as num).toDouble(),
      yellowRatio: (map['yellow_ratio'] as num).toDouble(),
      prediction: map['prediction'] as String,
      confidence: (map['confidence'] as num).toDouble(),
      healthScore: (map['health_score'] as num).toDouble(),
      severity: map['severity'] as String,
      maskBase64: map['mask_base64'] as String? ?? '',
    );
  }

  Map<String, Object?> toMap() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'plant_id': plantId,
        'location': location,
        'green_ratio': greenRatio,
        'yellow_ratio': yellowRatio,
        'prediction': prediction,
        'confidence': confidence,
        'health_score': healthScore,
        'severity': severity,
        'mask_base64': maskBase64,
      };

  Map<String, Object?> toFirestore() => {
        ...toMap(),
        'timestamp': timestamp,
      };

  MonitoringRecord copyWith({String? maskBase64}) => MonitoringRecord(
        id: id,
        timestamp: timestamp,
        plantId: plantId,
        location: location,
        greenRatio: greenRatio,
        yellowRatio: yellowRatio,
        prediction: prediction,
        confidence: confidence,
        healthScore: healthScore,
        severity: severity,
        maskBase64: maskBase64 ?? this.maskBase64,
      );
}
