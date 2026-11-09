import 'dart:async';
import 'dart:convert';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:camera_macos/camera_macos.dart' as macos;
import 'package:provider/provider.dart';

import '../models/monitoring_record.dart';
import '../providers/monitoring_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/garden_artwork.dart';
import '../widgets/glass_surface.dart';

class ScanScreen extends StatefulWidget {
  const ScanScreen({required this.isActive, super.key});

  final bool isActive;

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  final _picker = ImagePicker();
  final _tts = FlutterTts();
  final _plantId = TextEditingController(text: 'P001');
  final _location = TextEditingController(text: 'Polije Sidoarjo');
  CameraController? _cameraController;
  macos.CameraMacOSController? _macCameraController;
  List<CameraDescription> _mobileCameras = [];
  List<macos.CameraMacOSDevice> _macCameras = [];
  CameraDescription? _selectedMobileCamera;
  macos.CameraMacOSDevice? _selectedMacCamera;
  String? _cameraError;
  bool _cameraInitializing = false;
  Uint8List? _selectedImage;
  String _selectedImageName = 'plant_upload.jpg';
  MonitoringRecord? _result;
  bool _imageNeedsUnmirroring = false;
  bool _cameraMirrored = false;
  int _hueMin = 25;
  int _hueMax = 95;
  int _saturationMin = 35;
  int _valueMin = 30;
  int _kernelSize = 5;

  bool get _isMacDesktop =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

  @override
  void initState() {
    super.initState();
    if (widget.isActive) _initializeCamera();
  }

