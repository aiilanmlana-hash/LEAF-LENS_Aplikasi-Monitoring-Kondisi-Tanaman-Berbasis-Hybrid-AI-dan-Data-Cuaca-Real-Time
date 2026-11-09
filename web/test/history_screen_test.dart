import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_plant_web/screens/history_screen.dart';
import 'package:smart_plant_web/services/monitoring_repository.dart';
import 'package:smart_plant_web/theme/app_theme.dart';

void main() {
  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(768, 1024),
    const Size(900, 768),
    const Size(1024, 768),
    const Size(1440, 900),
    const Size(1920, 1080),
  ]) {
    testWidgets('History screen fits ${size.width}px layout', (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          theme: PlantTheme.light,
          home: HistoryScreen(repository: _FakeMonitoringRepository()),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Riwayat monitoring'), findsOneWidget);
      expect(find.text('Prediksi AI'), findsOneWidget);
      expect(find.byTooltip('Hapus data'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

class _FakeMonitoringRepository implements MonitoringRepository {
  @override
  Stream<List<Map<String, dynamic>>> watchRecords() => Stream.value([
    {
      '_document_id': 'test-record',
      'timestamp': Timestamp.fromDate(DateTime(2026, 11, 4, 21, 54)),
      'plant_id': 'P001',
      'location': 'Polije Sidoarjo',
      'green_ratio': 45.2,
      'yellow_ratio': 3.8,
      'prediction': 'Tomato - Early blight',
      'health_score': 82.4,
      'severity': 'Sehat',
      'mask_base64': '',
    },
  ]);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
