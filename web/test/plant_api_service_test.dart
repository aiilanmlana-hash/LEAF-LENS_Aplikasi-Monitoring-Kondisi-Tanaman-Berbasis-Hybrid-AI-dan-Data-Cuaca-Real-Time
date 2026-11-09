import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smart_plant_web/services/plant_api_service.dart';

void main() {
  test(
    'reports an unreachable backend with a friendly connection message',
    () async {
      final service = PlantApiService(
        client: MockClient(
          (_) async => throw http.ClientException('Failed to fetch'),
        ),
        idTokenProvider: () async => null,
      );
      addTearDown(service.dispose);

      await expectLater(
        _classify(service),
        throwsA(
          isA<PlantApiException>()
              .having((error) => error.code, 'code', 'api_unavailable')
              .having(
                (error) => error.message,
                'message',
                'Layanan analisis tidak dapat dijangkau. Pastikan server aktif lalu coba lagi.',
              ),
        ),
      );
    },
  );

  test('hides internal backend errors behind a friendly message', () async {
    final service = PlantApiService(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({'detail': 'RuntimeError: internal checkpoint path'}),
          500,
        ),
      ),
      idTokenProvider: () async => null,
    );
    addTearDown(service.dispose);

    await expectLater(
      _classify(service),
      throwsA(
        isA<PlantApiException>().having(
          (error) => error.message,
          'message',
          'Layanan analisis sedang bermasalah. Silakan coba lagi nanti.',
        ),
      ),
    );
  });

  test('sends optional coordinates and preserves the OOD error code', () async {
    final client = MockClient((request) async {
      expect(request, isA<http.Request>());
      expect(request.body, contains('name="latitude"'));
      expect(request.body, contains('-7.45'));
      expect(request.body, contains('name="longitude"'));
      expect(request.body, contains('112.72'));
      expect(request.body, contains('name="flip_horizontal"'));
      expect(request.body, contains('true'));
      return http.Response(
        '{"detail":{"status":"error","code":"ood_image","message":"Objek tidak terverifikasi sebagai daun tanaman hidup. Pastikan daun tanaman asli berada di dalam bingkai dengan pencahayaan terang."}}',
        422,
      );
    });
    final service = PlantApiService(
      client: client,
      baseUrl: 'http://localhost:8000',
      idTokenProvider: () async => null,
    );

    await expectLater(
      service.classify(
        imageBytes: Uint8List.fromList([1, 2, 3]),
        imageName: 'leaf.jpg',
        plantId: 'P001',
        location: 'Sidoarjo',
        hueMin: 25,
        hueMax: 95,
        saturationMin: 35,
        valueMin: 30,
        kernelSize: 5,
        flipHorizontal: true,
        latitude: -7.45,
        longitude: 112.72,
      ),
      throwsA(
        isA<PlantApiException>()
            .having((error) => error.statusCode, 'statusCode', 422)
            .having((error) => error.code, 'code', 'ood_image')
            .having(
              (error) => error.message,
              'message',
              'Objek tidak terverifikasi sebagai daun tanaman hidup. Pastikan daun tanaman asli berada di dalam bingkai dengan pencahayaan terang.',
            ),
      ),
    );
    client.close();
  });

  test('preserves low-confidence prediction from API', () async {
    final service = PlantApiService(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({'prediction': 'Tomato___healthy', 'confidence': 0.1}),
          200,
        ),
      ),
      idTokenProvider: () async => null,
    );
    addTearDown(service.dispose);

    final result = await _classify(service);

    expect(result['prediction'], 'Tomato___healthy');
    expect(result['confidence'], 0.1);
  });

  test('accepts a supported crop at exactly 10 percent confidence', () async {
    final service = PlantApiService(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({'prediction': 'Tomato___healthy', 'confidence': 10}),
          200,
        ),
      ),
      idTokenProvider: () async => null,
    );
    addTearDown(service.dispose);

    final result = await _classify(service);

    expect(result['prediction'], 'Tomato___healthy');
  });

  test('accepts Background_or_Invalid prediction from the API', () async {
    final service = PlantApiService(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({'prediction': 'Background_or_Invalid', 'confidence': 99}),
          200,
        ),
      ),
      idTokenProvider: () async => null,
    );
    addTearDown(service.dispose);

    final result = await _classify(service);

    expect(result['prediction'], 'Background_or_Invalid');
  });

  test('preserves unsupported class and low confidence from API', () async {
    final service = PlantApiService(
      client: MockClient(
        (_) async => http.Response(
          jsonEncode({'prediction': 'Apple___healthy', 'confidence': 0}),
          200,
        ),
      ),
      idTokenProvider: () async => null,
    );
    addTearDown(service.dispose);

    final result = await _classify(service);

    expect(result['prediction'], 'Apple___healthy');
    expect(result['confidence'], 0);
  });
}

Future<Map<String, dynamic>> _classify(PlantApiService service) =>
    service.classify(
      imageBytes: Uint8List.fromList([1, 2, 3]),
      imageName: 'leaf.jpg',
      plantId: 'P001',
      location: 'Sidoarjo',
      hueMin: 25,
      hueMax: 95,
      saturationMin: 35,
      valueMin: 30,
      kernelSize: 5,
    );
