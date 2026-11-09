import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/monitoring_repository.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_surface.dart';
import '../widgets/garden_artwork.dart';
import '../widgets/soft_motion.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({required this.repository, super.key});

  final MonitoringRepository repository;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final Set<String> _deletingIds = {};
  bool _deletingAll = false;

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.all(22),
            child: GlassSurface(
              radius: 25,
              opacity: 0.88,
              blur: 24,
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 430),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: PlantPalette.forest,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(message),
                    const SizedBox(height: 22),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Batal'),
                        ),
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          style: FilledButton.styleFrom(
                            backgroundColor: PlantPalette.red,
                          ),
                          child: Text(confirmLabel),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ) ??
        false;
  }

  Future<void> _deleteOne(String documentId) async {
    final confirmed = await _confirm(
      title: 'Hapus pengamatan?',
      message: 'Apakah Anda yakin ingin menghapus data pengamatan ini?',
      confirmLabel: 'Hapus',
    );
    if (!confirmed || !mounted) return;

    setState(() => _deletingIds.add(documentId));
    try {
      await widget.repository.deleteRecord(documentId);
      if (mounted) _showSnackBar('Data pengamatan berhasil dihapus.');
    } catch (error) {
      if (mounted) _showSnackBar('Gagal menghapus data: $error', isError: true);
    } finally {
      if (mounted) setState(() => _deletingIds.remove(documentId));
    }
  }

  Future<void> _deleteAll(int count) async {
    final confirmed = await _confirm(
      title: 'Hapus semua riwayat?',
      message:
          'Apakah Anda yakin ingin menghapus semua $count data pengamatan milik akun ini? Tindakan ini tidak dapat dibatalkan.',
      confirmLabel: 'Hapus semua',
    );
    if (!confirmed || !mounted) return;

    setState(() => _deletingAll = true);
    try {
      final deleted = await widget.repository.deleteAllRecords();
      if (mounted) _showSnackBar('$deleted data pengamatan berhasil dihapus.');
    } catch (error) {
      if (mounted) {
        _showSnackBar('Gagal menghapus seluruh riwayat: $error', isError: true);
      }
    } finally {
      if (mounted) setState(() => _deletingAll = false);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: isError ? PlantPalette.red : PlantPalette.forest,
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: widget.repository.watchRecords(),
      builder: (context, snapshot) {
        final records = snapshot.data ?? const <Map<String, dynamic>>[];
        return LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 760;
            final hasSingleMessage =
                snapshot.hasError ||
                snapshot.connectionState == ConnectionState.waiting ||
                records.isEmpty;
            final itemCount = hasSingleMessage ? 3 : records.length + 2;

            final header = SoftEntrance(
              child: GlassSurface(
                padding: EdgeInsets.all(compact ? 16 : 22),
                radius: 22,
                opacity: 0.78,
                blur: 16,
                child: LayoutBuilder(
                  builder: (context, headerConstraints) {
                    final showFullAction = headerConstraints.maxWidth >= 700;
                    final showArtwork = headerConstraints.maxWidth >= 900;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'MONITORING LOG',
                                style: Theme.of(context).textTheme.labelMedium
                                    ?.copyWith(
                                      color: PlantPalette.olive,
                                      letterSpacing: 0,
                                      fontWeight: FontWeight.w700,
                                    ),
                              ),
                            ),
                            if (records.isNotEmpty)
                              showFullAction
                                  ? OutlinedButton.icon(
                                      onPressed: _deletingAll
                                          ? null
                                          : () => _deleteAll(records.length),
                                      icon: _deletingAll
                                          ? const SizedBox.square(
                                              dimension: 16,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Icon(
                                              Icons.delete_sweep_outlined,
                                            ),
                                      label: const Text('Hapus semua riwayat'),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: PlantPalette.red,
                                      ),
                                    )
                                  : IconButton(
                                      tooltip: 'Hapus semua riwayat',
                                      onPressed: _deletingAll
                                          ? null
                                          : () => _deleteAll(records.length),
                                      color: PlantPalette.red,
                                      icon: _deletingAll
                                          ? const SizedBox.square(
                                              dimension: 18,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                              ),
                                            )
                                          : const Icon(
                                              Icons.delete_sweep_outlined,
                                            ),
                                    ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Riwayat monitoring',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style:
                                        (compact
                                                ? Theme.of(context)
                                                      .textTheme
                                                      .titleLarge
                                                : Theme.of(context)
                                                      .textTheme
                                                      .headlineSmall)
                                            ?.copyWith(height: 1.15),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Data diperbarui langsung dari Firestore untuk akun Anda.',
                                    maxLines: compact ? 2 : 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyMedium
                                        ?.copyWith(color: PlantPalette.sage),
                                  ),
                                ],
                              ),
                            ),
                            if (showArtwork) ...[
                              const SizedBox(width: 16),
                              const SizedBox(
                                width: 66,
                                height: 72,
                                child: GardenArtwork(
                                  asset: 'assets/reading-statue.webp',
                                  opacity: 0.34,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            );

            return ListView.builder(
              padding: EdgeInsets.all(compact ? 14 : 22),
              itemCount: itemCount,
              itemBuilder: (context, index) {
                if (index == 0) return header;
                if (index == 1) return const SizedBox(height: 16);
                if (snapshot.hasError) {
                  return Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Tidak dapat memuat riwayat: ${snapshot.error}',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  );
                }
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(30),
                      child: CircularProgressIndicator(),
                    ),
                  );
                }
                if (records.isEmpty) {
                  return SoftEntrance(
                    child: GlassSurface(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                      radius: 22,
                      child: Row(
                        children: [
                          const SizedBox(
                            width: 66,
                            height: 78,
                            child: GardenArtwork(
                              asset: 'assets/classical-statue.webp',
                              opacity: 0.72,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Text(
                              'Belum ada pengamatan tersimpan.',
                              style: Theme.of(context).textTheme.bodyLarge,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final record = records[index - 2];
                final documentId = record['_document_id'] as String;
                return _HistoryCard(
                  record: record,
                  isDeleting: _deletingIds.contains(documentId),
                  onDelete: () => _deleteOne(documentId),
                );
              },
            );
          },
        );
      },
    );
  }
}

String _percentage(Object? value) =>
    value is num ? '${value.toStringAsFixed(1)}%' : '—';

String _timestampLabel(Object? value) {
  final date = switch (value) {
    Timestamp timestamp => timestamp.toDate(),
    DateTime dateTime => dateTime,
    _ => null,
  };
  if (date == null) return 'Waktu tidak tersedia';
  final local = date.toLocal();
  final year = local.year.toString().padLeft(4, '0');
  final month = local.month.toString().padLeft(2, '0');
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$year-$month-$day $hour:$minute';
}

Color _statusColor(String status) => switch (status) {
  'Sehat' => PlantPalette.forest,
  'Kering / layu' => PlantPalette.orange,
  _ => PlantPalette.red,
};

class _HistoryMetric extends StatelessWidget {
  const _HistoryMetric({
    required this.label,
    required this.value,
    required this.valueColor,
  });

  final String label;
  final String value;
  final Color valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 66),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: PlantPalette.border.withValues(alpha: 0.8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall
                ?.copyWith(color: PlantPalette.sage, letterSpacing: 0),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: valueColor, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    required this.record,
    required this.isDeleting,
    required this.onDelete,
  });

  final Map<String, dynamic> record;
  final bool isDeleting;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final timestamp = _timestampLabel(record['timestamp']);
    final status = record['severity']?.toString() ?? '—';
    final location = record['location']?.toString().trim();
    final locationLabel = location == null || location.isEmpty
        ? 'Lokasi tidak tersedia'
        : location;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth = constraints.maxWidth - 36;
          final columns = availableWidth >= 1080
              ? 5
              : availableWidth >= 600
              ? 3
              : 2;
          const spacing = 10.0;
          final tileWidth =
              (availableWidth - spacing * (columns - 1)) / columns;
          final metrics = [
            (
              label: 'Prediksi AI',
              value: record['prediction']?.toString() ?? '—',
              color: PlantPalette.ink,
            ),
            (
              label: 'Area hijau',
              value: _percentage(record['green_ratio']),
              color: PlantPalette.forest,
            ),
            (
              label: 'Area kering',
              value: _percentage(record['yellow_ratio']),
              color: PlantPalette.orange,
            ),
            (
              label: 'Health score',
              value: _percentage(record['health_score']),
              color: PlantPalette.forest,
            ),
            (label: 'Status', value: status, color: _statusColor(status)),
          ];

          return GlassSurface(
            padding: const EdgeInsets.all(18),
            radius: 20,
            opacity: 0.78,
            blur: 10,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _MaskThumbnail(
                      maskString: record['mask_base64']?.toString() ?? '',
                      width: 58,
                      height: 58,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            record['plant_id']?.toString() ?? 'Plant',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$timestamp · $locationLabel',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: PlantPalette.sage),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: 'Hapus data',
                      onPressed: isDeleting ? null : onDelete,
                      color: PlantPalette.red,
                      icon: isDeleting
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.delete_outline),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  children: [
                    for (final metric in metrics)
                      SizedBox(
                        width: tileWidth,
                        child: _HistoryMetric(
                          label: metric.label,
                          value: metric.value,
                          valueColor: metric.color,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _MaskThumbnail extends StatelessWidget {
  const _MaskThumbnail({
    required this.maskString,
    this.width = 52,
    this.height = 42,
  });

  final String maskString;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    if (maskString.isEmpty) {
      return SizedBox(
        width: width,
        height: height,
        child: const Icon(Icons.image_not_supported_outlined, size: 18),
      );
    }
    try {
      return ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: Image.memory(
          base64Decode(maskString),
          width: width,
          height: height,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => SizedBox(
            width: width,
            height: height,
            child: const Icon(Icons.broken_image_outlined, size: 18),
          ),
        ),
      );
    } on FormatException {
      return SizedBox(
        width: width,
        height: height,
        child: const Icon(Icons.broken_image_outlined, size: 18),
      );
    }
  }
}
