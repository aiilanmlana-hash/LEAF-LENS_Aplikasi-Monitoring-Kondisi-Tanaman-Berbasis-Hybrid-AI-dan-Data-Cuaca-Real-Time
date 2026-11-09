import 'dart:async';
import 'dart:convert';

import 'package:camera/camera.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:image_picker/image_picker.dart';

import '../models/plant_analysis.dart';
import '../services/image_processing_service.dart';
import '../services/monitoring_repository.dart';
import '../services/plant_api_service.dart';
import '../services/weather_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_surface.dart';
import '../widgets/garden_artwork.dart';
import '../widgets/soft_motion.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({required this.repository, required this.api, super.key});

  final MonitoringRepository repository;
  final PlantApiService api;

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final _picker = ImagePicker();
  final _tts = FlutterTts();
  final _processor = const ImageProcessingService();
  final _plantId = TextEditingController(text: 'P001');
  final _location = TextEditingController(text: 'Polije Sidoarjo');
  final _latitude = TextEditingController();
  final _longitude = TextEditingController();
  CameraController? _cameraController;
  List<CameraDescription> _cameras = [];
  CameraDescription? _selectedCamera;
  Uint8List? _imageBytes;
  String _imageName = 'leaf.jpg';
  bool _isCameraImage = false;
  bool _flipHorizontal = true;
  bool _isBusy = false;
  bool _isCameraLoading = false;
  String? _cameraError;
  String? _analysisError;
  String? _coordinateNotice;
  int _hueMin = 25;
  int _hueMax = 95;
  int _saturationMin = 35;
  int _valueMin = 30;
  int _kernelSize = 5;
  PlantAnalysis? _analysis;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      unawaited(_loadCameras());
    } else {
      _cameraError = 'Gunakan Flutter Web di browser untuk kamera langsung.';
    }
  }

  @override
  void dispose() {
    _plantId.dispose();
    _location.dispose();
    _latitude.dispose();
    _longitude.dispose();
    unawaited(_tts.stop());
    final controller = _cameraController;
    if (controller != null) unawaited(controller.dispose());
    super.dispose();
  }

  Future<void> _loadCameras() async {
    if (!kIsWeb) {
      setState(() {
        _cameras = [];
        _cameraError = 'Kamera langsung tersedia pada browser Web.';
      });
      return;
    }
    if (_isCameraLoading) return;
    setState(() {
      _isCameraLoading = true;
      _cameraError = null;
    });
    try {
      final cameras = await availableCameras();
      if (!mounted) return;
      if (cameras.isEmpty) {
        setState(() {
          _cameras = [];
          _cameraError = 'Browser tidak menemukan kamera. Silakan unggah foto.';
        });
        return;
      }
      final current = cameras.where(
        (camera) => camera.name == _selectedCamera?.name,
      );
      final selected = current.isNotEmpty
          ? current.first
          : cameras.firstWhere(
              (camera) => camera.lensDirection == CameraLensDirection.back,
              orElse: () => cameras.first,
            );
      setState(() {
        _cameras = cameras;
        _selectedCamera = selected;
      });
      await _startCamera(selected);
    } on CameraException catch (error) {
      if (mounted) setState(() => _cameraError = _cameraMessage(error));
    } catch (error) {
      if (mounted) setState(() => _cameraError = 'Kamera gagal dimuat: $error');
    } finally {
      if (mounted) setState(() => _isCameraLoading = false);
    }
  }

  Future<void> _startCamera(CameraDescription camera) async {
    final previous = _cameraController;
    _cameraController = null;
    if (previous != null) await previous.dispose();
    if (!mounted) return;

    final controller = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
    );
    try {
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _cameraController = controller;
        _cameraError = null;
      });
    } on CameraException catch (error) {
      await controller.dispose();
      if (mounted) setState(() => _cameraError = _cameraMessage(error));
    }
  }

  String _cameraMessage(CameraException error) {
    if (error.code == 'CameraAccessDenied' ||
        error.code == 'CameraAccessDeniedWithoutPrompt') {
      return 'Izin kamera ditolak. Izinkan kamera di browser atau unggah foto.';
    }
    return error.description ?? error.code;
  }

  Future<void> _selectCamera(String? name) async {
    if (name == null) return;
    final matches = _cameras.where((camera) => camera.name == name);
    if (matches.isEmpty) return;
    setState(() {
      _selectedCamera = matches.first;
      _flipHorizontal =
          matches.first.lensDirection == CameraLensDirection.front;
    });
    await _startCamera(matches.first);
  }

  Future<void> _uploadImage() async {
    try {
      final picked = await _picker.pickImage(
        source: ImageSource.gallery,
        // Keep upload, browser decoding, and the preview bounded. The backend
        // classifier resizes to 256×256, so a 1600px source retains more than
        // enough detail while avoiding multi-megapixel UI stalls.
        imageQuality: 85,
        maxWidth: 1600,
        maxHeight: 1600,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      setState(() {
        _imageBytes = bytes;
        _imageName = picked.name;
        _isCameraImage = false;
        _flipHorizontal = false;
        _analysis = null;
        _analysisError = null;
      });
    } catch (error) {
      if (mounted) setState(() => _analysisError = 'Upload foto gagal: $error');
    }
  }

  Future<void> _captureImage() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      setState(() {
        _cameraError ??= 'Kamera belum siap. Coba refresh atau unggah foto.';
      });
      return;
    }
    try {
      final photo = await controller.takePicture();
      final bytes = await photo.readAsBytes();
      if (!mounted) return;
      setState(() {
        _imageBytes = bytes;
        _imageName = photo.name;
        _isCameraImage = true;
        _flipHorizontal =
            _selectedCamera?.lensDirection == CameraLensDirection.front;
        _analysis = null;
        _analysisError = null;
      });
    } on CameraException catch (error) {
      if (mounted) setState(() => _cameraError = _cameraMessage(error));
    } catch (error) {
      if (mounted) {
        setState(() => _cameraError = 'Pengambilan foto gagal: $error');
      }
    }
  }

  Future<void> _analyze() async {
    final sourceBytes = _imageBytes;
    if (sourceBytes == null || _isBusy) return;
    final plantId = _plantId.text.trim();
    if (plantId.isEmpty || plantId.length > 40) {
      setState(
        () => _analysisError = 'Plant ID wajib diisi (maksimal 40 karakter).',
      );
      return;
    }
    final latitudeText = _latitude.text.trim();
    final longitudeText = _longitude.text.trim();
    final latitude = latitudeText.isEmpty
        ? null
        : double.tryParse(latitudeText);
    final longitude = longitudeText.isEmpty
        ? null
        : double.tryParse(longitudeText);
    if ((latitudeText.isEmpty) != (longitudeText.isEmpty) ||
        (latitudeText.isNotEmpty &&
            (latitude == null ||
                longitude == null ||
                !latitude.isFinite ||
                !longitude.isFinite ||
                latitude < -90 ||
                latitude > 90 ||
                longitude < -180 ||
                longitude > 180))) {
      setState(
        () => _analysisError = 'Isi latitude (-90 sampai 90) dan longitude (-180 sampai 180) secara berpasangan.',
      );
      return;
    }

    setState(() {
      _isBusy = true;
      _analysisError = null;
    });

    try {
      // Give Flutter one frame to paint the progress state before any image or
      // network work starts. This avoids a button that appears frozen.
      await Future<void>.delayed(Duration.zero);
      final flipHorizontal = _isCameraImage && _flipHorizontal;
      if (kIsWeb && mounted) {
        setState(
          () => _coordinateNotice =
              'Meminta izin lokasi browser untuk mengambil data cuaca...',
        );
      }
      final deviceCoordinates = kIsWeb
          ? await WeatherService.resolveDeviceCoordinates()
          : null;
      final resolvedLatitude =
          latitude ??
          deviceCoordinates?.latitude ??
          WeatherService.defaultLatitude;
      final resolvedLongitude =
          longitude ??
          deviceCoordinates?.longitude ??
          WeatherService.defaultLongitude;
      if (!mounted) return;
      setState(() {
        _coordinateNotice = latitude != null && longitude != null
            ? 'Menggunakan koordinat yang diisi pada formulir.'
            : deviceCoordinates != null
            ? 'Lokasi browser digunakan untuk mengambil cuaca.'
            : 'Lokasi browser tidak tersedia atau izin ditolak; memakai koordinat default Sidoarjo.';
      });

      // The Python API already performs HSV/K-Means segmentation. Running an
      // additional pixel-by-pixel pass in the browser before every request was
      // redundant and blocked scrolling on larger photos. Local segmentation
      // remains available only as an offline/API-failure fallback.
      Map<String, dynamic>? ai;
      String? aiError;
      try {
        ai = await widget.api.classify(
          imageBytes: sourceBytes,
          imageName: _imageName,
          plantId: plantId,
          location: _location.text.trim(),
          hueMin: _hueMin,
          hueMax: _hueMax,
          saturationMin: _saturationMin,
          valueMin: _valueMin,
          kernelSize: _kernelSize,
          flipHorizontal: flipHorizontal,
          latitude: resolvedLatitude,
          longitude: resolvedLongitude,
        );
      } on PlantApiException catch (error) {
        if (error.code == 'ood_image') {
          if (mounted) {
            setState(() {
              _analysis = null;
              _analysisError = error.message;
            });
          }
          return;
        }
        aiError = 'Layanan analisis sementara tidak tersedia.';
      } catch (_) {
        aiError = 'Layanan analisis sementara tidak tersedia.';
      }

      Uint8List? backendMask;
      final encodedBackendMask = ai?['mask_base64'];
      if (encodedBackendMask is String && encodedBackendMask.isNotEmpty) {
        try {
          backendMask = base64Decode(encodedBackendMask);
        } on FormatException {
          aiError ??=
              'Mask dari server tidak valid; menggunakan segmentasi lokal.';
        }
      }
      SegmentationResult? localSegmentation;
      if (backendMask == null) {
        final localImageBytes = flipHorizontal
            ? _processor.correctHorizontalMirror(sourceBytes)
            : sourceBytes;
        localSegmentation = _processor.segment(
          localImageBytes,
          hueMin: _hueMin,
          hueMax: _hueMax,
          saturationMin: _saturationMin,
          valueMin: _valueMin,
          kernelSize: _kernelSize,
        );
      }
      final maskBytes = backendMask ?? localSegmentation!.maskBytes;
      final greenRatio =
          (ai?['green_ratio'] as num?)?.toDouble() ??
          localSegmentation?.greenRatio ??
          0;
      final dryRatio =
          (ai?['yellow_ratio'] as num?)?.toDouble() ??
          localSegmentation?.dryRatio ??
          0;
      final className = ai?['class_name']?.toString() ?? '';
      final prediction = ai?['prediction']?.toString() ?? className;
      final plantName = ai?['plant_name']?.toString();
      final diseaseName = ai?['disease_name']?.toString();
      final confidence = (ai?['confidence'] as num?)?.toDouble();
      final ann = ai?['ann_prediction'];
      final annResult = ann is List && ann.isNotEmpty
          ? ann.first
          : ann is Map
          ? ann
          : null;
      final annPrediction = annResult is Map
          ? annResult['label']?.toString()
          : null;
      final annConfidence = annResult is Map
          ? (annResult['confidence'] as num?)?.toDouble()
          : null;
      final status = ai == null
          ? ('HASIL AI TIDAK TERSEDIA', 'Perlu verifikasi')
          : diagnosisStatusForPrediction(className);
      final care = ai?['care_recommendation'];
      final careMap = care is Map ? care : const <String, dynamic>{};
      final careActions =
          ((careMap['emergency_actions'] ?? careMap['actions']) as List?)
              ?.map((action) => action.toString())
              .where((action) => action.isNotEmpty)
              .toList() ??
          const [
            'Periksa kondisi daun dan tanah sebelum memberi perlakuan.',
            'Ambil ulang foto bila hasil AI tidak tersedia.',
          ];
      List<String> recommendationList(String key) =>
          (careMap[key] as List?)
              ?.map((item) => item.toString())
              .where((item) => item.isNotEmpty)
              .toList() ??
          const [];
      final weatherValue = ai?['weather'];
      final weather = weatherValue is Map
          ? weatherValue
          : const <String, dynamic>{};
      final riskValue = ai?['risk_analysis'];
      final risk = riskValue is Map ? riskValue : const <String, dynamic>{};
      final analysis = PlantAnalysis(
        imageBytes: sourceBytes,
        imageIsMirrored: flipHorizontal,
        maskBytes: maskBytes,
        greenRatio: greenRatio,
        dryRatio: dryRatio,
        prediction: prediction,
        className: className,
        plantName: plantName,
        diseaseName: diseaseName,
        aiConfidence: confidence,
        annPrediction: annPrediction,
        annConfidence: annConfidence,
        annError: ai?['ann_error']?.toString(),
        healthScore: (ai?['health_score'] as num?)?.toDouble(),
        severity: status.$2,
        statusLabel: status.$1,
        carePriority: careMap['priority']?.toString() ?? 'Perlu verifikasi',
        priorityLevel: risk['priority_level']?.toString(),
        careSummary:
            careMap['summary']?.toString() ??
            'Hasil lokal belum cukup untuk memberikan rekomendasi spesifik.',
        careActions: careActions,
        careDisclaimer: careMap['disclaimer']?.toString() ?? 'Hasil dari foto adalah skrining awal, bukan diagnosis atau resep pupuk.',
        organicRecommendations: recommendationList('organic_recommendations'),
        chemicalRecommendations: recommendationList('chemical_recommendations'),
        untreatedImpact:
            careMap['untreated_impact']?.toString() ??
            'Dampak belum dapat dinilai dari hasil lokal.',
        temperatureC: (weather['temperature_c'] as num?)?.toDouble(),
        humidityPct: (weather['humidity_pct'] as num?)?.toDouble(),
        precipitationMm: (weather['precipitation_mm'] as num?)?.toDouble(),
        weatherSource: weather['source']?.toString(),
        weatherStation: weather['station_name']?.toString(),
        weatherError: ai?['weather_error']?.toString(),
        healthSeverity:
            risk['severity']?.toString() ?? ai?['severity']?.toString(),
        leafRiskScore: (risk['leaf_risk_score'] as num?)?.toDouble(),
        leafRiskLevel: risk['leaf_risk_level']?.toString(),
        weatherRiskScore: (risk['weather_risk_score'] as num?)?.toDouble(),
        weatherRiskLevel: risk['weather_risk_level']?.toString(),
        weatherSummary: risk['weather_summary']?.toString(),
        weatherRiskMethod: risk['weather_risk_method']?.toString(),
        boundingBox: localSegmentation?.boundingBox,
        imageWidth: localSegmentation?.imageWidth ?? 1,
        imageHeight: localSegmentation?.imageHeight ?? 1,
        createdAt: DateTime.now(),
        plantId: plantId,
        location: _location.text.trim(),
      );

      if (!mounted) return;
      setState(() => _analysis = analysis);
      // Show the result immediately. Persisting history may take longer on a
      // slow connection and must not make the analysis screen feel frozen.
      try {
        final thumbnail = _processor.createFirestoreThumbnail(maskBytes);
        await widget.repository.saveAnalysis(
          analysis: analysis,
          maskThumbnail: thumbnail,
        );
      } on FirebaseException catch (error) {
        if (mounted) {
          setState(
            () => _analysisError =
                'Hasil analisis tersedia, tetapi gagal disimpan ke Firestore: ${error.message ?? error.code}',
          );
        }
      }
      if (aiError != null) {
        setState(
          () => _analysisError =
              '$aiError Segmentasi lokal ditampilkan; prediksi AI belum tersedia.',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _analysisError =
              'Analisis gagal diproses. Periksa foto lalu coba kembali.',
        );
      }
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _speakAnalysis() async {
    final analysis = _analysis;
    if (analysis == null) return;
    try {
      await _tts.setLanguage('id-ID');
      await _tts.setSpeechRate(0.46);
      await _tts.setPitch(1.02);
      await _tts.setVolume(1.0);
      await _tts.speak(
        'Hasil pemeriksaan tanaman ${analysis.plantId}. '
        '${analysis.statusLabel}. '
        'Area hijau ${analysis.greenRatio.toStringAsFixed(1)} persen. '
        'Area kering ${analysis.dryRatio.toStringAsFixed(1)} persen. '
        'Prediksi kecerdasan buatan ${analysis.prediction}. '
        '${analysis.careSummary} '
        '${analysis.healthScore == null ? '' : 'Skor kesehatan ${analysis.healthScore!.toStringAsFixed(0)} persen.'}',
      );
    } on PlatformException catch (error) {
      if (mounted) {
        setState(
          () => _analysisError =
              'Suara tidak tersedia di browser ini: ${error.message ?? error.code}',
        );
      }
    } catch (error) {
      if (mounted) setState(() => _analysisError = 'TTS gagal: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1000;
        final controls = _controls(context);
        final preview = _previewAndResults(context);
        return ListView(
          padding: EdgeInsets.fromLTRB(wide ? 30 : 18, 22, wide ? 30 : 18, 32),
          children: [
            SoftEntrance(
              child: GlassSurface(
                padding: const EdgeInsets.fromLTRB(17, 12, 8, 12),
                radius: 22,
                opacity: 0.74,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final artWidth = constraints.maxWidth < 430 ? 70.0 : 104.0;
                    return Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Analisis tanaman',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall,
                              ),
                              const SizedBox(height: 5),
                              Text(
                                'Segmentasi HSV dual-color dan klasifikasi MobileNetV2.',
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(color: PlantPalette.sage),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(
                          width: artWidth,
                          height: 82,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Positioned(
                                right: 0,
                                top: -4,
                                width: artWidth * 0.82,
                                height: 90,
                                child: const GardenArtwork(
                                  asset: 'assets/moss-branch.webp',
                                  opacity: 0.58,
                                ),
                              ),
                              Positioned(
                                right: 0,
                                bottom: -6,
                                width: artWidth * 0.44,
                                height: 72,
                                child: const GardenArtwork(
                                  asset: 'assets/swallow-bird.webp',
                                  opacity: 0.82,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 20),
            if (wide)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 350,
                    child: SoftEntrance(child: HoverLift(child: controls)),
                  ),
                  const SizedBox(width: 18),
                  Expanded(child: SoftEntrance(child: preview)),
                ],
              )
            else ...[
              SoftEntrance(child: HoverLift(child: controls)),
              const SizedBox(height: 16),
              SoftEntrance(
                delay: const Duration(milliseconds: 100),
                child: preview,
              ),
            ],
          ],
        );
      },
    );
  }

  Widget _controls(BuildContext context) {
    final controller = _cameraController;
    return GlassSurface(
      padding: const EdgeInsets.all(18),
      radius: 22,
      opacity: 0.72,
      blur: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.camera_alt_outlined, color: PlantPalette.forest),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Input gambar',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: 'Refresh camera',
                onPressed: _isCameraLoading ? null : _loadCameras,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            height: 190,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: PlantPalette.forest.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
            ),
            child: controller != null && controller.value.isInitialized
                ? RepaintBoundary(child: CameraPreview(controller))
                : Center(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.videocam_off_outlined,
                            size: 30,
                            color: PlantPalette.sage,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _isCameraLoading
                                ? 'Menghubungkan kamera...'
                                : _cameraError ?? 'Kamera belum tersedia',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
          ),
          if (_cameras.length > 1) ...[
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _selectedCamera?.name,
              decoration: const InputDecoration(labelText: 'Perangkat kamera'),
              items: [
                for (final camera in _cameras)
                  DropdownMenuItem(
                    value: camera.name,
                    child: Text(camera.name, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: _selectCamera,
            ),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: controller?.value.isInitialized == true
                      ? _captureImage
                      : null,
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text('Ambil foto'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _uploadImage,
                  icon: const Icon(Icons.upload_file_outlined),
                  label: const Text('Upload foto'),
                ),
              ),
            ],
          ),
          if (_isCameraImage) ...[
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _flipHorizontal,
              title: const Text('Koreksi mirror horizontal'),
              controlAffinity: ListTileControlAffinity.leading,
              onChanged: (value) =>
                  setState(() => _flipHorizontal = value ?? false),
            ),
          ],
          const Divider(height: 24),
          TextField(
            controller: _plantId,
            maxLength: 40,
            decoration: const InputDecoration(
              labelText: 'Plant ID',
              counterText: '',
              prefixIcon: Icon(Icons.local_florist_outlined),
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _location,
            maxLength: 100,
            decoration: const InputDecoration(
              labelText: 'Lokasi',
              counterText: '',
              prefixIcon: Icon(Icons.place_outlined),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _latitude,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Latitude (opsional)',
                    hintText: '-7.45',
                    prefixIcon: Icon(Icons.public_outlined),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _longitude,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                    signed: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Longitude (opsional)',
                    hintText: '112.72',
                    prefixIcon: Icon(Icons.public_outlined),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            _coordinateNotice ?? 'Saat scan, browser mencoba mengambil lokasi. Jika izin ditolak atau waktu habis, koordinat default Sidoarjo digunakan untuk cuaca.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 18),
          Text(
            'Parameter segmentasi',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 8),
          _RangeParameter(
            label: 'Hue (H)',
            values: RangeValues(_hueMin.toDouble(), _hueMax.toDouble()),
            max: 179,
            onChanged: (values) => setState(() {
              _hueMin = values.start.round();
              _hueMax = values.end.round();
            }),
          ),
          _SingleParameter(
            label: 'Saturation minimum (S)',
            value: _saturationMin,
            max: 255,
            onChanged: (value) => setState(() => _saturationMin = value),
          ),
          _SingleParameter(
            label: 'Value minimum (V)',
            value: _valueMin,
            max: 255,
            onChanged: (value) => setState(() => _valueMin = value),
          ),
          DropdownButtonFormField<int>(
            initialValue: _kernelSize,
            decoration: const InputDecoration(labelText: 'Kernel morfologi'),
            items: const [3, 5, 7, 9]
                .map(
                  (size) => DropdownMenuItem(
                    value: size,
                    child: Text('$size × $size'),
                  ),
                )
                .toList(),
            onChanged: (value) {
              if (value != null) setState(() => _kernelSize = value);
            },
          ),
          const SizedBox(height: 16),
          PressScale(
            enabled: _imageBytes != null && !_isBusy,
            child: FilledButton.icon(
              onPressed: _imageBytes == null || _isBusy ? null : _analyze,
              icon: _isBusy
                  ? const SizedBox.square(
                      dimension: 17,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.document_scanner_outlined),
              label: Text(_isBusy ? 'Memproses...' : 'Analisis daun'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _previewAndResults(BuildContext context) {
    final analysis = _analysis;
    if (analysis == null) {
      return Column(
        children: [
          if (_analysisError != null)
            _Notice(message: _analysisError!, isError: true),
          GlassSurface(
            radius: 24,
            opacity: 0.72,
            child: SizedBox(
              height: 440,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_imageBytes == null)
                        Image.asset(
                          'assets/broad-tree.webp',
                          width: 118,
                          height: 142,
                          fit: BoxFit.contain,
                          excludeFromSemantics: true,
                        )
                      else
                        const Icon(
                          Icons.spa_outlined,
                          size: 44,
                          color: PlantPalette.sage,
                        ),
                      const SizedBox(height: 12),
                      Text(
                        _imageBytes == null
                            ? 'Ambil foto atau unggah gambar daun'
                            : 'Gambar siap dianalisis',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (_imageBytes != null) ...[
                        const SizedBox(height: 12),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 280),
                          child: _isCameraImage && _flipHorizontal
                              ? Transform.flip(
                                  flipX: true,
                                  child: Image.memory(
                                    _imageBytes!,
                                    fit: BoxFit.contain,
                                    cacheWidth: 640,
                                  ),
                                )
                              : Image.memory(
                                  _imageBytes!,
                                  fit: BoxFit.contain,
                                  cacheWidth: 640,
                                ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    final statusColor = _statusColor(analysis.severity);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_analysisError != null)
          _Notice(message: _analysisError!, isError: true),
        LayoutBuilder(
          builder: (context, constraints) {
            final maskPanel = _ImagePanel(
              title: 'MASK SEGMENTASI',
              subtitle: 'Putih: hijau  ·  Abu-abu: kering',
              child: Image.memory(
                analysis.maskBytes,
                fit: BoxFit.contain,
                cacheWidth: 640,
              ),
            );
            final sourcePanel = _ImagePanel(
              title: 'FOTO & DETEKSI',
              subtitle: 'Bounding area hasil segmentasi',
              child: _DetectionImage(analysis: analysis),
            );
            if (constraints.maxWidth < 680) {
              return Column(
                children: [maskPanel, const SizedBox(height: 10), sourcePanel],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: maskPanel),
                const SizedBox(width: 12),
                Expanded(child: sourcePanel),
              ],
            );
          },
        ),
        const SizedBox(height: 14),
        GlassSurface(
          padding: const EdgeInsets.all(18),
          radius: 22,
          opacity: 0.88,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      analysis.statusLabel,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: statusColor,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  _StatusChip(label: analysis.severity, color: statusColor),
                ],
              ),
              const SizedBox(height: 14),
              _careMetricsDashboard(analysis),
              const SizedBox(height: 14),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _MetricPill(
                    label: 'Hijau',
                    value: analysis.greenRatio,
                    color: PlantPalette.forest,
                  ),
                  _MetricPill(
                    label: 'Kering',
                    value: analysis.dryRatio,
                    color: PlantPalette.orange,
                  ),
                  _InfoPill(
                    label: 'PlantVillage',
                    value: analysis.aiConfidence == null
                        ? analysis.prediction
                        : '${analysis.prediction} · ${analysis.aiConfidence!.toStringAsFixed(1)}%',
                  ),
                  if (analysis.plantName != null ||
                      analysis.diseaseName != null)
                    _InfoPill(
                      label: 'Tanaman / penyakit',
                      value: [analysis.plantName, analysis.diseaseName]
                          .whereType<String>()
                          .where((part) => part.isNotEmpty)
                          .join(' · '),
                    ),
                  if (analysis.annPrediction != null)
                    _InfoPill(
                      label: 'ANN',
                      value: analysis.annConfidence == null
                          ? analysis.annPrediction!
                          : '${analysis.annPrediction} · ${analysis.annConfidence!.toStringAsFixed(1)}%',
                    ),
                  if (analysis.annPrediction == null &&
                      analysis.annError != null)
                    _InfoPill(
                      label: 'ANN belum tersedia',
                      value: analysis.annError!,
                    ),
                ],
              ),
              if (analysis.weatherSource != null) ...[
                const SizedBox(height: 4),
                Text(
                  'Sumber cuaca: ${analysis.weatherSource}'
                  '${analysis.weatherStation == null ? '' : ' · ${analysis.weatherStation}'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
              if (analysis.weatherError != null &&
                  analysis.temperatureC == null) ...[
                const SizedBox(height: 4),
                Text(
                  'Cuaca belum tersedia: ${analysis.weatherError}',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: PlantPalette.sage),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                'Rekomendasi Penanganan',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: PlantPalette.forest,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(analysis.careSummary),
              const SizedBox(height: 12),
              _careActionCards(analysis),
              const SizedBox(height: 12),
              _CareFooterAlert(
                title: 'Catatan penggunaan',
                message:
                    '${analysis.careDisclaimer} Dampak bila diabaikan: ${analysis.untreatedImpact}',
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _speakAnalysis,
                icon: const Icon(Icons.volume_up_outlined),
                label: const Text('Dengarkan Analisis'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _careMetricsDashboard(PlantAnalysis analysis) {
    final priority = analysis.priorityLevel ?? analysis.carePriority;
    final priorityColor = switch (priority) {
      'Tinggi' || 'Sangat tinggi' => PlantPalette.red,
      'Sedang' => PlantPalette.orange,
      'Rendah' || 'Rutin' || 'Pantau' => PlantPalette.forest,
      _ => PlantPalette.sage,
    };
    final weatherRiskScore = analysis.weatherRiskScore;
    final leafRiskScore =
        analysis.leafRiskScore ??
        (analysis.healthScore == null ? null : 100 - analysis.healthScore!);

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 960
            ? 3
            : constraints.maxWidth >= 620
            ? 2
            : 1;
        final cardWidth = (constraints.maxWidth - (columns - 1) * 10) / columns;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            SizedBox(
              width: cardWidth,
              child: _CareMetricCard(
                title: 'PRIORITAS TINDAKAN',
                icon: Icons.priority_high_rounded,
                color: priorityColor,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      priority,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: priorityColor,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Keparahan: ${analysis.healthSeverity ?? analysis.severity}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _CareMetricCard(
                title: 'RISIKO DAUN · FUZZY + CUACA',
                icon: Icons.cloud_outlined,
                color: _riskColor(analysis.leafRiskLevel),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Text(
                            analysis.leafRiskLevel ?? 'Belum tersedia',
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(
                                  color: _riskColor(analysis.leafRiskLevel),
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                        ),
                        Text(
                          leafRiskScore == null
                              ? '—'
                              : '${leafRiskScore.toStringAsFixed(0)}/100',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    if (leafRiskScore == null)
                      Container(
                        height: 6,
                        decoration: BoxDecoration(
                          color: PlantPalette.sage.withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      )
                    else
                      LinearProgressIndicator(
                        value: (leafRiskScore / 100).clamp(0.0, 1.0),
                        minHeight: 6,
                        borderRadius: BorderRadius.circular(8),
                        color: _riskColor(analysis.leafRiskLevel),
                        backgroundColor: PlantPalette.sage.withValues(
                          alpha: 0.16,
                        ),
                      ),
                    const SizedBox(height: 7),
                    Text(
                      'Fuzzy health ${analysis.healthScore?.toStringAsFixed(1) ?? '—'}% · risiko cuaca ${analysis.weatherRiskLevel ?? 'tidak tersedia'}${weatherRiskScore == null ? '' : ' (${weatherRiskScore.toStringAsFixed(0)}/100)'}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    if (analysis.weatherSummary != null)
                      Text(
                        analysis.weatherSummary!,
                        style: Theme.of(context).textTheme.bodySmall
                            ?.copyWith(color: PlantPalette.sage),
                      ),
                    if (analysis.weatherRiskMethod != null)
                      Text(
                        analysis.weatherRiskMethod!,
                        style: Theme.of(context).textTheme.labelSmall
                            ?.copyWith(color: PlantPalette.sage, height: 1.35),
                      ),
                  ],
                ),
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _CareMetricCard(
                title: 'SEGMENTASI DAUN · HSV',
                icon: Icons.donut_small_outlined,
                color: PlantPalette.forest,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SegmentProgress(
                      label: 'Hijau / sehat',
                      value: analysis.greenRatio,
                      color: PlantPalette.forest,
                    ),
                    const SizedBox(height: 8),
                    _SegmentProgress(
                      label: 'Kering / bercak',
                      value: analysis.dryRatio,
                      color: PlantPalette.orange,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      'Indikasi warna, bukan konfirmasi infeksi.',
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: PlantPalette.sage),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _careActionCards(PlantAnalysis analysis) {
    final cards = [
      _CareActionCard(
        title: 'Tindakan darurat',
        subtitle: 'Langkah awal yang dapat dilakukan sekarang',
        icon: Icons.health_and_safety_outlined,
        color: PlantPalette.red,
        actions: analysis.careActions,
      ),
      _CareActionCard(
        title: 'Pengelolaan organik',
        subtitle: 'Sanitasi dan praktik budidaya',
        icon: Icons.eco_outlined,
        color: PlantPalette.forest,
        actions: analysis.organicRecommendations,
      ),
      _CareActionCard(
        title: 'Opsi kimiawi',
        subtitle: 'Hanya setelah verifikasi diagnosis dan label',
        icon: Icons.science_outlined,
        color: PlantPalette.orange,
        actions: analysis.chemicalRecommendations,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 960
            ? 3
            : constraints.maxWidth >= 620
            ? 2
            : 1;
        final cardWidth = (constraints.maxWidth - (columns - 1) * 10) / columns;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: cards
              .map((card) => SizedBox(width: cardWidth, child: card))
              .toList(),
        );
      },
    );
  }

  Color _riskColor(String? level) => switch (level) {
    'Tinggi' => PlantPalette.red,
    'Sedang' => PlantPalette.orange,
    'Rendah' => PlantPalette.forest,
    _ => PlantPalette.sage,
  };

  Color _statusColor(String severity) => switch (severity) {
    'Sehat' => PlantPalette.forest,
    'Kering / layu' => PlantPalette.orange,
    _ => PlantPalette.red,
  };
}

class _ImagePanel extends StatelessWidget {
  const _ImagePanel({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      padding: const EdgeInsets.all(12),
      radius: 20,
      opacity: 0.66,
      blur: 17,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(context).textTheme.labelLarge
                ?.copyWith(letterSpacing: 0, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 3),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: PlantPalette.sage),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 235,
            width: double.infinity,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: ColoredBox(
                color: PlantPalette.forest.withValues(alpha: 0.045),
                child: child,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetectionImage extends StatelessWidget {
  const _DetectionImage({required this.analysis});

  final PlantAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    final bounds = analysis.boundingBox;
    if (bounds == null) {
      final image = Image.memory(
        analysis.imageBytes,
        fit: BoxFit.contain,
        cacheWidth: 960,
      );
      return analysis.imageIsMirrored
          ? Transform.flip(flipX: true, child: image)
          : image;
    }
    final imageWithBounds = Center(
      child: AspectRatio(
        aspectRatio: analysis.imageWidth / analysis.imageHeight,
        child: Stack(
          fit: StackFit.expand,
          children: [
            analysis.imageIsMirrored
                ? Transform.flip(
                    flipX: true,
                    child: Image.memory(
                      analysis.imageBytes,
                      fit: BoxFit.fill,
                      cacheWidth: 960,
                    ),
                  )
                : Image.memory(
                    analysis.imageBytes,
                    fit: BoxFit.fill,
                    cacheWidth: 960,
                  ),
            Positioned.fill(
              child: CustomPaint(
                painter: _BoundingBoxPainter(
                  bounds: bounds,
                  color: analysis.severity == 'Sehat'
                      ? PlantPalette.forest
                      : PlantPalette.orange,
                ),
              ),
            ),
          ],
        ),
      ),
    );
    return imageWithBounds;
  }
}

class _BoundingBoxPainter extends CustomPainter {
  const _BoundingBoxPainter({required this.bounds, required this.color});

  final NormalizedBounds bounds;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawRect(
      Rect.fromLTRB(
        bounds.left * size.width,
        bounds.top * size.height,
        bounds.right * size.width,
        bounds.bottom * size.height,
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _BoundingBoxPainter oldDelegate) =>
      oldDelegate.bounds != bounds || oldDelegate.color != color;
}

class _RangeParameter extends StatelessWidget {
  const _RangeParameter({
    required this.label,
    required this.values,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final RangeValues values;
  final int max;
  final ValueChanged<RangeValues> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label  ${values.start.round()}–${values.end.round()}'),
        RangeSlider(
          values: values,
          min: 0,
          max: max.toDouble(),
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _SingleParameter extends StatelessWidget {
  const _SingleParameter({
    required this.label,
    required this.value,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final int value;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: Text(label)),
            Text('$value'),
          ],
        ),
        Slider(
          value: value.toDouble(),
          min: 0,
          max: max.toDouble(),
          divisions: max,
          onChanged: (next) => onChanged(next.round()),
        ),
      ],
    );
  }
}

class _CareMetricCard extends StatelessWidget {
  const _CareMetricCard({
    required this.title,
    required this.icon,
    required this.color,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) => GlassSurface(
    padding: const EdgeInsets.all(14),
    radius: 18,
    opacity: 0.86,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                title,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: PlantPalette.sage,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        child,
      ],
    ),
  );
}

class _SegmentProgress extends StatelessWidget {
  const _SegmentProgress({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final boundedValue = value.clamp(0.0, 100.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(label, style: Theme.of(context).textTheme.bodySmall),
            ),
            Text(
              '${value.toStringAsFixed(1)}%',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
          ],
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: boundedValue / 100,
          minHeight: 6,
          borderRadius: BorderRadius.circular(8),
          color: color,
          backgroundColor: color.withValues(alpha: 0.14),
        ),
      ],
    );
  }
}

class _CareActionCard extends StatelessWidget {
  const _CareActionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.actions,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final List<String> actions;

  @override
  Widget build(BuildContext context) => GlassSurface(
    padding: const EdgeInsets.all(16),
    radius: 18,
    opacity: 0.84,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: PlantPalette.forest,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        for (final action in actions)
          Padding(
            padding: const EdgeInsets.only(bottom: 9),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.check_circle_outline, size: 16, color: color),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    action,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(height: 1.4),
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

class _CareFooterAlert extends StatelessWidget {
  const _CareFooterAlert({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: PlantPalette.orange.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: PlantPalette.orange.withValues(alpha: 0.28)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.info_outline_rounded,
          color: PlantPalette.orange,
          size: 19,
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: PlantPalette.forest,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(message, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ],
    ),
  );
}

class _MetricPill extends StatelessWidget {
  const _MetricPill({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final double value;
  final Color color;

  @override
  Widget build(BuildContext context) => _InfoPill(
    label: label,
    value: '${value.toStringAsFixed(2)}%',
    color: color,
  );
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: PlantPalette.canvas,
        borderRadius: BorderRadius.circular(8),
      ),
      child: RichText(
        text: TextSpan(
          style: Theme.of(context).textTheme.bodySmall,
          children: [
            TextSpan(
              text: '$label  ',
              style: TextStyle(color: color ?? PlantPalette.sage),
            ),
            TextSpan(
              text: value,
              style: const TextStyle(
                color: PlantPalette.ink,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice({required this.message, this.isError = false});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final color = isError ? PlantPalette.red : PlantPalette.forest;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: PlantPalette.ink,
                fontWeight: FontWeight.w500,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
