import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../models/plant_analysis.dart';

class ImageProcessingService {
  const ImageProcessingService();

  Uint8List correctHorizontalMirror(Uint8List bytes) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw const FormatException('File gambar tidak dapat dibaca.');
    }
    return Uint8List.fromList(img.encodeJpg(img.flipHorizontal(decoded)));
  }

  SegmentationResult segment(
    Uint8List bytes, {
    required int hueMin,
    required int hueMax,
    required int saturationMin,
    required int valueMin,
    required int kernelSize,
  }) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw const FormatException('File gambar tidak dapat dibaca.');
    }

    final scale = math.min(1.0, 640 / math.max(decoded.width, decoded.height));
    final source = scale < 1
        ? img.copyResize(
            decoded,
            width: math.max(1, (decoded.width * scale).round()),
            height: math.max(1, (decoded.height * scale).round()),
            interpolation: img.Interpolation.average,
          )
        : decoded;
    final width = source.width;
    final height = source.height;
    final count = width * height;
    final green = Uint8List(count);
    final dry = Uint8List(count);

    // This browser-side pass uses HSV ranges only; K-Means runs in the Python API.
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final pixel = source.getPixel(x, y);
        final hsv = _rgbToHsv(
          pixel.r.toDouble(),
          pixel.g.toDouble(),
          pixel.b.toDouble(),
        );
        final index = y * width + x;
        if (hsv.$1 >= hueMin &&
            hsv.$1 <= hueMax &&
            hsv.$2 >= saturationMin &&
            hsv.$3 >= valueMin) {
          green[index] = 1;
        }
        if (hsv.$1 >= 15 && hsv.$1 <= 30 && hsv.$2 >= 40 && hsv.$3 >= 40) {
          dry[index] = 1;
        }
      }
    }

    // Clean isolated pixels and small holes before calculating preview ratios.
    final greenClean = _openThenClose(green, width, height, kernelSize);
    final dryClean = _openThenClose(dry, width, height, kernelSize);
    final mask = img.Image(width: width, height: height, numChannels: 4);
    var greenPixels = 0;
    var dryPixels = 0;
    var minX = width;
    var minY = height;
    var maxX = -1;
    var maxY = -1;

    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final index = y * width + x;
        if (greenClean[index] == 1) {
          greenPixels++;
          mask.setPixelRgba(x, y, 255, 255, 255, 255);
        } else if (dryClean[index] == 1) {
          dryPixels++;
          mask.setPixelRgba(x, y, 150, 150, 150, 255);
        } else {
          mask.setPixelRgba(x, y, 0, 0, 0, 255);
        }
        if (greenClean[index] == 1 || dryClean[index] == 1) {
          minX = math.min(minX, x);
          minY = math.min(minY, y);
          maxX = math.max(maxX, x);
          maxY = math.max(maxY, y);
        }
      }
    }

    final bounds = maxX < 0
        ? null
        : NormalizedBounds(
            left: minX / width,
            top: minY / height,
            right: (maxX + 1) / width,
            bottom: (maxY + 1) / height,
          );
    return SegmentationResult(
      maskBytes: Uint8List.fromList(img.encodePng(mask)),
      greenRatio: greenPixels * 100 / count,
      dryRatio: dryPixels * 100 / count,
      boundingBox: bounds,
      imageWidth: width,
      imageHeight: height,
    );
  }

  Uint8List createFirestoreThumbnail(Uint8List pngBytes) {
    final decoded = img.decodeImage(pngBytes);
    if (decoded == null) {
      throw const FormatException('Mask segmentasi tidak dapat diproses.');
    }
    final scale = math.min(1.0, 280 / math.max(decoded.width, decoded.height));
    final thumbnail = img.copyResize(
      decoded,
      width: math.max(1, (decoded.width * scale).round()),
      height: math.max(1, (decoded.height * scale).round()),
      interpolation: img.Interpolation.nearest,
    );
    return Uint8List.fromList(img.encodePng(thumbnail));
  }

  Uint8List decodeBase64Mask(String base64) {
    final decoded = UriData.parse('data:image/png;base64,$base64')
        .contentAsBytes();
    return createFirestoreThumbnail(decoded);
  }

  Uint8List _openThenClose(
    Uint8List input,
    int width,
    int height,
    int kernelSize,
  ) {
    final eroded = _morph(input, width, height, kernelSize, erode: true);
    final opened = _morph(eroded, width, height, kernelSize, erode: false);
    final dilated = _morph(opened, width, height, kernelSize, erode: false);
    return _morph(dilated, width, height, kernelSize, erode: true);
  }

  Uint8List _morph(
    Uint8List input,
    int width,
    int height,
    int kernelSize, {
    required bool erode,
  }) {
    final radius = kernelSize ~/ 2;
    final horizontal = Uint8List(input.length);
    final output = Uint8List(input.length);
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        var value = erode ? 1 : 0;
        for (
          var offset = -radius;
          offset <= radius && (erode ? value == 1 : value == 0);
          offset++
        ) {
          final neighborX = x + offset;
          final pixel = neighborX >= 0 && neighborX < width
              ? input[y * width + neighborX]
              : 0;
          if (erode && pixel == 0) value = 0;
          if (!erode && pixel == 1) value = 1;
        }
        horizontal[y * width + x] = value;
      }
    }
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        var value = erode ? 1 : 0;
        for (
          var offset = -radius;
          offset <= radius && (erode ? value == 1 : value == 0);
          offset++
        ) {
          final neighborY = y + offset;
          final pixel = neighborY >= 0 && neighborY < height
              ? horizontal[neighborY * width + x]
              : 0;
          if (erode && pixel == 0) value = 0;
          if (!erode && pixel == 1) value = 1;
        }
        output[y * width + x] = value;
      }
    }
    return output;
  }

  (double, double, double) _rgbToHsv(double red, double green, double blue) {
    final r = red / 255;
    final g = green / 255;
    final b = blue / 255;
    final maxValue = math.max(r, math.max(g, b));
    final minValue = math.min(r, math.min(g, b));
    final delta = maxValue - minValue;
    var hue = 0.0;
    if (delta != 0) {
      if (maxValue == r) {
        hue = 60 * (((g - b) / delta) % 6);
      } else if (maxValue == g) {
        hue = 60 * (((b - r) / delta) + 2);
      } else {
        hue = 60 * (((r - g) / delta) + 4);
      }
    }
    if (hue < 0) hue += 360;
    final saturation = maxValue == 0 ? 0.0 : delta / maxValue;
    return (hue / 2, saturation * 255, maxValue * 255);
  }
}
