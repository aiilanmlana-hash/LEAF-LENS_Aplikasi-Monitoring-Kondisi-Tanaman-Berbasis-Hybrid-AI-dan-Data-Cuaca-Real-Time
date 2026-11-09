import 'dart:typed_data';

class PlantAnalysis {
  const PlantAnalysis({
    required this.imageBytes,
    this.imageIsMirrored = false,
    required this.maskBytes,
    required this.greenRatio,
    required this.dryRatio,
    required this.prediction,
    required this.className,
    this.plantName,
    this.diseaseName,
    required this.aiConfidence,
    required this.annPrediction,
    required this.annConfidence,
    this.annError,
    required this.healthScore,
    required this.severity,
    required this.statusLabel,
    required this.carePriority,
    required this.careSummary,
    required this.careActions,
    required this.careDisclaimer,
    required this.organicRecommendations,
    required this.chemicalRecommendations,
    required this.untreatedImpact,
    this.temperatureC,
    this.humidityPct,
    this.precipitationMm,
    this.weatherSource,
    this.weatherStation,
    this.weatherError,
    required this.boundingBox,
    required this.imageWidth,
    required this.imageHeight,
    required this.createdAt,
    required this.plantId,
    required this.location,
  });

  final Uint8List imageBytes;
  final bool imageIsMirrored;
  final Uint8List maskBytes;
  final double greenRatio;
  final double dryRatio;
  final String prediction;
  final String className;
  final String? plantName;
  final String? diseaseName;
  final double? aiConfidence;
  final String? annPrediction;
  final double? annConfidence;
  final String? annError;
  final double? healthScore;
  final String severity;
  final String statusLabel;
  final String carePriority;
  final String careSummary;
  final List<String> careActions;
  final String careDisclaimer;
  final List<String> organicRecommendations;
  final List<String> chemicalRecommendations;
  final String untreatedImpact;
  final double? temperatureC;
  final double? humidityPct;
  final double? precipitationMm;
  final String? weatherSource;
  final String? weatherStation;
  final String? weatherError;
  final NormalizedBounds? boundingBox;
  final int imageWidth;
  final int imageHeight;
  final DateTime createdAt;
  final String plantId;
  final String location;
}

class NormalizedBounds {
  const NormalizedBounds({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  final double left;
  final double top;
  final double right;
  final double bottom;
}

class SegmentationResult {
  const SegmentationResult({
    required this.maskBytes,
    required this.greenRatio,
    required this.dryRatio,
    required this.boundingBox,
    required this.imageWidth,
    required this.imageHeight,
  });

  final Uint8List maskBytes;
  final double greenRatio;
  final double dryRatio;
  final NormalizedBounds? boundingBox;
  final int imageWidth;
  final int imageHeight;
}

(String, String) diagnosisStatusForPrediction(String className) {
  final separatorIndex = className.indexOf('___');
  if (separatorIndex <= 0 || separatorIndex + 3 >= className.length) {
    return ('HASIL AI PERLU DIVERIFIKASI', 'Perlu verifikasi');
  }

  final crop = className.substring(0, separatorIndex);
  final disease = className
      .substring(separatorIndex + 3)
      .replaceAll('_', ' ')
      .trim()
      .toLowerCase();
  if (!const {'Corn_(maize)', 'Potato', 'Tomato'}.contains(crop) ||
      disease.isEmpty) {
    return ('HASIL AI PERLU DIVERIFIKASI', 'Perlu verifikasi');
  }
  if (disease.split(RegExp(r'[^a-z]+')).contains('healthy')) {
    return ('DAUN HIJAU SEHAT', 'Sehat');
  }
  return ('TERSERANG PENYAKIT', 'Terserang Penyakit');
}
