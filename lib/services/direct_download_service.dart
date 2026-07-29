import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import '../models/download_item.dart';

typedef ProgressCallback = void Function(int percent, String speed);
typedef FinishedCallback = void Function(bool success, String message);

/// Port directo de DownloadWorker._download_direct (descarga por HTTP con
/// requests.get(stream=True) -> acá usamos Dio con responseType stream).
/// Soporta pausar/reanudar (igual que el original: usa header Range si el
/// archivo ya existe parcialmente) y cancelar (borra el archivo incompleto).
class DirectDownloadService {
  final Dio _dio = Dio();

  bool _isPaused = false;
  bool _isCancelled = false;
  CancelToken _cancelToken = CancelToken();

  bool get isPaused => _isPaused;

  void pause() => _isPaused = true;

  void resume() => _isPaused = false;

  void cancel() {
    _isCancelled = true;
    _cancelToken.cancel('Cancelado por el usuario');
  }

  Future<String> _resolveSaveDir() async {
    // Equivalente a os.path.join(os.path.expanduser("~"), "Downloads")
    final dir = await getExternalStorageDirectory();
    final downloadsDir = Directory('${dir!.path}/Download');
    if (!await downloadsDir.exists()) {
      await downloadsDir.create(recursive: true);
    }
    return downloadsDir.path;
  }

  String _sanitizeTitle(String title) {
    // Port de re.sub(r'[\\/*?:"<>|]', "_", self.custom_title)
    var clean = title.replaceAll(RegExp(r'[\\/*?:"<>|]'), '_');
    if (!clean.toLowerCase().endsWith('.mp4')) clean += '.mp4';
    return clean;
  }

  Future<void> download({
    required String url,
    required String title,
    Map<String, String>? headers,
    required ProgressCallback onProgress,
    required FinishedCallback onFinished,
  }) async {
    _isPaused = false;
    _isCancelled = false;
    _cancelToken = CancelToken();

    try {
      final saveDir = await _resolveSaveDir();
      final fileName = _sanitizeTitle(title);
      final filePath = '$saveDir/$fileName';
      final file = File(filePath);

      int downloaded = 0;
      if (await file.exists()) {
        downloaded = await file.length();
      }

      final reqHeaders = Map<String, String>.from(headers ?? {});
      if (downloaded > 0) {
        reqHeaders['Range'] = 'bytes=$downloaded-';
      }

      final sink = await file.open(
        mode: downloaded > 0 ? FileMode.append : FileMode.write,
      );

      final response = await _dio.get<ResponseBody>(
        url,
        options: Options(
          headers: reqHeaders,
          responseType: ResponseType.stream,
        ),
        cancelToken: _cancelToken,
      );

      final contentLength = response.data!.contentLength;
      final total = contentLength > 0 ? contentLength + downloaded : 0;

      int lastDownloaded = downloaded;
      var lastTime = DateTime.now();

      await for (final chunk in response.data!.stream) {
        if (_isCancelled) break;

        while (_isPaused) {
          if (_isCancelled) break;
          await Future.delayed(const Duration(milliseconds: 500));
        }
        if (_isCancelled) break;

        sink.writeFromSync(chunk);
        downloaded += chunk.length;

        final now = DateTime.now();
        final elapsed = now.difference(lastTime).inMilliseconds / 1000.0;
        if (elapsed >= 0.5) {
          final bytesDiff = downloaded - lastDownloaded;
          final speedBps = elapsed > 0 ? bytesDiff / elapsed : 0;
          onProgress(
            total > 0 ? ((downloaded / total) * 100).floor() : 0,
            _formatSpeed(speedBps.toDouble()),
          );
          lastTime = now;
          lastDownloaded = downloaded;
        }
      }

      await sink.close();

      if (_isCancelled) {
        if (await file.exists()) await file.delete();
        onFinished(false, 'Descarga cancelada por el usuario');
        return;
      }

      onFinished(true, 'Descarga completada');
    } catch (e) {
      if (_isCancelled) {
        onFinished(false, 'Descarga cancelada por el usuario');
      } else {
        onFinished(false, e.toString());
      }
    }
  }

  String _formatSpeed(double bytesPerSec) {
    if (bytesPerSec <= 0) return '0 KB/s';
    if (bytesPerSec >= 1024 * 1024) {
      return '${(bytesPerSec / (1024 * 1024)).toStringAsFixed(2)} MB/s';
    }
    return '${(bytesPerSec / 1024).toStringAsFixed(1)} KB/s';
  }
}