  @override
  void didUpdateWidget(covariant ScanScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isActive && widget.isActive) {
      _initializeCamera();
    } else if (oldWidget.isActive && !widget.isActive) {
      _releaseCamera();
    }
  }

  void _releaseCamera() {
    final controller = _cameraController;
    final macController = _macCameraController;
    _cameraController = null;
    _macCameraController = null;
    _cameraMirrored = false;
    if (controller != null) unawaited(controller.dispose());
    if (macController != null) unawaited(macController.destroy());
  }

  Future<void> _initializeCamera() async {
    if (_cameraInitializing ||
        _cameraController != null ||
        _macCameraController != null) {
      return;
    }
    _cameraInitializing = true;
    try {
      if (_isMacDesktop) {
        final cameras = await macos.CameraMacOS.instance.listDevices(
          deviceType: macos.CameraMacOSDeviceType.video,
        );
        if (!mounted || !widget.isActive) return;
        final previousId = _selectedMacCamera?.deviceId;
        final selected = cameras.where((item) => item.deviceId == previousId);
        setState(() {
          _macCameras = cameras;
          _selectedMacCamera = selected.isNotEmpty
              ? selected.first
              : cameras.isEmpty
                  ? null
                  : cameras.first;
          _cameraError = cameras.isEmpty
              ? 'Kamera tidak ditemukan. Hubungkan kamera atau aktifkan iPhone Continuity Camera.'
              : null;
        });
        return;
      }

      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw CameraException(
            'NoCamera', 'Kamera tidak tersedia pada perangkat ini.');
      }
      final camera = cameras.firstWhere(
        (item) => item.name == _selectedMobileCamera?.name,
        orElse: () => cameras.firstWhere(
          (item) => item.lensDirection == CameraLensDirection.back,
          orElse: () => cameras.first,
        ),
      );
      await _startMobileCamera(cameras, camera);
    } on CameraException catch (error) {
      if (mounted) {
        setState(() => _cameraError = error.description ?? error.code);
      }
    } on PlatformException catch (error) {
      if (mounted) setState(() => _cameraError = error.message ?? error.code);
    } finally {
      _cameraInitializing = false;
    }
  }

  Future<void> _startMobileCamera(
    List<CameraDescription> cameras,
    CameraDescription camera,
  ) async {
    final controller = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: false,
    );
    await controller.initialize();
    if (!mounted || !widget.isActive) {
      await controller.dispose();
      return;
    }
    setState(() {
      _mobileCameras = cameras;
      _selectedMobileCamera = camera;
      _cameraController = controller;
      _cameraMirrored = camera.lensDirection == CameraLensDirection.front;
      _cameraError = null;
    });
  }

  Future<void> _refreshCameras() async {
    _releaseCamera();
    setState(() {
      _cameraError = null;
      _macCameras = [];
      _mobileCameras = [];
    });
    await _initializeCamera();
  }

  Future<void> _selectMobileCamera(String? cameraName) async {
    if (cameraName == null) return;
    final camera = _mobileCameras.firstWhere((item) => item.name == cameraName);
    final previous = _cameraController;
    setState(() {
      _cameraController = null;
      _selectedMobileCamera = camera;
    });
    if (previous != null) await previous.dispose();
    try {
      await _startMobileCamera(_mobileCameras, camera);
    } on CameraException catch (error) {
      if (mounted) {
        setState(() => _cameraError = error.description ?? error.code);
      }
    }
  }

  Future<void> _selectMacCamera(String? deviceId) async {
    if (deviceId == null) return;
    final camera = _macCameras.firstWhere((item) => item.deviceId == deviceId);
    final previous = _macCameraController;
    if (previous != null) {
      _macCameraController = null;
      await previous.destroy();
    }
    if (mounted) {
      setState(() {
        _selectedMacCamera = camera;
        _cameraError = null;
      });
    }
  }

  void _onMacCameraInitialized(macos.CameraMacOSController controller) {
    if (!mounted || !widget.isActive) {
      unawaited(controller.destroy());
      return;
    }
    setState(() {
      _macCameraController = controller;
      _cameraMirrored = false;
      _cameraError = null;
    });
  }

  Future<void> _pickImage(ImageSource source) async {
    try {
      final image = await _picker.pickImage(source: source, imageQuality: 92);
      if (image == null || !mounted) return;
      final bytes = await image.readAsBytes();
      if (!mounted) return;
      setState(() {
        _selectedImage = bytes;
        _selectedImageName = image.name;
        _imageNeedsUnmirroring = false;
        _result = null;
      });
    } on PlatformException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Tidak dapat membuka galeri: ${error.message ?? error.code}')),
        );
      }
    }
  }

  Future<void> _capturePhoto() async {
    if (_isMacDesktop) {
      final controller = _macCameraController;
      if (controller == null) return;
      try {
        final picture = await controller.takePicture();
        final bytes = picture?.bytes;
        if (bytes == null || !mounted) return;
        if (!mounted) return;
        setState(() {
          _selectedImage = bytes;
          _selectedImageName =
              'plant_${DateTime.now().microsecondsSinceEpoch}.jpg';
          _imageNeedsUnmirroring = false;
          _result = null;
        });
      } on PlatformException catch (error) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(
                    'Pengambilan foto gagal: ${error.message ?? error.code}')),
          );
        }
      }
      return;
    }

    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      await _pickImage(ImageSource.camera);
      return;
    }
    try {
      final image = await controller.takePicture();
      final bytes = await image.readAsBytes();
      if (!mounted) return;
      setState(() {
        _selectedImage = bytes;
        _selectedImageName = image.name;
        _imageNeedsUnmirroring = _cameraMirrored;
        _result = null;
      });
    } on CameraException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(
                  'Pengambilan foto gagal: ${error.description ?? error.code}')),
        );
      }
    }
  }

  Future<void> _analyze() async {
    final image = _selectedImage;
    if (image == null) return;
    final provider = context.read<MonitoringProvider>();
    final result = await provider.analyze(
      imageBytes: image,
      imageName: _selectedImageName,
      plantId: _plantId.text.trim(),
      location: _location.text.trim(),
      flipHorizontal: _imageNeedsUnmirroring,
      hueMin: _hueMin,
      hueMax: _hueMax,
      saturationMin: _saturationMin,
      valueMin: _valueMin,
      kernelSize: _kernelSize,
    );
    if (!mounted || result == null) return;
    setState(() => _result = result);
    try {
      await _speak(result);
    } on PlatformException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Analisis tersimpan, tetapi suara Indonesia tidak tersedia pada perangkat ini.')),
        );
      }
    }
  }

  Future<void> _speak(MonitoringRecord result) async {
    await _tts.setLanguage('id-ID');
    await _tts.setSpeechRate(0.48);
    try {
      await _tts.setVoice({'name': 'Damayanti', 'locale': 'id-ID'});
    } on PlatformException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text(
                  'Suara Damayanti tidak tersedia; menggunakan suara Indonesia bawaan.')),
        );
      }
    }
    await _tts.speak(
      'Hasil analisis tanaman ${result.plantId}. ${result.prediction}. '
      'Skor kesehatan ${result.healthScore.toStringAsFixed(0)} persen. '
      'Status ${result.severity}.',
    );
  }

  @override
  void dispose() {
    _releaseCamera();
    _plantId.dispose();
    _location.dispose();
    _tts.stop();
    super.dispose();
  }

  Widget _cameraPreview(BuildContext context) {
    if (!widget.isActive) {
      return const _CameraPlaceholder(message: 'Kamera dijeda');
    }

    if (_isMacDesktop) {
      final camera = _selectedMacCamera;
      if (camera == null) {
        return _CameraPlaceholder(
          message: _cameraError ?? 'Mencari kamera Mac dan kamera terhubung…',
        );
      }
      return SizedBox(
        height: 330,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: macos.CameraMacOSView(
            key: ValueKey(camera.deviceId),
            deviceId: camera.deviceId,
            cameraMode: macos.CameraMacOSMode.photo,
            pictureFormat: macos.PictureFormat.jpg,
            isVideoMirrored: false,
            enableAudio: false,
            fit: BoxFit.cover,
            onCameraInizialized: _onMacCameraInitialized,
            onCameraLoading: (error) => _CameraPlaceholder(
              message: error == null
                  ? 'Menghubungkan ke ${camera.localizedName ?? 'kamera'}…'
                  : 'Kamera tidak tersedia: $error',
            ),
          ),
        ),
      );
    }

    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) {
      return _CameraPlaceholder(
        message: _cameraError ?? 'Menyiapkan kamera perangkat…',
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: AspectRatio(
        aspectRatio: controller.value.aspectRatio,
        child: CameraPreview(controller),
      ),
    );
  }

  Widget _cameraSelector() {
    if (_isMacDesktop) {
      if (_macCameras.isEmpty) return const SizedBox.shrink();
      return DropdownButtonFormField<String>(
        initialValue: _selectedMacCamera?.deviceId,
        decoration: const InputDecoration(
          labelText: 'Perangkat kamera',
          prefixIcon: Icon(Icons.videocam_outlined),
        ),
        items: [
          for (final camera in _macCameras)
            DropdownMenuItem(
              value: camera.deviceId,
              child: Text(
                camera.localizedName ?? camera.deviceId,
                overflow: TextOverflow.ellipsis,
              ),
            ),
        ],
        onChanged: _selectMacCamera,
      );
    }

    if (_mobileCameras.isEmpty) return const SizedBox.shrink();
    return DropdownButtonFormField<String>(
      initialValue: _selectedMobileCamera?.name,
      decoration: const InputDecoration(
        labelText: 'Perangkat kamera',
        prefixIcon: Icon(Icons.videocam_outlined),
      ),
      items: [
        for (final camera in _mobileCameras)
          DropdownMenuItem(
            value: camera.name,
            child: Text(
              'Kamera ${camera.lensDirection.name}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: _selectMobileCamera,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<MonitoringProvider>(
      builder: (context, monitoring, _) {
        final result = _result;
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            GlassSurface(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
              radius: 22,
              child: SizedBox(
                height: 104,
                child: Stack(
                  children: [
                    const Positioned(
                      right: -6,
                      top: -10,
                      width: 76,
                      height: 98,
                      child: GardenArtwork(
                        asset: 'assets/moss-branch.webp',
                        opacity: 0.62,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 76),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'ANALISIS TANAMAN',
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium
                                ?.copyWith(
                                  color: PlantColors.olive,
                                  letterSpacing: 1.2,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Segmentasi daun',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          Text(
                            'Gunakan kamera atau unggah foto daun.',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: PlantColors.sage),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            GlassSurface(
              padding: const EdgeInsets.all(8),
              radius: 24,
              child: _cameraPreview(context),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(child: _cameraSelector()),
                const SizedBox(width: 8),
                IconButton.outlined(
                  tooltip: 'Muat ulang daftar kamera',
                  onPressed: widget.isActive ? _refreshCameras : null,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _isMacDesktop
                        ? _macCameraController == null
                            ? null
                            : _capturePhoto
                        : _cameraController == null
                            ? _pickImageCameraFallback
                            : _capturePhoto,
                    icon: const Icon(Icons.camera_alt_outlined),
                    label: const Text('Ambil foto'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickImage(ImageSource.gallery),
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Galeri / file'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_selectedImage != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: Image.memory(
                  _selectedImage!,
                  height: 160,
                  fit: BoxFit.cover,
                  width: double.infinity,
                ),
              )
            else
              Container(
                height: 190,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Center(
                    child: Icon(
                  Icons.add_a_photo_outlined,
                  size: 48,
                  color: PlantColors.sage.withValues(alpha: 0.72),
                )),
              ),
            const SizedBox(height: 16),
            TextField(
              controller: _plantId,
              decoration: const InputDecoration(
                labelText: 'ID tanaman',
                prefixIcon: Icon(Icons.local_florist_outlined),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _location,
              decoration: const InputDecoration(
                labelText: 'Lokasi',
                prefixIcon: Icon(Icons.place_outlined),
              ),
            ),
            const SizedBox(height: 18),
            Text('Parameter segmentasi',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _RangeControl(
              label: 'Rentang Hue',
              start: _hueMin,
              end: _hueMax,
              max: 179,
              onChanged: (range) => setState(() {
                _hueMin = range.start.round();
                _hueMax = range.end.round();
              }),
            ),
            _ValueControl(
              label: 'Saturasi minimum',
              value: _saturationMin,
              max: 255,
              onChanged: (value) => setState(() => _saturationMin = value),
            ),
            _ValueControl(
              label: 'Kecerahan minimum',
              value: _valueMin,
              max: 255,
              onChanged: (value) => setState(() => _valueMin = value),
            ),
            _ValueControl(
              label: 'Ukuran kernel morfologi',
              value: _kernelSize,
              max: 15,
              divisions: 7,
              onChanged: (value) => setState(
                  () => _kernelSize = value.isEven ? value + 1 : value),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed:
                  _selectedImage == null || monitoring.isBusy ? null : _analyze,
              icon: monitoring.isBusy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_awesome),
              label: Text(
                monitoring.isBusy ? 'Menganalisis…' : 'Analisis tanaman',
              ),
            ),
            if (monitoring.errorMessage != null) ...[
              const SizedBox(height: 12),
              Text(monitoring.errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            if (result != null) ...[
              const SizedBox(height: 20),
              _ResultCard(record: result, onSpeak: () => _speak(result)),
            ],
          ],
        );
      },
    );
  }

  Future<void> _pickImageCameraFallback() async {
    await _pickImage(ImageSource.camera);
  }
}

class _RangeControl extends StatelessWidget {
  const _RangeControl({
    required this.label,
    required this.start,
    required this.end,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final int start;
  final int end;
  final int max;
  final ValueChanged<RangeValues> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label: $start – $end'),
        RangeSlider(
          values: RangeValues(start.toDouble(), end.toDouble()),
          min: 0,
          max: max.toDouble(),
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _CameraPlaceholder extends StatelessWidget {
  const _CameraPlaceholder({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      height: 260,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.photo_camera_outlined,
                  size: 38, color: theme.colorScheme.primary),
              const SizedBox(height: 12),
              Text(message, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}

class _ValueControl extends StatelessWidget {
  const _ValueControl({
    required this.label,
    required this.value,
    required this.max,
    required this.onChanged,
    this.divisions = 25,
  });

  final String label;
  final int value;
  final int max;
  final int divisions;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [Text(label), Text('$value')],
        ),
        Slider(
          value: value.toDouble(),
          min: max == 15 ? 1 : 0,
          max: max.toDouble(),
          divisions: divisions,
          onChanged: (number) => onChanged(number.round()),
        ),
      ],
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.record, required this.onSpeak});

  final MonitoringRecord record;
  final Future<void> Function() onSpeak;

  @override
  Widget build(BuildContext context) {
    final statusColor = switch (record.severity) {
      'Sehat' => PlantColors.leaf,
      'Kritis' => const Color(0xFFB4513E),
      _ => PlantColors.clay,
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                    child: Text(record.severity,
                        style: Theme.of(context).textTheme.titleLarge)),
                Chip(
                  label: Text('${record.healthScore.toStringAsFixed(1)}%'),
                  avatar: const Icon(Icons.favorite_outline, size: 16),
                  backgroundColor: statusColor.withValues(alpha: 0.15),
                ),
              ],
            ),
            Text(
                '${record.prediction} · keyakinan ${record.confidence.toStringAsFixed(1)}%'),
            const SizedBox(height: 8),
            Text(
              'Hijau ${record.greenRatio.toStringAsFixed(1)}%  ·  '
              'Kering ${record.yellowRatio.toStringAsFixed(1)}%',
            ),
            const SizedBox(height: 12),
            if (record.maskBase64.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.memory(
                  base64Decode(record.maskBase64),
                  height: 170,
                  fit: BoxFit.contain,
                ),
              ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: onSpeak,
              icon: const Icon(Icons.volume_up_outlined),
              label: const Text('Dengarkan analisis'),
            ),
          ],
        ),
      ),
    );
  }
}
