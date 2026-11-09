import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:flutter/material.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/monitoring_record.dart';
import '../providers/monitoring_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/garden_artwork.dart';
import '../widgets/glass_surface.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _search = TextEditingController();
  String _severity = 'Semua status';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<MonitoringRecord> _filtered(List<MonitoringRecord> records) {
    final query = _search.text.trim().toLowerCase();
    return records.where((record) {
      final matchesText = query.isEmpty ||
          record.plantId.toLowerCase().contains(query) ||
          record.location.toLowerCase().contains(query) ||
          record.prediction.toLowerCase().contains(query);
      return matchesText &&
          (_severity == 'Semua status' || record.severity == _severity);
    }).toList(growable: false);
  }

  Future<void> _exportCsv(List<MonitoringRecord> records) async {
    final rows = <List<Object?>>[
      [
        'Timestamp',
        'Plant ID',
        'Location',
        'Green %',
        'Yellow %',
        'AI prediction',
        'Confidence %',
        'Health %',
        'Severity',
        'Mask saved'
      ],
      ...records.map((record) => [
            record.timestamp.toIso8601String(),
            record.plantId,
            record.location,
            record.greenRatio,
            record.yellowRatio,
            record.prediction,
            record.confidence,
            record.healthScore,
            record.severity,
            record.maskBase64.isNotEmpty,
          ]),
    ];
    final bytes = utf8.encode(const ListToCsvConverter().convert(rows));
    await Share.shareXFiles([
      XFile.fromData(
        bytes,
        mimeType: 'text/csv',
        name: 'smart_plant_history.csv',
      ),
    ], text: 'Smart Plant AI monitoring history');
  }

  Future<void> _exportPdf(List<MonitoringRecord> records) async {
    final report = pw.Document();
    report.addPage(
      pw.MultiPage(
        build: (_) => [
          pw.Header(
              level: 0, child: pw.Text('Smart Plant AI - Monitoring History')),
          pw.SizedBox(height: 16),
          pw.TableHelper.fromTextArray(
            headers: [
              'Date',
              'Plant',
              'Green',
              'Yellow',
              'Prediction',
              'Health',
              'Status'
            ],
            data: records
                .map((record) => [
                      record.timestamp.toIso8601String().substring(0, 16),
                      record.plantId,
                      '${record.greenRatio.toStringAsFixed(1)}%',
                      '${record.yellowRatio.toStringAsFixed(1)}%',
                      record.prediction,
                      '${record.healthScore.toStringAsFixed(1)}%',
                      record.severity,
                    ])
                .toList(),
          ),
        ],
      ),
    );
    final bytes = await report.save();
    await Share.shareXFiles([
      XFile.fromData(
        bytes,
        mimeType: 'application/pdf',
        name: 'smart_plant_history.pdf',
      ),
    ], text: 'Smart Plant AI monitoring report');
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<MonitoringProvider>(
      builder: (context, monitoring, _) {
        final records = _filtered(monitoring.records);
        return Column(
          children: [
            if (monitoring.errorMessage != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text(
                  monitoring.errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: GlassSurface(
                padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                radius: 22,
                child: SizedBox(
                  height: 88,
                  child: Stack(
                    children: [
                      const Positioned(
                        right: -2,
                        bottom: -16,
                        width: 82,
                        height: 104,
                        child: GardenArtwork(
                          asset: 'assets/reading-statue.webp',
                          opacity: 0.6,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(right: 76),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'MONITORING LOG',
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
                              'Riwayat monitoring',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.headlineSmall,
                            ),
                            Text(
                              'Data tersimpan untuk akun Anda.',
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
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Column(
                children: [
                  TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Cari tanaman, lokasi, atau prediksi',
                      prefixIcon: Icon(Icons.search),
                    ),
                  ),
                  const SizedBox(height: 8),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final statusFilter = DropdownButtonFormField<String>(
                        isExpanded: true,
                        initialValue: _severity,
                        decoration: const InputDecoration(
                          labelText: 'Status',
                        ),
                        items: const [
                          DropdownMenuItem(
                              value: 'Semua status',
                              child: Text(
                                'Semua status',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              )),
                          DropdownMenuItem(
                              value: 'Sehat',
                              child: Text('Sehat', maxLines: 1)),
                          DropdownMenuItem(
                              value: 'Perlu perhatian',
                              child: Text(
                                'Perlu perhatian',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              )),
                          DropdownMenuItem(
                              value: 'Kritis',
                              child: Text('Kritis', maxLines: 1)),
                          DropdownMenuItem(
                              value: 'Tidak diketahui',
                              child: Text(
                                'Tidak diketahui',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              )),
                        ],
                        onChanged: (value) =>
                            setState(() => _severity = value ?? 'Semua status'),
                      );
                      final exportMenu = PopupMenuButton<String>(
                        tooltip: 'Ekspor riwayat',
                        icon: const Icon(Icons.file_download_outlined),
                        style: IconButton.styleFrom(
                          foregroundColor: PlantColors.olive,
                          side: BorderSide(
                              color: PlantColors.olive.withValues(alpha: 0.3)),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                              value: 'csv', child: Text('Ekspor CSV')),
                          PopupMenuItem(
                              value: 'pdf', child: Text('Ekspor PDF')),
                        ],
                        onSelected: (type) => type == 'csv'
                            ? _exportCsv(records)
                            : _exportPdf(records),
                      );
                      if (constraints.maxWidth < 440) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            statusFilter,
                            Align(
                              alignment: Alignment.centerRight,
                              child: exportMenu,
                            ),
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: statusFilter),
                          const SizedBox(width: 8),
                          exportMenu,
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child: records.isEmpty
                  ? const Center(
                      child: Text('Belum ada data pengamatan yang sesuai.'),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                      itemCount: records.length,
                      itemBuilder: (context, index) =>
                          _HistoryCard(record: records[index]),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({required this.record});

  final MonitoringRecord record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusColor = switch (record.severity) {
      'Sehat' => PlantColors.leaf,
      'Kritis' => const Color(0xFFB4513E),
      _ => PlantColors.clay,
    };
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: record.maskBase64.isNotEmpty
                  ? Image.memory(
                      base64Decode(record.maskBase64),
                      width: 78,
                      height: 78,
                      fit: BoxFit.cover,
                    )
                  : Container(
                      width: 78,
                      height: 78,
                      color:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
                      child: const Icon(Icons.image_not_supported_outlined),
                    ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                          child: Text(record.plantId,
                              style: theme.textTheme.titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700))),
                      Chip(
                        label: Text(record.severity),
                        visualDensity: VisualDensity.compact,
                        backgroundColor: statusColor.withValues(alpha: 0.13),
                        labelStyle: TextStyle(
                            color: statusColor, fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  Text(
                    '${record.timestamp.toLocal()} · ${record.location}',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 4),
                  Text(
                      'Hijau ${record.greenRatio}% · Kering ${record.yellowRatio}%'),
                  Text('${record.prediction} · AI ${record.confidence}%'),
                  Text(
                    'Skor kesehatan ${record.healthScore}%',
                    style: TextStyle(
                        color: PlantColors.olive, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
