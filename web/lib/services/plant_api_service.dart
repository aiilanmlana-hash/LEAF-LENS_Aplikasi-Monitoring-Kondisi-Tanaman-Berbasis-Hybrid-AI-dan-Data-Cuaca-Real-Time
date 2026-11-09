import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

class PlantApiService {
  PlantApiService({
    http.Client? client,
    String? baseUrl,
    Future<String?> Function()? idTokenProvider,
  }) : _client = client ?? http.Client(),
       _idTokenProvider = idTokenProvider ?? _firebaseIdToken,
       baseUrl = (baseUrl ?? _defaultBaseUrl).replaceFirst(RegExp(r'/$'), '');

  final http.Client _client;
  final Future<String?> Function() _idTokenProvider;
  final String baseUrl;

  static Future<String?> _firebaseIdToken() async =>
      FirebaseAuth.instance.currentUser?.getIdToken();

  static String get _defaultBaseUrl {
    const configured = String.fromEnvironment('PLANT_API_URL');
    return configured.isNotEmpty ? configured : 'http://localhost:8000';
  }

  Future<Map<String, dynamic>> classify({
    required Uint8List imageBytes,
    required String imageName,
    required String plantId,
    required String location,
    required int hueMin,
    required int hueMax,
    required int saturationMin,
    required int valueMin,
    required int kernelSize,
    bool flipHorizontal = false,
    double? latitude,
    double? longitude,
  }) async {
    final idToken = await _idTokenProvider();
    final request =
        http.MultipartRequest(
            'POST',
            Uri.parse('$baseUrl/api/v1/analyze-plant'),
          )
          ..fields.addAll({
            'plant_id': plantId,
            'location': location,
            'flip_horizontal': flipHorizontal.toString(),
            'hue_min': '$hueMin',
            'hue_max': '$hueMax',
            'saturation_min': '$saturationMin',
            'value_min': '$valueMin',
            'kernel_size': '$kernelSize',
          })
          ..files.add(
            http.MultipartFile.fromBytes(
              'image',
              imageBytes,
              filename: imageName,
            ),
          );
    if (latitude != null && longitude != null) {
      request.fields['latitude'] = '$latitude';
      request.fields['longitude'] = '$longitude';
    }
    if (idToken != null && idToken.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $idToken';
    }

    late final http.Response response;
    try {
      final streamedResponse = await _client
          .send(request)
          .timeout(const Duration(seconds: 90));
      response = await http.Response.fromStream(streamedResponse)
          .timeout(const Duration(seconds: 90));
    } on TimeoutException {
      throw const PlantApiException(
        statusCode: 0,
        code: 'api_timeout',
        message: 'Analisis membutuhkan waktu terlalu lama. Periksa koneksi lalu coba lagi.',
      );
    } on http.ClientException {
      throw const PlantApiException(
        statusCode: 0,
        code: 'api_unavailable',
        message: 'Layanan analisis tidak dapat dijangkau. Pastikan server aktif lalu coba lagi.',
      );
    }
    final dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException {
      throw const PlantApiException(
        statusCode: 502,
        code: 'invalid_api_response',
        message: 'Layanan analisis mengirim respons yang tidak dapat diproses. Silakan coba lagi.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detailPayload = decoded is Map<String, dynamic>
          ? decoded['detail']
          : null;
      final detailMap = detailPayload is Map<String, dynamic>
          ? detailPayload
          : null;
      final code = detailMap?['code']?.toString();
      final message = switch (code) {
        'ood_image' =>
          detailMap?['message']?.toString() ??
              'Gambar tidak terverifikasi sebagai daun tanaman yang didukung.',
        _ when response.statusCode == 401 || response.statusCode == 403 =>
          'Sesi masuk tidak valid atau telah berakhir. Silakan masuk kembali.',
        _ when response.statusCode >= 500 =>
          'Layanan analisis sedang bermasalah. Silakan coba lagi nanti.',
        _ => 'Foto atau informasi analisis tidak dapat diproses. Periksa kembali lalu coba lagi.',
      };
      throw PlantApiException(
        statusCode: response.statusCode,
        code: code,
        message: message,
      );
    }
    if (decoded is! Map<String, dynamic>) {
      throw const PlantApiException(
        statusCode: 502,
        code: 'invalid_api_response',
        message: 'Layanan analisis mengirim respons yang tidak dapat diproses. Silakan coba lagi.',
      );
    }
    return decoded;
  }

  void dispose() => _client.close();
}

class PlantApiException implements Exception {
  const PlantApiException({
    required this.statusCode,
    required this.message,
    this.code,
  });

  final int statusCode;
  final String message;
  final String? code;

  @override
  String toString() => message;
}
