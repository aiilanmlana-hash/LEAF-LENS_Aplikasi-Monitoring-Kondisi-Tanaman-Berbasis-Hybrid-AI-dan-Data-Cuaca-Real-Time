import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smart_plant_web/screens/dashboard_screen.dart';
import 'package:smart_plant_web/services/monitoring_repository.dart';
import 'package:smart_plant_web/services/weather_service.dart';
import 'package:smart_plant_web/theme/app_theme.dart';

void main() {
  test('fetches current weather without requiring an API key', () async {
    final client = MockClient((request) async {
      expect(request.url.host, 'api.open-meteo.com');
      expect(request.url.queryParameters['current'], contains('rain'));
      return http.Response(
        jsonEncode({
          'current': {
            'temperature_2m': 32.5,
            'relative_humidity_2m': 45,
            'precipitation': 0,
            'rain': 0,
          },
        }),
        200,
      );
    });
    final service = WeatherService(
      client: client,
      locationResolver: () async => null,
    );
    addTearDown(service.dispose);

    final weather = await service.fetchCurrent();

    expect(weather.isAvailable, isTrue);
    expect(weather.temperatureC, 32.5);
    expect(weather.locationName, 'Sidoarjo');
    expect(weather.usedFallback, isTrue);
  });

  test(
    'uses the device coordinates when location permission is granted',
    () async {
      final client = MockClient((request) async {
        expect(request.url.queryParameters['latitude'], '-7.25');
        expect(request.url.queryParameters['longitude'], '112.75');
        return http.Response(
          jsonEncode({
            'current': {
              'temperature_2m': 29,
              'relative_humidity_2m': 70,
              'precipitation': 0,
              'rain': 0,
            },
          }),
          200,
        );
      });
      var resolverCalled = false;
      final service = WeatherService(
        client: client,
        locationResolver: () async {
          resolverCalled = true;
          return const WeatherCoordinates(latitude: -7.25, longitude: 112.75);
        },
      );
      addTearDown(service.dispose);

      final weather = await service.fetchCurrent();

      expect(resolverCalled, isTrue);
      expect(weather.locationName, 'Lokasi perangkat');
      expect(weather.usedFallback, isFalse);
    },
  );

  test('falls back to Sidoarjo when location resolution throws', () async {
    final client = MockClient((request) async {
      expect(request.url.queryParameters['latitude'], '-7.45');
      expect(request.url.queryParameters['longitude'], '112.72');
      return http.Response(
        jsonEncode({
          'current': {
            'temperature_2m': 29,
            'relative_humidity_2m': 70,
            'precipitation': 0,
            'rain': 0,
          },
        }),
        200,
      );
    });
    final service = WeatherService(
      client: client,
      locationResolver: () async => throw StateError('permission denied'),
    );
    addTearDown(service.dispose);

    final weather = await service.fetchCurrent();

    expect(weather.locationName, 'Sidoarjo');
    expect(weather.usedFallback, isTrue);
  });

  test('uses rainy or humid recommendation before hot-dry rule', () {
    const weather = CurrentWeather(
      temperatureC: 32,
      humidityPct: 81,
      precipitationMm: 0,
      rainMm: 0,
    );

    expect(
      wateringRecommendation(weather),
      startsWith('Tunda penyiraman hari ini.'),
    );
  });

  test(
    'postpones watering when rain or precipitation exceeds the threshold',
    () {
      const rainyWeather = CurrentWeather(
        temperatureC: 28,
        humidityPct: 60,
        precipitationMm: 0,
        rainMm: 0.1,
      );
      const precipitatingWeather = CurrentWeather(
        temperatureC: 28,
        humidityPct: 60,
        precipitationMm: 0.6,
        rainMm: 0,
      );

      expect(
        wateringRecommendation(rainyWeather),
        startsWith('Tunda penyiraman hari ini.'),
      );
      expect(
        wateringRecommendation(precipitatingWeather),
        startsWith('Tunda penyiraman hari ini.'),
      );
    },
  );

  test('recommends extra watering for hot, dry, rain-free weather', () {
    const weather = CurrentWeather(
      temperatureC: 31,
      humidityPct: 49,
      precipitationMm: 0,
      rainMm: 0,
    );

    expect(
      wateringRecommendation(weather),
      startsWith('Suhu cukup tinggi dan udara kering.'),
    );
  });

  test(
    'uses routine watering in normal weather and includes diagnosis context',
    () {
      const weather = CurrentWeather(
        temperatureC: 27,
        humidityPct: 65,
        precipitationMm: 0,
        rainMm: 0,
      );

      final recommendation = wateringRecommendation(
        weather,
        latestDiagnosis: {
          'prediction': 'Tomato___Late_blight',
          'severity': 'Kritis',
        },
      );

      expect(
        recommendation,
        startsWith('Lakukan penyiraman rutin secukupnya.'),
      );
      expect(recommendation, contains('Tomato___Late_blight (Kritis)'));
      expect(recommendation, contains('hindari membasahi daun'));
    },
  );

  test('falls back safely when weather is unavailable', () {
    final recommendation = wateringRecommendation(
      CurrentWeather.unavailable('offline'),
    );

    expect(recommendation, contains('Lakukan penyiraman rutin secukupnya.'));
    expect(recommendation, contains('Data cuaca real-time tidak tersedia.'));
  });

  for (final size in [
    const Size(320, 568),
    const Size(390, 844),
    const Size(768, 1024),
    const Size(1024, 768),
    const Size(1440, 900),
  ]) {
    testWidgets('dashboard weather card fits ${size.width}px', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);

      final service = WeatherService(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'current': {
                'temperature_2m': 27,
                'relative_humidity_2m': 65,
                'precipitation': 0,
                'rain': 0,
              },
            }),
            200,
          ),
        ),
        locationResolver: () async =>
            const WeatherCoordinates(latitude: -7.25, longitude: 112.75),
      );
      addTearDown(service.dispose);

      await tester.pumpWidget(
        MaterialApp(
          theme: PlantTheme.light,
          home: DashboardScreen(
            repository: _EmptyDashboardRepository(),
            onScan: () {},
            weatherService: service,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Rekomendasi perawatan hari ini'),
        250,
        scrollable: find.byType(Scrollable).first,
      );

      expect(find.text('Rekomendasi perawatan hari ini'), findsOneWidget);
      expect(find.textContaining('Kelembapan:'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }
}

class _EmptyDashboardRepository implements MonitoringRepository {
  @override
  Stream<List<Map<String, dynamic>>> watchRecords() => Stream.value([]);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
