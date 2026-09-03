import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../config/settings.dart';
import '../ha/connection.dart';

/// The speaker. Plays a URL, or speaks text by asking Home Assistant's own
/// TTS engine for the audio - so the voice is whatever you configured in HA,
/// and nothing is synthesised on a 2018 SoC.
class Announcer {
  Announcer({required this.settings, required this.conn});

  final Settings settings;
  final HaConnection conn;
  final _player = AudioPlayer();
  String? _engine;

  /// Plays whatever `ref` names:
  ///   sound:doorbell          a built-in chime (doorbell, chime, alert)
  ///   media-source://...      a file from HA's media browser, resolved via HA
  ///   /local/x.mp3            a path on HA
  ///   https://...             any URL
  Future<void> play(String ref) async {
    try {
      if (ref.startsWith('sound:')) {
        final name = ref.substring(6).trim().toLowerCase();
        await _player.setAsset('assets/sounds/$name.wav');
      } else {
        var url = ref;
        if (ref.startsWith('media-source://')) {
          final r = await conn.send({'type': 'media_source/resolve_media', 'media_content_id': ref});
          url = ((r as Map)['url'] ?? '').toString();
          if (url.isEmpty) throw StateError('media source did not resolve');
        }
        await _player.setUrl(settings.resolve(url));
      }
      await _player.play();
    } catch (e) {
      debugPrint('play failed for $ref: $e');
    }
  }

  Future<void> say(String text) async {
    final url = await _ttsUrl(text);
    if (url != null) await play(url);
  }

  Future<void> stop() => _player.stop();

  Future<void> dispose() => _player.dispose();

  /// The engine from settings, else the first one HA lists. Cached after.
  Future<String?> _engineId() async {
    if (settings.ttsEngine.isNotEmpty) return settings.ttsEngine;
    if (_engine != null) return _engine;
    try {
      final r = await conn.send({'type': 'tts/engine/list'});
      final list = ((r as Map)['providers'] as List?) ?? const [];
      for (final p in list.whereType<Map>()) {
        final id = p['engine_id']?.toString();
        if (id != null && id.isNotEmpty) return _engine = id;
      }
    } catch (e) {
      debugPrint('tts engine list failed: $e');
    }
    return null;
  }

  Future<String?> _ttsUrl(String text) async {
    final engine = await _engineId();
    if (engine == null) {
      debugPrint('no TTS engine: set tts_engine in setup.json');
      return null;
    }
    final client = HttpClient();
    try {
      final req = await client.postUrl(settings.base.replace(path: '/api/tts_get_url'));
      req.headers.set('Authorization', 'Bearer ${settings.token}');
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode({'message': text, 'engine_id': engine}));
      final res = await req.close();
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode != 200) {
        debugPrint('tts_get_url ${res.statusCode}: $body');
        return null;
      }
      return (jsonDecode(body) as Map)['url']?.toString();
    } catch (e) {
      debugPrint('tts failed: $e');
      return null;
    } finally {
      client.close();
    }
  }
}
