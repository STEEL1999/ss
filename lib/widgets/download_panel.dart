import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
            if (item.status == DownloadStatus.error &&
                item.errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        item.errorMessage!,
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      onPressed: () => _showErrorDetail(context),
                      child: const Text('Ver detalle'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _showErrorDetail(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.red),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                item.name,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: SelectableText(
            item.errorMessage ?? 'Sin detalles disponibles.',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
          ),
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('Copiar'),
            onPressed: () {
              Clipboard.setData(
                ClipboardData(text: item.errorMessage ?? ''),
              );
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(content: Text('Error copiado al portapapeles')),
              );
            },
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
  }
}
