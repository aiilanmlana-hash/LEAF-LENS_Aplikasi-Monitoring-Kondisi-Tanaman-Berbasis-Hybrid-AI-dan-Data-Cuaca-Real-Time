import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_plant_monitoring/screens/auth_screen.dart';
import 'package:smart_plant_monitoring/theme/app_theme.dart';

void main() {
  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(768, 1024),
    const Size(1024, 768),
  ]) {
    testWidgets('Auth screen fits ${size.width}px layout', (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(theme: AppTheme.light, home: const AuthScreen()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Smart Plant'), findsOneWidget);
      expect(find.text('Masuk'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  }
}
