import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

class WeatherCoordinates {
  const WeatherCoordinates({required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;
}

class CurrentWeather {
  const CurrentWeather({
    this.temperatureC,
    this.humidityPct,
    this.precipitationMm,
    this.rainMm,
    this.locationName = 'Lokasi perangkat',
    this.usedFallback = false,
    this.source = 'Open-Meteo',
    this.error,
  });

  final double? temperatureC;
  final double? humidityPct;
  final double? precipitationMm;
  final double? rainMm;
  final String locationName;
  final bool usedFallback;
  final String source;
  final String? error;

  bool get isAvailable =>
      temperatureC != null && humidityPct != null && precipitationMm != null;

  factory CurrentWeather.unavailable(
    String error, {
    String locationName = WeatherService.defaultLocationName,
    bool usedFallback = true,
  }) => CurrentWeather(
    error: error,
    locationName: locationName,
    usedFallback: usedFallback,
  );
}

class WeatherService {
  static const defaultLatitude = -7.4478;
  static const defaultLongitude = 112.7183;
  static const defaultLocationName = 'Sidoarjo';

  WeatherService({
    http.Client? client,
    Future<WeatherCoordinates?> Function()? locationResolver,
  }) : _client = client ?? http.Client(),
       _locationResolver = locationResolver ?? _resolveDeviceLocation;

  final http.Client _client;
  final Future<WeatherCoordinates?> Function() _locationResolver;

  Future<CurrentWeather> fetchCurrent({
    double? latitude,
    double? longitude,
    String? locationName,
  }) async {
    final suppliedCoordinates = _validCoordinates(latitude, longitude)
        ? WeatherCoordinates(latitude: latitude!, longitude: longitude!)
        : null;
    WeatherCoordinates? deviceCoordinates;
    if (suppliedCoordinates == null) {
      try {
        deviceCoordinates = await _locationResolver();
      } catch (_) {
        deviceCoordinates = null;
      }
    }

    final usedFallback =
        suppliedCoordinates == null && deviceCoordinates == null;
    final coordinates =
        suppliedCoordinates ??
        deviceCoordinates ??
        const WeatherCoordinates(
          latitude: defaultLatitude,
          longitude: defaultLongitude,
        );
    final resolvedLocationName =
        locationName ??
        (usedFallback ? defaultLocationName : 'Lokasi perangkat');

    try {
      final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
        'latitude': '${coordinates.latitude}',
        'longitude': '${coordinates.longitude}',
        'current': 'temperature_2m,relative_humidity_2m,precipitation,rain',
        'timezone': 'auto',
      });
      final response = await _client
          .get(uri)
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) {
        throw http.ClientException(
          'Open-Meteo mengembalikan HTTP ${response.statusCode}.',
          uri,
        );
      }

      final payload = jsonDecode(response.body);
      final current = payload is Map<String, dynamic>
          ? payload['current']
          : null;
      if (current is! Map<String, dynamic>) {
        throw const FormatException('Data cuaca saat ini tidak tersedia.');
      }

      double requiredNumber(String key) {
        final value = current[key];
        if (value is! num || !value.toDouble().isFinite) {
          throw FormatException('Nilai cuaca $key tidak valid.');
        }
        return value.toDouble();
      }

      final temperature = requiredNumber('temperature_2m');
      final humidity = requiredNumber('relative_humidity_2m');
      final precipitation = requiredNumber('precipitation');
      final rainValue = current['rain'];
      final rain = rainValue is num && rainValue.toDouble().isFinite
          ? rainValue.toDouble()
          : 0.0;
      if (humidity < 0 || humidity > 100 || precipitation < 0 || rain < 0) {
        throw const FormatException('Nilai cuaca berada di luar rentang.');
      }

      return CurrentWeather(
        temperatureC: temperature,
        humidityPct: humidity,
        precipitationMm: precipitation,
        rainMm: rain,
        locationName: resolvedLocationName,
        usedFallback: usedFallback,
      );
    } catch (error) {
      return CurrentWeather.unavailable(
        error.toString(),
        locationName: resolvedLocationName,
        usedFallback: usedFallback,
      );
    }
  }

  static bool _validCoordinates(double? latitude, double? longitude) =>
      latitude != null &&
      longitude != null &&
      latitude.isFinite &&
      longitude.isFinite &&
      latitude >= -90 &&
      latitude <= 90 &&
      longitude >= -180 &&
      longitude <= 180;

  static Future<WeatherCoordinates?> resolveDeviceCoordinates() async {
    try {
      return await _resolveDeviceLocation().timeout(
        const Duration(seconds: 12),
      );
    } on TimeoutException {
      return null;
    } on PermissionDeniedException {
      return null;
    } on LocationServiceDisabledException {
      return null;
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  static Future<WeatherCoordinates?> _resolveDeviceLocation() async {
    if (!await Geolocator.isLocationServiceEnabled().timeout(
      const Duration(seconds: 3),
    )) {
      return null;
    }

    var permission = await Geolocator.checkPermission().timeout(
      const Duration(seconds: 3),
    );
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.unableToDetermine) {
      permission = await Geolocator.requestPermission().timeout(
        const Duration(seconds: 15),
      );
    }
    if (permission == LocationPermission.deniedForever ||
        (permission == LocationPermission.denied && !kIsWeb) ||
        (permission == LocationPermission.unableToDetermine && !kIsWeb)) {
      return null;
    }

    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.low,
        timeLimit: Duration(seconds: 10),
      ),
    ).timeout(const Duration(seconds: 12));
    if (!_validCoordinates(position.latitude, position.longitude)) return null;
    return WeatherCoordinates(
      latitude: position.latitude,
      longitude: position.longitude,
    );
  }

  void dispose() => _client.close();
}

String wateringRecommendation(
  CurrentWeather weather, {
  Map<String, dynamic>? latestDiagnosis,
}) {
  late final String recommendation;
  if (!weather.isAvailable) {
    recommendation = 'Lakukan penyiraman rutin secukupnya. Data cuaca real-time tidak tersedia.';
  } else {
    final temperature = weather.temperatureC!;
    final humidity = weather.humidityPct!;
    final precipitation = weather.precipitationMm!;
    final rain = weather.rainMm ?? 0;

    // Hujan atau kelembapan tinggi didahulukan untuk mengurangi risiko jamur.
    if (rain > 0 || precipitation > 0.5 || humidity > 80) {
      recommendation = 'Tunda penyiraman hari ini. Kelembapan tinggi/hujan dapat memicu pertumbuhan jamur pada daun.';
    } else if (temperature > 30 && humidity < 50 && precipitation == 0) {
      recommendation = 'Suhu cukup tinggi dan udara kering. Lakukan penyiraman ekstra di pagi atau sore hari.';
    } else {
      recommendation = 'Lakukan penyiraman rutin secukupnya.';
    }
  }

  if (latestDiagnosis == null) {
    return '$recommendation Belum ada diagnosis daun terbaru; gunakan ini sebagai panduan cuaca.';
  }

  final prediction =
      latestDiagnosis['prediction']?.toString() ?? 'AI tidak tersedia';
  final severity = latestDiagnosis['severity']?.toString() ?? 'Tidak diketahui';
  final needsCare = severity != 'Sehat' && severity != 'Tidak diketahui';
  final diagnosisNote = needsCare
      ? 'Diagnosis terakhir: $prediction ($severity). Arahkan air ke media tanam dan hindari membasahi daun.'
      : 'Diagnosis terakhir: $prediction ($severity); sesuaikan jumlah air dengan kelembapan media.';
  return '$recommendation $diagnosisNote';
}
