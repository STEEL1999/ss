import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../models/download_item.dart';
import '../services/adblock_service.dart';
import '../services/direct_download_service.dart';
import '../services/ytdlp_service.dart';
import '../widgets/download_panel.dart';

class BrowserScreen extends StatefulWidget {
  const BrowserScreen({super.key});

  @override
  State<BrowserScreen> createState() => _BrowserScreenState();
}

class _BrowserScreenState extends State<BrowserScreen> {
  InAppWebViewController? _webController;
  final TextEditingController _urlController =
      TextEditingController(text: 'https://www.google.com');

  final AdblockService _adblock = AdblockService();
  final YtdlpService _ytdlp = YtdlpService();

  String _currentUrl = 'https://www.google.com';
  bool _showDownloadPanel = false;
  bool _isLoading = false;

  final Map<String, DownloadItem> _downloads = {};
  final Map<String, DirectDownloadService> _directServices = {};
  StreamSubscription? _ytdlpSub;

  @override
  void initState() {
    super.initState();
    _ytdlpSub = _ytdlp.progressStream.listen(_onYtdlpEvent);
  }

  @override
  void dispose() {
    _ytdlpSub?.cancel();
    super.dispose();
  }

  void _onYtdlpEvent(Map<String, dynamic> event) {
    final id = event['id'] as String?;
    if (id == null || !_downloads.containsKey(id)) return;

    setState(() {
      final item = _downloads[id]!;
      if (event['type'] == 'progress') {
        item.progress = (event['percent'] as num).toInt();
        item.speed = event['speed'] as String;
      } else if (event['type'] == 'finished') {
        final success = event['success'] as bool;
        item.status = success ? DownloadStatus.completed : DownloadStatus.error;
        if (success) item.progress = 100;
        item.errorMessage = event['message'] as String?;
      }
    });
  }

  // --------------------------------------------------------------------
  // Navegación (equivalente a navigate_to_url)
  // --------------------------------------------------------------------
  void _navigateToUrl() {
    var text = _urlController.text.trim();
    if (!text.startsWith('http://') && !text.startsWith('https://')) {
      if (text.contains('.') && !text.contains(' ')) {
        text = 'https://$text';
      } else {
        text = 'https://www.google.com/search?q=${Uri.encodeComponent(text)}';
      }
    }
    _webController?.loadUrl(urlRequest: URLRequest(url: WebUri(text)));
  }

  // --------------------------------------------------------------------
  // Descarga del video actual (equivalente a download_current_video)
  // --------------------------------------------------------------------
  Future<void> _downloadCurrentVideo() async {
    if (_currentUrl.isEmpty || _currentUrl == 'about:blank') {
      _showSnack('No hay ninguna página válida abierta.');
      return;
    }

    final domain = Uri.parse(_currentUrl).host.toLowerCase();

    // 1) Extractor custom (ej: pimpbunny.com)
    const customDomains = {'pimpbunny.com', 'www.pimpbunny.com'};
    if (customDomains.contains(domain)) {
      final result = await _ytdlp.runCustomExtractor(domain, _currentUrl);
      if (result != null && result.isNotEmpty) {
        final keys = result.keys.toList()
          ..sort((a, b) {
            final na = RegExp(r'\d+').firstMatch(a)?.group(0);
            final nb = RegExp(r'\d+').firstMatch(b)?.group(0);
            return (int.tryParse(nb ?? '0') ?? 0)
                .compareTo(int.tryParse(na ?? '0') ?? 0);
          });
        final choice = await _promptChoice('Resolución', keys);
        if (choice != null) {
          final title = await _webController?.getTitle() ?? 'Video_Descargado';
          _startDirectDownload(result[choice]!, title);
        }
        return;
      }
    }

    // 2) yt-dlp (soporta YouTube y cientos de sitios)
    try {
      final info = await _ytdlp.probeInfo(_currentUrl);
      if (info != null) {
        final title = info['title'] as String? ??
            await _webController?.getTitle() ??
            'Video';
        final heights = (info['heights'] as List?) ?? [];
        final formatChosen = await _promptResolution(heights);
        if (formatChosen != null) {
          _startYtdlpDownload(_currentUrl, title, formatChosen);
        }
        return;
      }
    } catch (_) {
      // Igual que el except: pass del original -> seguimos al fallback JS
    }

    // 3) Scrapeo de tags <video>/<source> vía JS
    await _scrapeVideoTagsAndDownload();
  }

  Future<void> _scrapeVideoTagsAndDownload() async {
    const jsCode = '''
      (function() {
        let urls = [];
        document.querySelectorAll('video').forEach(v => { if (v.src) urls.push(v.src); });
        document.querySelectorAll('source').forEach(s => { if (s.src) urls.push(s.src); });
        return JSON.stringify(urls);
      })();
    ''';
    final result = await _webController?.evaluateJavascript(source: jsCode);
    List<dynamic> urls = [];
    if (result is String && result.isNotEmpty && result != 'null') {
      try {
        urls = List<dynamic>.from(jsonDecode(result) as List);
      } catch (_) {
        urls = [];
      }
    } else if (result is List) {
      urls = result;
    }

    if (urls.isEmpty) {
      _showSnack('No se encontró ningún enlace de video descargable.');
      return;
    }

    final directUrl = Uri.parse(_currentUrl).resolve(urls.first.toString());
    final title = await _webController?.getTitle() ?? 'video_descargado';
    _startDirectDownload(directUrl.toString(), title);
  }

