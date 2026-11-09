import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_plant_web/main.dart';

void main() {
  testWidgets('Web application accepts an injectable home', (tester) async {
    await tester.pumpWidget(const SmartPlantWebApp(home: _TestHome()));

    expect(find.text('LEAF LENS test surface'), findsOneWidget);
  });
}

class _TestHome extends StatelessWidget {
  const _TestHome();

  @override
  Widget build(BuildContext context) =>
      const Text('LEAF LENS test surface');
}
