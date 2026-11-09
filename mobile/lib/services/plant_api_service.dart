import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class PlantApiService {
  final String baseUrl;

  PlantApiService({String? baseUrl})
      : baseUrl =
            (baseUrl ?? _configuredBaseUrl()).replaceFirst(RegExp(r'/$'), '');

  static String _configuredBaseUrl() {
    const configured = String.fromEnvironment('PLANT_API_URL');
    if (configured.isNotEmpty) return configured;
    if (kIsWeb || defaultTargetPlatform == TargetPlatform.macOS) {
      return 'http://127.0.0.1:8000';
    }
    return 'http://10.0.2.2:8000';
  }

  Future<Map<String, dynamic>> analyze({
    required Uint8List imageBytes,
    required String imageName,
    required String plantId,
    required String location,
    required bool flipHorizontal,
    required int hueMin,
    required int hueMax,
    required int saturationMin,
    required int valueMin,
    required int kernelSize,
  }) async {
    final idToken = await FirebaseAuth.instance.currentUser?.getIdToken();
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$baseUrl/api/v1/analyze-plant'),
    )
      ..fields.addAll({
        'plant_id': plantId,
        'location': location,
        'flip_horizontal': '$flipHorizontal',
        'hue_min': '$hueMin',
        'hue_max': '$hueMax',
        'saturation_min': '$saturationMin',
        'value_min': '$valueMin',
        'kernel_size': '$kernelSize',
      })
      ..files.add(http.MultipartFile.fromBytes(
        'image',
        imageBytes,
        filename: imageName,
      ));
    if (idToken != null && idToken.isNotEmpty) {
      request.headers['Authorization'] = 'Bearer $idToken';
    }

    final streamedResponse = await request.send().timeout(
          const Duration(seconds: 90),
        );
    final response = await http.Response.fromStream(streamedResponse);
    final body = jsonDecode(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail =
          body is Map<String, dynamic> ? body['detail']?.toString() : null;
      throw Exception(
          detail ?? 'Plant analysis failed (${response.statusCode}).');
    }
    if (body is! Map<String, dynamic>) {
      throw const FormatException(
          'The plant API returned an invalid response.');
    }
    return body;
  }
}
