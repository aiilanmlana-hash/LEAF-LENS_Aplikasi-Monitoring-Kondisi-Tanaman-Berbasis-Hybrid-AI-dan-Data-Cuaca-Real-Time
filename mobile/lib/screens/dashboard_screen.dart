import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/monitoring_record.dart';
import '../providers/monitoring_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/garden_artwork.dart';
import '../widgets/glass_surface.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({required this.onScan, super.key});

  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    return Consumer<MonitoringProvider>(
      builder: (context, monitoring, _) {
        final records = monitoring.records;
        final healthy =
            records.where((item) => item.severity == 'Sehat').length;
        final dryOrInfected = records.length - healthy;
        final average = records.isEmpty
            ? 0.0
            : records.fold<double>(0, (sum, item) => sum + item.healthScore) /
                records.length;
        return ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
          children: [
            if (monitoring.errorMessage != null) ...[
              _DataErrorBanner(message: monitoring.errorMessage!),
              const SizedBox(height: 12),
            ],
            GlassSurface(
              padding: const EdgeInsets.fromLTRB(18, 15, 12, 15),
              radius: 22,
              child: SizedBox(
                height: 112,
                child: Stack(
                  children: [
                    const Positioned(
                      right: -4,
                      top: -12,
                      width: 92,
                      height: 116,
                      child: GardenArtwork(
                        asset: 'assets/broad-tree.webp',
                        opacity: 0.72,
                      ),
                    ),
                    const Positioned(
                      right: 68,
                      top: 0,
                      width: 55,
                      height: 66,
                      child: GardenArtwork(
                        asset: 'assets/swallow-bird.webp',
                        opacity: 0.58,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(right: 108),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            'MONITORING OVERVIEW',
                            style: Theme.of(context)
                                .textTheme
                                .labelMedium
                                ?.copyWith(
                                  color: PlantColors.olive,
                                  letterSpacing: 1.2,
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            'Kondisi kebun Anda',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.headlineSmall,
                          ),
                          Text(
                            'Pantau kesehatan daun melalui segmentasi dan klasifikasi visual.',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: PlantColors.sage,
                                    ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 480;
                return Container(
                  padding: const EdgeInsets.all(22),
                  decoration: BoxDecoration(
                    color: PlantColors.forest.withValues(alpha: 0.94),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.3),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: PlantColors.forest.withValues(alpha: 0.12),
                        blurRadius: 18,
                        offset: const Offset(0, 7),
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      Positioned(
                        right: -18,
                        bottom: -34,
                        width: compact ? 100 : 138,
                        height: compact ? 170 : 192,
                        child: const GardenArtwork(
                          asset: 'assets/twisted-tree.webp',
                          opacity: 0.52,
                        ),
                      ),
                      Positioned(
                        right: compact ? 62 : 90,
                        bottom: -22,
                        width: 72,
                        height: 74,
                        child: const GardenArtwork(
                          asset: 'assets/driftwood.webp',
                          opacity: 0.74,
                        ),
                      ),
                      Padding(
                        padding: EdgeInsets.only(right: compact ? 70 : 150),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Perhatikan perubahan kecil pada daun.',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleLarge
                                  ?.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                            const SizedBox(height: 7),
                            Text(
                              'Ambil gambar untuk mendapatkan rasio area hijau, area kering, dan prediksi AI.',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
                                  ?.copyWith(
                                    color: Colors.white.withValues(alpha: 0.84),
                                  ),
                            ),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: onScan,
                              icon: const Icon(Icons.center_focus_strong),
                              label: const Text('Mulai analisis'),
                              style: FilledButton.styleFrom(
                                backgroundColor: PlantColors.sand,
                                foregroundColor: PlantColors.espresso,
                                minimumSize: const Size(150, 46),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 18),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth > 720 ? 4 : 2;
                return GridView.count(
                  crossAxisCount: columns,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: columns == 4
                      ? (constraints.maxWidth >= 1000 ? 1.45 : 1.15)
                      : 1.1,
                  children: [
                    _SummaryCard(
                      title: 'Total pemindaian',
                      value: '${records.length}',
                      icon: Icons.document_scanner_outlined,
                      accent: PlantColors.olive,
                    ),
                    _SummaryCard(
                      title: 'Daun sehat',
                      value: '$healthy',
                      icon: Icons.eco_outlined,
                      accent: PlantColors.leaf,
                    ),
                    _SummaryCard(
                      title: 'Kering / terinfeksi',
                      value: '$dryOrInfected',
                      icon: Icons.warning_amber_outlined,
                      accent: PlantColors.clay,
                    ),
                    _SummaryCard(
                      title: 'Rata-rata kesehatan',
                      value: '${average.toStringAsFixed(1)}%',
                      icon: Icons.monitor_heart_outlined,
                      accent: PlantColors.olive,
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 24),
            Text('Tren kesehatan',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 20, 20, 12),
                child: SizedBox(
                  height: 190,
                  child: records.isEmpty
                      ? const Center(
                          child: Text('Scan tanaman untuk mulai melihat tren.'))
                      : _HealthChart(records: records),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text('Aktivitas terbaru',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 10),
            if (records.isEmpty)
              const Card(
                child: ListTile(
                  leading: Icon(Icons.spa_outlined, color: PlantColors.olive),
                  title: Text('Belum ada data monitoring'),
                  subtitle:
                      Text('Hasil analisis akan tersimpan ke akun Firebase.'),
                ),
              )
            else
              ...records.take(5).map((record) => _RecentRecord(record: record)),
          ],
        );
      },
    );
  }
}

class _DataErrorBanner extends StatelessWidget {
  const _DataErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        message,
        style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.title,
    required this.value,
    required this.icon,
    this.accent,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: (accent ?? PlantColors.olive).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 20, color: accent ?? PlantColors.olive),
            ),
            Text(value,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
            Text(
              title,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HealthChart extends StatelessWidget {
  const _HealthChart({required this.records});

  final List<MonitoringRecord> records;

  @override
  Widget build(BuildContext context) {
    final trend = records.reversed.take(7).toList(growable: false);
    return BarChart(
      BarChartData(
        minY: 0,
        maxY: 100,
        gridData: const FlGridData(show: true, drawVerticalLine: false),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: 34),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, _) {
                final index = value.toInt();
                if (index < 0 || index >= trend.length) {
                  return const SizedBox.shrink();
                }
                final date = trend[index].timestamp;
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text('${date.month}/${date.day}',
                      style: const TextStyle(fontSize: 10)),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (var index = 0; index < trend.length; index++)
            BarChartGroupData(
              x: index,
              barRods: [
                BarChartRodData(
                  toY: trend[index].healthScore,
                  width: 18,
                  borderRadius: BorderRadius.circular(5),
                  color: trend[index].healthScore >= 75
                      ? PlantColors.leaf
                      : PlantColors.clay,
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _RecentRecord extends StatelessWidget {
  const _RecentRecord({required this.record});

  final MonitoringRecord record;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          record.severity == 'Sehat'
              ? Icons.eco
              : Icons.health_and_safety_outlined,
          color:
              record.severity == 'Sehat' ? PlantColors.leaf : PlantColors.clay,
        ),
        title: Text(
            '${record.plantId} · ${record.healthScore.toStringAsFixed(0)}%'),
        subtitle: Text('${record.prediction} · ${record.timestamp.toLocal()}'),
        trailing: Text(record.severity),
      ),
    );
  }
}
