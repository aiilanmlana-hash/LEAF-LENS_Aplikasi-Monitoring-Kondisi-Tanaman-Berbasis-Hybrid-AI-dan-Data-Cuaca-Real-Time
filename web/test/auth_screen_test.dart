import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_plant_web/screens/auth_screen.dart';
import 'package:smart_plant_web/theme/app_theme.dart';

void main() {
  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(768, 1024),
    const Size(900, 768),
    const Size(1024, 768),
    const Size(1440, 900),
  ]) {
    testWidgets('Auth screen fits ${size.width}px layout', (tester) async {
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetDevicePixelRatio);
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetPhysicalSize);
      await tester.pumpWidget(
        MaterialApp(theme: PlantTheme.light, home: const AuthScreen()),
      );
      await tester.pumpAndSettle();

      expect(find.text('LEAF LENS'), findsOneWidget);
      expect(find.text('Masuk'), findsWidgets);
      expect(find.text('Masuk dengan Google'), findsOneWidget);
      final exception = tester.takeException();
      expect(exception, isNull);
    });
  }

  testWidgets('Auth screen honors reduced-motion preference', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: PlantTheme.light,
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: const AuthScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('LEAF LENS'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Google sign-in label follows login/register mode', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(theme: PlantTheme.light, home: const AuthScreen()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Masuk dengan Google'), findsOneWidget);
    await tester.tap(find.text('Buat akun').first);
    await tester.pumpAndSettle();
    expect(find.text('Daftar dengan Google'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
