import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
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

  /// Provisioning without a keyboard.
  ///
  /// A wall panel has no comfortable way to type a 180-character token. So on
  /// every launch the app looks for `setup.json` in its own external files
  /// directory - writable with a plain `adb push`, no storage permission - and
  /// if it is there, takes `url`, `token` and `dashboard` from it, saves them,
  /// and deletes the file. The token is on the panel's flash for exactly as
  /// long as it takes to read it once.
  ///
  ///   adb push setup.json /sdcard/Android/data/nl.mennovanhout.nspanel/files/setup.json
  static Future<bool> consumeSetupFile() async {
    try {
      final dir = await getExternalStorageDirectory();
      if (dir == null) return false;
      final f = File('${dir.path}${Platform.pathSeparator}setup.json');
      if (!await f.exists()) return false;
      final j = jsonDecode(await f.readAsString());
      await f.delete();
      if (j is! Map) return false;
      final url = j['url']?.toString().trim() ?? '';
      final token = j['token']?.toString().trim() ?? '';
      if (url.isEmpty || token.isEmpty) return false;
      final s = Settings(url: url, token: token, dashboard: j['dashboard']?.toString().trim() ?? '');
      await s.save();
      return true;
    } catch (e) {
      debugPrint('setup.json: $e');
      return false;
    }
  }

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

  /// The dashboard's url_path, however it was typed. People paste what the
  /// address bar shows, and that is `/dining-area/0` - the view index on the
  /// end, a slash on the front, sometimes the whole URL. HA wants `dining-area`.
  String get dashboardPath => normaliseDashboard(dashboard);

  static String normaliseDashboard(String raw) {
    var s = raw.trim();
    if (s.contains('://')) {
      s = Uri.tryParse(s)?.path ?? s;
    }
    s = s.replaceAll(RegExp(r'^/+'), '');
    // drop a trailing view segment: "/0", "/kitchen", but not the dashboard itself
    final parts = s.split('/').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '';
    if (parts.first == 'lovelace') return ''; // the default dashboard's own URL
    return parts.first;
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

  /// entity_picture and friends are relative to HA. Plain concatenation, not
  /// Uri.replace(path:), which would encode the `?` in
  /// `/api/media_player_proxy/x?token=…` and 404 every album cover.
  String resolve(String path) {
    if (!path.startsWith('/')) return path;
    final b = base;
    return '${b.scheme}://${b.authority}$path';
  }
}
