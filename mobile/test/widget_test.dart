// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smart_plant_monitoring/main.dart';
import 'package:smart_plant_monitoring/providers/monitoring_provider.dart';
import 'package:smart_plant_monitoring/screens/dashboard_screen.dart';
import 'package:smart_plant_monitoring/screens/history_screen.dart';
import 'package:smart_plant_monitoring/screens/scan_screen.dart';
import 'package:smart_plant_monitoring/theme/app_theme.dart';

void main() {
  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(768, 1024),
    const Size(1440, 900),
  ]) {
    testWidgets('Dashboard fits ${size.width}px layout', (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        ChangeNotifierProvider(
          create: (_) => MonitoringProvider(),
          child: SmartPlantApp(
            home: Scaffold(
              body: DashboardScreen(onScan: () {}),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Kondisi kebun Anda'), findsOneWidget);
      expect(find.text('Mulai analisis'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('History fits a compact phone layout', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ChangeNotifierProvider(
          create: (_) => MonitoringProvider(),
          child: const Scaffold(body: HistoryScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Riwayat monitoring'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Scan controls fit a compact phone layout', (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: ChangeNotifierProvider(
          create: (_) => MonitoringProvider(),
          child: const Scaffold(body: ScanScreen(isActive: false)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Segmentasi daun'), findsOneWidget);
    expect(find.text('Galeri / file'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
