import 'package:flutter/material.dart';
import '../models/download_item.dart';

/// Port de la QTableWidget de 5 columnas (Archivo, Progreso, Velocidad,
/// Estado, Acciones) de la app original.
class DownloadPanel extends StatelessWidget {
  final List<DownloadItem> downloads;
  final void Function(String id) onPauseResume;
  final void Function(String id) onCancel;

  const DownloadPanel({
    super.key,
    required this.downloads,
    required this.onPauseResume,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(8.0),
            child: Text(
              'Cola de Descargas',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: downloads.isEmpty
                ? const Center(child: Text('Sin descargas'))
                : ListView.builder(
                    itemCount: downloads.length,
                    itemBuilder: (context, index) {
                      final item = downloads[index];
                      return _DownloadRow(
                        item: item,
                        onPauseResume: () => onPauseResume(item.id),
                        onCancel: () => onCancel(item.id),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _DownloadRow extends StatelessWidget {
  final DownloadItem item;
  final VoidCallback onPauseResume;
  final VoidCallback onCancel;

  const _DownloadRow({
    required this.item,
    required this.onPauseResume,
    required this.onCancel,
  });

  bool get _isActive =>
      item.status == DownloadStatus.downloading ||
      item.status == DownloadStatus.paused;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.name,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            LinearProgressIndicator(value: item.progress / 100),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${item.speed} · ${item.statusLabel}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
                if (_isActive) ...[
                  IconButton(
                    iconSize: 20,
                    icon: Icon(
                      item.status == DownloadStatus.paused
                          ? Icons.play_arrow
                          : Icons.pause,
                    ),
                    onPressed: onPauseResume,
                  ),
                  IconButton(
                    iconSize: 20,
                    icon: const Icon(Icons.close),
                    onPressed: onCancel,
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