  Future<String?> _promptResolution(List<dynamic> heights) async {
    if (heights.isEmpty) return 'best';
    final options = ['Mejor calidad', ...heights.map((h) => '${h}p')];
    final choice = await _promptChoice('Calidad', options);
    if (choice == null) return null;
    if (choice == 'Mejor calidad') return 'bestvideo+bestaudio/best';
    final height = int.parse(choice.replaceAll('p', ''));
    return 'bestvideo[height<=$height]+bestaudio/best[height<=$height]';
  }

  Future<String?> _promptChoice(String title, List<String> options) {
    return showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(title),
        children: options
            .map((o) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(ctx, o),
                  child: Text(o),
                ))
            .toList(),
      ),
    );
  }

  // --------------------------------------------------------------------
  // Manejo de la cola de descargas (equivalente a add_download_to_panel +
  // start_async_download)
  // --------------------------------------------------------------------
  Future<void> _startDirectDownload(String url, String title) async {
    final id = const Uuid().v4();
    final item = DownloadItem(id: id, name: title);
    final service = DirectDownloadService();
    _directServices[id] = service;

    setState(() {
      _downloads[id] = item;
      _showDownloadPanel = true;
    });

    service.download(
      url: url,
      title: title,
      onProgress: (percent, speed) {
        if (!mounted) return;
        setState(() {
          item.progress = percent;
          item.speed = speed;
        });
      },
      onFinished: (success, message) {
        if (!mounted) return;
        setState(() {
          item.status = success
              ? DownloadStatus.completed
              : (service.isPaused ? DownloadStatus.paused : DownloadStatus.error);
          if (message.contains('cancel')) item.status = DownloadStatus.cancelled;
          item.errorMessage = message;
        });
      },
    );
  }

  Future<void> _startYtdlpDownload(
    String url,
    String title,
    String formatChosen,
  ) async {
    final id = const Uuid().v4();
    final item = DownloadItem(id: id, name: title);

    setState(() {
      _downloads[id] = item;
      _showDownloadPanel = true;
    });

    final dir = await getExternalStorageDirectory();
    await _ytdlp.startDownload(
      downloadId: id,
      url: url,
      saveDir: '${dir!.path}/Download',
      title: title,
      formatChosen: formatChosen,
    );
  }

  void _togglePauseResume(String id) {
    final item = _downloads[id];
    if (item == null) return;

    if (_directServices.containsKey(id)) {
      final service = _directServices[id]!;
      setState(() {
        if (service.isPaused) {
          service.resume();
          item.status = DownloadStatus.downloading;
        } else {
          service.pause();
          item.status = DownloadStatus.paused;
          item.speed = '0 KB/s';
        }
      });
    } else {
      // Descarga por yt-dlp
      setState(() {
        if (item.status == DownloadStatus.paused) {
          _ytdlp.resumeDownload(id);
          item.status = DownloadStatus.downloading;
        } else {
          _ytdlp.pauseDownload(id);
          item.status = DownloadStatus.paused;
          item.speed = '0 KB/s';
        }
      });
    }
  }

  void _cancelDownload(String id) {
    if (_directServices.containsKey(id)) {
      _directServices[id]!.cancel();
    } else {
      _ytdlp.cancelDownload(id);
    }
    setState(() {
      _downloads[id]?.status = DownloadStatus.cancelled;
    });
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // --------------------------------------------------------------------
  // UI
  // --------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildNavBar(),
            if (_isLoading) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    flex: _showDownloadPanel ? 3 : 1,
                    child: InAppWebView(
                      initialUrlRequest: URLRequest(
                        url: WebUri(_urlController.text),
                      ),
                      initialSettings: InAppWebViewSettings(
                        useShouldInterceptRequest: true,
                        javaScriptEnabled: true,
                        mediaPlaybackRequiresUserGesture: false,
                      ),
                      onWebViewCreated: (controller) {
                        _webController = controller;
                      },
                      onLoadStart: (controller, url) {
                        setState(() => _isLoading = true);
                      },
                      onLoadStop: (controller, url) {
                        setState(() {
                          _isLoading = false;
                          _currentUrl = url.toString();
                          _urlController.text = _currentUrl;
                        });
                      },
                      // Equivalente a AdBlockInterceptor.interceptRequest
                      shouldInterceptRequest: (controller, request) async {
                        final uri = request.url;
                        if (_adblock.shouldBlockRequest(uri)) {
                          return WebResourceResponse(
                            contentType: '',
                            contentEncoding: '',
                            data: Uint8List(0),
                          );
                        }
                        return null; // dejar pasar la request normalmente
                      },
                    ),
                  ),
                  if (_showDownloadPanel)
                    Expanded(
                      flex: 1,
                      child: DownloadPanel(
                        downloads: _downloads.values.toList(),
                        onPauseResume: _togglePauseResume,
                        onCancel: _cancelDownload,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => _webController?.goBack(),
          ),
          IconButton(
            icon: const Icon(Icons.arrow_forward),
            onPressed: () => _webController?.goForward(),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _webController?.reload(),
          ),
          Expanded(
            child: TextField(
              controller: _urlController,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 8),
              ),
              onSubmitted: (_) => _navigateToUrl(),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.arrow_circle_right),
            onPressed: _navigateToUrl,
          ),
          IconButton(
            tooltip: 'Bloquear anuncios',
            icon: Icon(
              Icons.shield,
              color: _adblock.enabled ? Colors.green : Colors.grey,
            ),
            onPressed: () {
              setState(() => _adblock.enabled = !_adblock.enabled);
            },
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF27AE60),
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.download),
            label: const Text('Descargar'),
            onPressed: _downloadCurrentVideo,
          ),
          IconButton(
            tooltip: 'Descargas',
            icon: const Icon(Icons.list_alt),
            onPressed: () {
              setState(() => _showDownloadPanel = !_showDownloadPanel);
            },
          ),
        ],
      ),
    );
  }
}
