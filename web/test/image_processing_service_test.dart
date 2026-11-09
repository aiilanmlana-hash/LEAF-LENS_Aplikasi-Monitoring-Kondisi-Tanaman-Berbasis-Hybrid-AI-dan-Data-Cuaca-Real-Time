import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:smart_plant_web/services/image_processing_service.dart';

void main() {
  const processor = ImageProcessingService();

  test(
    'segments green and dry leaf colors into white and gray mask pixels',
    () {
      final image = img.Image(width: 48, height: 32, numChannels: 3);
      for (var y = 0; y < image.height; y++) {
        for (var x = 0; x < image.width; x++) {
          if (x < image.width ~/ 2) {
            image.setPixelRgb(x, y, 25, 150, 30);
          } else {
            image.setPixelRgb(x, y, 190, 140, 20);
          }
        }
      }

      final bytes = Uint8List.fromList(img.encodePng(image));
      final result = processor.segment(
        bytes,
        hueMin: 25,
        hueMax: 95,
        saturationMin: 35,
        valueMin: 30,
        kernelSize: 3,
      );
      final mask = img.decodePng(result.maskBytes)!;
      final greenPixel = mask.getPixel(8, 16);
      final dryPixel = mask.getPixel(39, 16);

      expect(result.greenRatio, greaterThan(30));
      expect(result.dryRatio, greaterThan(30));
      expect(greenPixel.r, 255);
      expect(dryPixel.r, 150);
      expect(result.boundingBox, isNotNull);
    },
  );

  test('ignores a dark image using minimum HSV limits', () {
    final image = img.Image(width: 20, height: 20, numChannels: 3);
    final bytes = Uint8List.fromList(img.encodePng(image));

    final result = processor.segment(
      bytes,
      hueMin: 25,
      hueMax: 95,
      saturationMin: 35,
      valueMin: 30,
      kernelSize: 5,
    );

    expect(result.greenRatio, 0);
    expect(result.dryRatio, 0);
    expect(result.boundingBox, isNull);
  });

  test('corrects horizontal camera mirroring in image bytes', () {
    final image = img.Image(width: 2, height: 1, numChannels: 3)
      ..setPixelRgb(0, 0, 255, 0, 0)
      ..setPixelRgb(1, 0, 0, 0, 255);
    final bytes = Uint8List.fromList(img.encodePng(image));

    final corrected = img.decodeImage(
      processor.correctHorizontalMirror(bytes),
    )!;

    expect(corrected.getPixel(0, 0).b, greaterThan(240));
    expect(corrected.getPixel(1, 0).r, greaterThan(240));
  });
}
