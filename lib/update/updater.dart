import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'adb.dart';

/// A release on GitHub with an arm64 APK attached.
class UpdateInfo {
  const UpdateInfo(
      {required this.version, required this.url, required this.notes, required this.apkUrl, required this.size});
  final String version; // "0.3.0", the tag without its v
  final String url; // the release page
  final String notes;
  final String apkUrl;
  final int size;
}

/// Numeric, segment by segment: 0.10.0 is newer than 0.9.1. A leading v is
/// ignored, and so is anything after a dash or plus.
int compareVersions(String a, String b) {
  List<int> parts(String v) => v
      .replaceFirst(RegExp(r'^v'), '')
      .split(RegExp(r'[-+]'))
      .first
      .split('.')
      .map((s) => int.tryParse(s) ?? 0)
      .toList();
  final pa = parts(a), pb = parts(b);
  for (var i = 0; i < 3; i++) {
    final x = i < pa.length ? pa[i] : 0;
    final y = i < pb.length ? pb[i] : 0;
    if (x != y) return x.compareTo(y);
  }
  return 0;
}

/// Parses GitHub's releases/latest JSON. Null when there is no arm64 APK on it.
UpdateInfo? parseRelease(String json) {
  final j = jsonDecode(json);
  if (j is! Map) return null;
  final assets = (j['assets'] as List?) ?? const [];
  for (final a in assets) {
    if (a is! Map) continue;
    final name = (a['name'] ?? '').toString();
    if (name.contains('arm64') && name.endsWith('.apk')) {
      return UpdateInfo(
        version: (j['tag_name'] ?? '').toString().replaceFirst(RegExp(r'^v'), ''),
        url: (j['html_url'] ?? '').toString(),
        notes: (j['body'] ?? '').toString(),
        apkUrl: (a['browser_download_url'] ?? '').toString(),
        size: (a['size'] as num?)?.toInt() ?? 0,
      );
    }
  }
  return null;
}

typedef Fetch = Future<String> Function(Uri url);
typedef Download = Future<void> Function(Uri url, File to, void Function(int percent) onProgress);

/// Checks GitHub for a newer release and installs it through the panel's own
/// adb daemon. `pm install -r` kills this process; BootReceiver brings the
/// new one up on MY_PACKAGE_REPLACED, so from HA it looks like a reboot.
class Updater {
  Updater({
    required this.installed,
    required this.dir,
    this.repo = 'mennovanhout/nspanelpro-flutter',
    Fetch? fetch,
    Download? download,
    AdbShell? shell,
  })  : _fetch = fetch ?? _httpGet,
        _download = download ?? _httpDownload,
        _shell = shell ?? AdbShell();

  final String installed;
  final Directory dir;
  final String repo;
  final Fetch _fetch;
  final Download _download;
  final AdbShell _shell;

  /// The latest release, whether or not it is newer; null until checked.
  final latest = ValueNotifier<UpdateInfo?>(null);

  /// Download/install progress, 0-100 while busy, null when idle.
  final progress = ValueNotifier<int?>(null);

  /// The last thing that happened, for the setup screen and the log.
  final status = ValueNotifier<String>('');

  bool get updateAvailable {
    final l = latest.value;
    return l != null && compareVersions(l.version, installed) > 0;
  }

  Future<UpdateInfo?> check() async {
    try {
      final String body;
      try {
        body = await _fetch(Uri.parse('https://api.github.com/repos/$repo/releases/latest'));
      } on HttpException catch (e) {
        // GitHub answers 404 when the repo has no release at all
        if (e.message.contains('404')) {
          latest.value = null;
          status.value = 'No release yet';
          return null;
        }
        rethrow;
      }
      final info = parseRelease(body);
      latest.value = info;
      status.value = info == null
          ? 'No release with an APK yet'
          : updateAvailable
              ? 'Update ${info.version} available'
              : 'Up to date';
      return info;
    } catch (e) {
      status.value = 'Update check failed: $e';
      debugPrint('update: check failed: $e');
      return null;
    }
  }

  /// Downloads and installs. Returns only on failure (success ends the process).
  Future<bool> install([UpdateInfo? which]) async {
    final info = which ?? latest.value;
    if (info == null || progress.value != null) return false;
    final file = File('${dir.path}/update.apk');
    try {
      progress.value = 0;
      status.value = 'Downloading ${info.version}…';
      await _download(Uri.parse(info.apkUrl), file, (p) => progress.value = p);
      status.value = 'Installing ${info.version}…';
      final out = await _shell.run('pm install -r "${file.path}"');
      if (out.contains('Success')) {
        status.value = 'Installed ${info.version}, restarting';
        return true;
      }
      status.value = 'Install failed: ${out.trim()}';
      debugPrint('update: $out');
      return false;
    } catch (e) {
      status.value = 'Update failed: $e';
      debugPrint('update: failed: $e');
      return false;
    } finally {
      progress.value = null;
      if (await file.exists()) await file.delete();
    }
  }

  static Future<String> _httpGet(Uri url) async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(url);
      req.headers.set('Accept', 'application/vnd.github+json');
      req.headers.set('User-Agent', 'nspanel-app');
      final res = await req.close();
      if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}', uri: url);
      return await res.transform(utf8.decoder).join();
    } finally {
      client.close();
    }
  }

  static Future<void> _httpDownload(Uri url, File to, void Function(int) onProgress) async {
    final client = HttpClient();
    try {
      final req = await client.getUrl(url);
      req.headers.set('User-Agent', 'nspanel-app');
      final res = await req.close();
      if (res.statusCode != 200) throw HttpException('HTTP ${res.statusCode}', uri: url);
      final total = res.contentLength;
      var got = 0;
      final sink = to.openWrite();
      await for (final chunk in res) {
        sink.add(chunk);
        got += chunk.length;
        if (total > 0) onProgress((got * 100 ~/ total).clamp(0, 100));
      }
      await sink.close();
    } finally {
      client.close();
    }
  }
}
