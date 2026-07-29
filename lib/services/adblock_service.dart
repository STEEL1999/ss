/// Port directo de HARDCODED_AD_DOMAINS + AdBlockInterceptor._is_blocked
/// de la app PyQt original.
class AdblockService {
  bool enabled = false; // Desactivado por defecto, igual que el original
  int blockedCount = 0;

  static const Set<String> blockedDomains = {
    'doubleclick.net',
    'googlesyndication.com',
    'googleadservices.com',
    'google-analytics.com',
    'adservice.google.com',
    'adnxs.com',
    'adsrvr.org',
    'taboola.com',
    'outbrain.com',
    'criteo.com',
    'scorecardresearch.com',
    'moatads.com',
    'advertising.com',
    'popads.net',
    'propellerads.com',
    'adcolony.com',
    'exoclick.com',
    'juicyads.com',
    'trafficjunky.net',
    'adform.net',
    'pubmatic.com',
    'rubiconproject.com',
    'openx.net',
    'media.net',
    'revcontent.com',
  };

  /// Misma lógica que _is_blocked: revisa el host y todos sus sufijos
  /// (ej: sub.doubleclick.net -> doubleclick.net coincide).
  bool isBlocked(String? host) {
    if (host == null || host.isEmpty) return false;
    final h = host.toLowerCase();
    final parts = h.split('.');
    for (var i = 0; i < parts.length - 1; i++) {
      final candidate = parts.sublist(i).join('.');
      if (blockedDomains.contains(candidate)) return true;
    }
    return false;
  }

  bool shouldBlockRequest(Uri uri) {
    if (!enabled) return false;
    final blocked = isBlocked(uri.host);
    if (blocked) blockedCount++;
    return blocked;
  }
}
