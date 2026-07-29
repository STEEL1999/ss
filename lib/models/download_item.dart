enum DownloadStatus { downloading, paused, completed, cancelled, error }

/// Equivalente a una fila de la QTableWidget de descargas en la app original.
class DownloadItem {
  final String id;
  String name;
  int progress; // 0-100
  String speed;
  DownloadStatus status;
  String? errorMessage;

  // Referencias internas para poder pausar/cancelar (dio CancelToken, etc.)
  Object? cancelToken;
  bool isPaused;

  DownloadItem({
    required this.id,
    required this.name,
    this.progress = 0,
    this.speed = '0 KB/s',
    this.status = DownloadStatus.downloading,
    this.errorMessage,
    this.cancelToken,
    this.isPaused = false,
  });

  String get statusLabel {
    switch (status) {
      case DownloadStatus.downloading:
        return 'Descargando...';
      case DownloadStatus.paused:
        return 'Pausado';
      case DownloadStatus.completed:
        return 'Completado';
      case DownloadStatus.cancelled:
        return 'Cancelado';
      case DownloadStatus.error:
        return 'Error';
    }
  }
}
