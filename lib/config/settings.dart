import 'package:shared_preferences/shared_preferences.dart';

/// Where Home Assistant is and how to prove who we are. Stored on the panel
/// and nowhere else.
class Settings {
  Settings({required this.url, required this.token, this.dashboard = '', this.cachedConfig});

  String url;
  String token;

  /// Lovelace url_path of the dashboard to render; empty = the default one.
  String dashboard;

  /// The last dashboard config we fetched, so the panel has something to
  /// draw before HA answers - and something to draw when it does not.
  String? cachedConfig;

  static const _kUrl = 'url';
  static const _kToken = 'token';
  static const _kDash = 'dashboard';
  static const _kCache = 'cached_config';

  static Future<Settings?> load() async {
    final p = await SharedPreferences.getInstance();
    final url = p.getString(_kUrl);
    final token = p.getString(_kToken);
    if (url == null || url.isEmpty || token == null || token.isEmpty) return null;
    return Settings(
      url: url,
      token: token,
      dashboard: p.getString(_kDash) ?? '',
      cachedConfig: p.getString(_kCache),
    );
  }

  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString(_kUrl, url);
    await p.setString(_kToken, token);
    await p.setString(_kDash, dashboard);
  }

  Future<void> cacheConfig(String json) async {
    cachedConfig = json;
    final p = await SharedPreferences.getInstance();
    await p.setString(_kCache, json);
  }

  static Future<void> clear() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kUrl);
    await p.remove(_kToken);
    await p.remove(_kDash);
    await p.remove(_kCache);
  }

  Uri get base {
    var raw = url.trim();
    if (!raw.contains('://')) raw = 'http://$raw';
    return Uri.parse(raw);
  }

  Uri get wsUri {
    final b = base;
    return b.replace(scheme: b.scheme == 'https' ? 'wss' : 'ws', path: '/api/websocket');
  }

  /// entity_picture and friends are relative to HA.
  String resolve(String path) => path.startsWith('/') ? base.replace(path: path).toString() : path;
}
