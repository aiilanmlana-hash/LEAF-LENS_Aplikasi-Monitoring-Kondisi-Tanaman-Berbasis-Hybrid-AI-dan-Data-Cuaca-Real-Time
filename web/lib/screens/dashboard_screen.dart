import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/monitoring_repository.dart';
import '../services/weather_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_surface.dart';
import '../widgets/garden_artwork.dart';
import '../widgets/soft_motion.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    required this.repository,
    required this.onScan,
    this.weatherService,
    super.key,
  });

  final MonitoringRepository repository;
  final VoidCallback onScan;
  final WeatherService? weatherService;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: repository.watchRecords(),
      builder: (context, snapshot) {
        final records = snapshot.data ?? const <Map<String, dynamic>>[];
        final healthy = records
            .where((record) => record['severity'] == 'Sehat')
            .length;
        final needsAttention = records.length - healthy;
        final average = records.isEmpty
            ? 0.0
            : records.fold<double>(
                    0,
                    (total, record) =>
                        total +
                        ((record['health_score'] as num?)?.toDouble() ?? 0),
                  ) /
                  records.length;
        return ListView(
          padding: EdgeInsets.all(
            MediaQuery.sizeOf(context).width < 600 ? 16 : 24,
          ),
          children: [
            if (snapshot.hasError)
              _ErrorNotice(message: 'Riwayat gagal dimuat: ${snapshot.error}'),
            SoftEntrance(
              child: GlassSurface(
                radius: 22,
                padding: const EdgeInsets.fromLTRB(18, 14, 10, 14),
                opacity: 0.76,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final artWidth = constraints.maxWidth < 430 ? 76.0 : 112.0;
                    return Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'MONITORING OVERVIEW',
                                style: Theme.of(context).textTheme.labelMedium
                                    ?.copyWith(
                                      color: PlantPalette.olive,
                                      letterSpacing: 0,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Kondisi kebun Anda',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Pantau kesehatan daun melalui segmentasi dan klasifikasi visual.',
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(color: PlantPalette.sage),
                              ),
                            ],
                          ),
                        ),
                        SizedBox(
                          width: artWidth,
                          height: 100,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              Positioned(
                                right: 0,
                                bottom: -7,
                                width: artWidth * 0.8,
                                height: 100,
                                child: const GardenArtwork(
                                  asset: 'assets/large-canopy-tree.webp',
                                  opacity: 0.72,
                                ),
                              ),
                              Positioned(
                                right: 0,
                                top: 0,
                                width: artWidth * 0.82,
                                height: 50,
                                child: const GardenArtwork(
                                  asset: 'assets/winged-cupid.webp',
                                  opacity: 0.5,
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
            SoftEntrance(
              child: HoverLift(
                child: GlassSurface(
                  padding: const EdgeInsets.all(24),
                  tint: PlantPalette.forest,
                  opacity: 0.84,
                  radius: 24,
                  blur: 20,
                  borderOpacity: 0.34,
                  shadowOpacity: 0.16,
                  child: Stack(
                    children: [
                      Positioned(
                        right: -14,
                        bottom: -38,
                        width: 118,
                        height: 168,
                        child: const GardenArtwork(
                          asset: 'assets/twisted-tree.webp',
                          opacity: 0.55,
                        ),
                      ),
                      Positioned(
                        right: 76,
                        bottom: -2,
                        width: 92,
                        height: 52,
                        child: const GardenArtwork(
                          asset: 'assets/driftwood.webp',
                          opacity: 0.62,
                        ),
                      ),
                      Wrap(
                        alignment: WrapAlignment.spaceBetween,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        runSpacing: 18,
                        children: [
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 560),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Perhatikan perubahan kecil pada daun.',
                                  style: Theme.of(context).textTheme.titleLarge
                                      ?.copyWith(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                      ),
                                ),
                                const SizedBox(height: 7),
                                Text(
                                  'Ambil gambar untuk mendapatkan rasio area hijau, area kering, dan prediksi AI.',
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(color: Colors.white70),
                                ),
                              ],
                            ),
                          ),
                          PressScale(
                            child: FilledButton.icon(
                              onPressed: onScan,
                              icon: const Icon(Icons.center_focus_strong),
                              label: const Text('Mulai analisis'),
                              style: FilledButton.styleFrom(
                                backgroundColor: PlantPalette.sand,
                                foregroundColor: PlantPalette.ink,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            _WeatherCarePanel(
              latestDiagnosis: records.isEmpty ? null : records.first,
              service: weatherService,
            ),
            const SizedBox(height: 18),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth > 900
                    ? 4
                    : constraints.maxWidth > 560
                    ? 2
                    : 2;
                return GridView.count(
                  crossAxisCount: columns,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: constraints.maxWidth < 390 ? 1.2 : 1.65,
                  children: [
                    for (final (index, card) in [
                      _SummaryCard(
                        label: 'Total scan',
                        value: '${records.length}',
                      ),
                      _SummaryCard(label: 'Daun sehat', value: '$healthy'),
                      _SummaryCard(
                        label: 'Perlu perhatian',
                        value: '$needsAttention',
                      ),
                      _SummaryCard(
                        label: 'Rata-rata health',
                        value: records.isEmpty
                            ? '—'
                            : '${average.toStringAsFixed(1)}%',
                      ),
                    ].indexed)
                      SoftEntrance(
                        delay: Duration(milliseconds: 60 * index),
                        child: HoverLift(child: card),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Pengamatan terbaru',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                TextButton(
                  onPressed: onScan,
                  child: const Text('Analisis tanaman'),
                ),
              ],
            ),
            if (snapshot.connectionState == ConnectionState.waiting)
              const LinearProgressIndicator()
            else if (records.isEmpty)
              GlassSurface(
                padding: const EdgeInsets.fromLTRB(20, 12, 14, 12),
                radius: 20,
                child: Row(
                  children: [
                    const SizedBox(
                      width: 82,
                      height: 66,
                      child: GardenArtwork(
                        asset: 'assets/sleeping-cat.webp',
                        opacity: 0.78,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Belum ada data. Mulai analisis untuk mengisi riwayat.',
                      ),
                    ),
                    const SizedBox(
                      width: 38,
                      height: 58,
                      child: GardenArtwork(
                        asset: 'assets/ivy-sprig.webp',
                        opacity: 0.54,
                      ),
                    ),
                  ],
                ),
              )
            else
              ...records
                  .take(5)
                  .indexed
                  .map(
                    (entry) => SoftEntrance(
                      delay: Duration(milliseconds: 50 * entry.$1),
                      child: _RecentRecord(record: entry.$2),
                    ),
                  ),
          ],
        );
      },
    );
  }
}

class _WeatherCarePanel extends StatefulWidget {
  const _WeatherCarePanel({this.latestDiagnosis, this.service});

  final Map<String, dynamic>? latestDiagnosis;
  final WeatherService? service;

  @override
  State<_WeatherCarePanel> createState() => _WeatherCarePanelState();
}

class _WeatherCarePanelState extends State<_WeatherCarePanel> {
  late final WeatherService _service;
  late final bool _ownsService;
  late Future<CurrentWeather> _weatherRequest;

  @override
  void initState() {
    super.initState();
    _ownsService = widget.service == null;
    _service = widget.service ?? WeatherService();
    _weatherRequest = _service.fetchCurrent();
  }

  @override
  void dispose() {
    if (_ownsService) _service.dispose();
    super.dispose();
  }

  void _refresh() {
    setState(() => _weatherRequest = _service.fetchCurrent());
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<CurrentWeather>(
      future: _weatherRequest,
      builder: (context, snapshot) {
        final loading = snapshot.connectionState == ConnectionState.waiting;
        final weather =
            snapshot.data ??
            CurrentWeather.unavailable('Data cuaca belum tersedia.');
        final locationTitle = loading
            ? 'Menentukan lokasi...'
            : weather.locationName;
        final locationSubtitle = loading
            ? 'Meminta izin lokasi dan memuat cuaca'
            : weather.isAvailable
            ? weather.usedFallback
                  ? 'Lokasi default · cuaca real-time Open-Meteo'
                  : 'Lokasi perangkat · cuaca real-time Open-Meteo'
            : weather.usedFallback
            ? 'Cuaca tidak tersedia · memakai lokasi default'
            : 'Cuaca real-time tidak tersedia';
        final recommendation = wateringRecommendation(
          weather,
          latestDiagnosis: widget.latestDiagnosis,
        );

        return GlassSurface(
          padding: const EdgeInsets.all(20),
          radius: 20,
          opacity: 0.74,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.cloud_outlined, color: PlantPalette.forest),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Cuaca lokal · $locationTitle',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          locationSubtitle,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: PlantPalette.sage),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Perbarui cuaca',
                    onPressed: loading ? null : _refresh,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ],
              ),
              if (loading) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(minHeight: 2),
              ] else ...[
                const SizedBox(height: 16),
                Wrap(
                  spacing: 28,
                  runSpacing: 10,
                  children: [
                    _WeatherReading(
                      icon: Icons.thermostat_rounded,
                      label: 'Suhu',
                      value: weather.temperatureC == null
                          ? '—'
                          : '${weather.temperatureC!.toStringAsFixed(1)} °C',
                    ),
                    _WeatherReading(
                      icon: Icons.water_drop_outlined,
                      label: 'Kelembapan',
                      value: weather.humidityPct == null
                          ? '—'
                          : '${weather.humidityPct!.toStringAsFixed(0)}%',
                    ),
                    _WeatherReading(
                      icon: Icons.grain_rounded,
                      label: 'Hujan',
                      value: weather.precipitationMm == null
                          ? '—'
                          : '${weather.precipitationMm!.toStringAsFixed(1)} mm',
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 14),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.eco_outlined,
                      color: PlantPalette.olive,
                      size: 21,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Rekomendasi perawatan hari ini',
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 5),
                          Text(recommendation),
                          if (!weather.isAvailable &&
                              weather.error != null) ...[
                            const SizedBox(height: 5),
                            Text(
                              'Periksa koneksi internet untuk memuat cuaca.',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: PlantPalette.sage),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _WeatherReading extends StatelessWidget {
  const _WeatherReading({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: PlantPalette.sage),
        const SizedBox(width: 6),
        Text('$label: ', style: Theme.of(context).textTheme.bodySmall),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      padding: const EdgeInsets.all(17),
      radius: 20,
      opacity: 0.69,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Icon(Icons.eco_outlined, color: PlantPalette.olive),
          Text(
            value,
            style: Theme.of(context).textTheme.headlineSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _RecentRecord extends StatelessWidget {
  const _RecentRecord({required this.record});

  final Map<String, dynamic> record;

  @override
  Widget build(BuildContext context) {
    final severity = record['severity']?.toString() ?? 'Tidak diketahui';
    final color = severity == 'Sehat'
        ? PlantPalette.forest
        : severity == 'Kering / layu'
        ? PlantPalette.orange
        : PlantPalette.red;
    final timestamp = (record['timestamp'] as Timestamp).toDate().toLocal();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: GlassSurface(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        radius: 18,
        opacity: 0.66,
        child: ListTile(
          leading: Icon(Icons.spa_outlined, color: color),
          title: Text(record['plant_id']?.toString() ?? 'Plant'),
          subtitle: Text(
            '${record['prediction'] ?? 'AI tidak tersedia'} · ${timestamp.toString().substring(0, 16)}',
          ),
          trailing: Text(
            '${(record['green_ratio'] as num?)?.toStringAsFixed(1) ?? '0.0'}%',
            style: TextStyle(color: color, fontWeight: FontWeight.w700),
          ),
        ),
      ),
    );
  }
}

class _ErrorNotice extends StatelessWidget {
  const _ErrorNotice({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: PlantPalette.red.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(9),
    ),
    child: Text(message, style: const TextStyle(color: PlantPalette.red)),
  );
}
