import 'dart:async';
import 'package:flutter/services.dart';

/// Puente hacia downloader.py (corriendo dentro de Chaquopy) que envuelve
/// yt-dlp igual que DownloadWorker._download_ytdlp y el extractor custom
/// de pimpbunny.com en la app original.
class YtdlpService {
  static const MethodChannel _channel = MethodChannel('vidbrowser/ytdlp');
  static const EventChannel _progressChannel =
      EventChannel('vidbrowser/ytdlp_progress');

  Stream<Map<String, dynamic>>? _progressStream;

  Stream<Map<String, dynamic>> get progressStream {
    _progressStream ??= _progressChannel
        .receiveBroadcastStream()
        .map((event) => Map<String, dynamic>.from(event as Map));
    return _progressStream!;
  }

  /// Equivalente a probe_opts + ydl.extract_info(url, download=False):
  /// devuelve título y lista de alturas de video disponibles.
  Future<Map<String, dynamic>?> probeInfo(String url) async {
    try {
      final result = await _channel.invokeMethod('probeInfo', {'url': url});
      if (result == null) return null;
      return Map<String, dynamic>.from(result as Map);
    } on PlatformException catch (e) {
      throw Exception('Error al analizar el video: ${e.message}');
    }
  }

  /// Corre el extractor custom para un dominio (ej: pimpbunny.com), igual
  /// que CUSTOM_EXTRACTORS[domain](current_url) en la app original.
  Future<Map<String, String>?> runCustomExtractor(
    String domain,
    String pageUrl,
  ) async {
    try {
      final result = await _channel.invokeMethod('customExtract', {
        'domain': domain,
        'url': pageUrl,
      });
      if (result == null) return null;
      return Map<String, String>.from(result as Map);
    } on PlatformException {
      return null;
    }
  }

  /// Inicia la descarga real con yt-dlp (bestvideo+bestaudio o el formato
  /// elegido). El progreso llega por progressStream (id -> {percent, speed}).
  Future<void> startDownload({
    required String downloadId,
    required String url,
    required String saveDir,
    required String title,
    required String formatChosen,
  }) async {
    await _channel.invokeMethod('startDownload', {
      'id': downloadId,
      'url': url,
      'saveDir': saveDir,
      'title': title,
      'format': formatChosen,
    });
  }

  Future<void> pauseDownload(String downloadId) async {
    await _channel.invokeMethod('pauseDownload', {'id': downloadId});
  }

  Future<void> resumeDownload(String downloadId) async {
    await _channel.invokeMethod('resumeDownload', {'id': downloadId});
  }

  Future<void> cancelDownload(String downloadId) async {
    await _channel.invokeMethod('cancelDownload', {'id': downloadId});
  }
}
