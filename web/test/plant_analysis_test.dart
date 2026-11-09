import 'package:flutter_test/flutter_test.dart';
import 'package:smart_plant_web/models/plant_analysis.dart';

void main() {
  test('only supported healthy class labels receive the healthy status', () {
    for (final className in [
      'Corn_(maize)___healthy',
      'Potato___healthy',
      'Tomato___healthy',
    ]) {
      expect(diagnosisStatusForPrediction(className), (
        'DAUN HIJAU SEHAT',
        'Sehat',
      ));
    }
  });

  test('diseased predictions stay diseased even when leaf color is green', () {
    expect(diagnosisStatusForPrediction('Potato___Early_blight'), (
      'TERSERANG PENYAKIT',
      'Terserang Penyakit',
    ));
    expect(diagnosisStatusForPrediction('Tomato___Late_blight'), (
      'TERSERANG PENYAKIT',
      'Terserang Penyakit',
    ));
    expect(diagnosisStatusForPrediction('Corn_(maize)___Common_rust_'), (
      'TERSERANG PENYAKIT',
      'Terserang Penyakit',
    ));
  });

  test('healthy status follows the healthy token in the model label', () {
    expect(diagnosisStatusForPrediction('Tomato___healthy_leaf'), (
      'DAUN HIJAU SEHAT',
      'Sehat',
    ));
    expect(diagnosisStatusForPrediction('Tomato___unhealthy'), (
      'TERSERANG PENYAKIT',
      'Terserang Penyakit',
    ));
  });

  test('malformed or unsupported class names need verification', () {
    expect(diagnosisStatusForPrediction('Background_or_Invalid'), (
      'HASIL AI PERLU DIVERIFIKASI',
      'Perlu verifikasi',
    ));
    expect(diagnosisStatusForPrediction('Apple___healthy'), (
      'HASIL AI PERLU DIVERIFIKASI',
      'Perlu verifikasi',
    ));
    expect(diagnosisStatusForPrediction('Tomato__healthy'), (
      'HASIL AI PERLU DIVERIFIKASI',
      'Perlu verifikasi',
    ));
  });
}
