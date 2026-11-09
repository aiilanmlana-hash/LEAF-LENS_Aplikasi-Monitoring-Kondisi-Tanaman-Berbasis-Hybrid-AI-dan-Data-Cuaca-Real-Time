import 'package:flutter/material.dart';

class PlantBackdrop extends StatelessWidget {
  const PlantBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    return const RepaintBoundary(
      child: ExcludeSemantics(
        child: Image(
          image: AssetImage('assets/landscape-soft.jpg'),
          fit: BoxFit.cover,
          filterQuality: FilterQuality.low,
        ),
      ),
    );
  }
}
