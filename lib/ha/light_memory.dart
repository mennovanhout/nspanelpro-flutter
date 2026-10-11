import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Last confirmed light attributes, separate from the authoritative HA state.
/// One bounded, versioned record per HA origin. No commands or capabilities.
class LightMemory {
  static const limit = 128;
  final Map<String, Map<String, dynamic>> _lights = {};
  Future<void> Function(String)? _save;
  Future<void> _writes = Future.value();
  Timer? _timer;
  bool _dirty = false;

  static Map<String, dynamic> valid(Map attributes) {
    final result = <String, dynamic>{};
    bool number(dynamic v, double min, double max) =>
        v is num && v.isFinite && v >= min && v <= max;
    final brightness = attributes['brightness'];
    if (number(brightness, 1, 255)) result['brightness'] = brightness;
    final mode = attributes['color_mode'];
    if (const {
      'brightness',
      'color_temp',
      'hs',
      'rgb',
      'rgbw',
      'rgbww',
      'xy',
      'white',
    }.contains(mode)) {
      result['color_mode'] = mode;
    }
    final hs = attributes['hs_color'], rgb = attributes['rgb_color'];
    if (hs is List &&
        hs.length == 2 &&
        number(hs[0], 0, 360) &&
        number(hs[1], 0, 100)) {
      result['hs_color'] = List<num>.from(hs);
    } else if (rgb is List &&
        rgb.length >= 3 &&
        rgb.take(3).every((v) => number(v, 0, 255))) {
      result['rgb_color'] = rgb.take(3).toList();
    }
    final kelvin = attributes['color_temp_kelvin'],
        mired = attributes['color_temp'];
    if (number(kelvin, 1, 1000000)) {
      result['color_temp_kelvin'] = kelvin;
    } else if (number(mired, 1, 1000000)) {
      result['color_temp_kelvin'] = 1000000 / (mired as num);
    }
    final effect = attributes['effect'];
    if (effect is String && effect.isNotEmpty && effect.length <= 256) {
      result['effect'] = effect;
    }
    return result;
  }

  static Map<String, dynamic> _merge(
    Map<String, dynamic> old,
    Map<String, dynamic> fresh,
  ) {
    final merged = {...old};
    // A live RGB value must win over an older HS value, and vice versa.
    if (fresh.containsKey('hs_color') || fresh.containsKey('rgb_color')) {
      merged.remove('hs_color');
      merged.remove('rgb_color');
    }
    return merged..addAll(fresh);
  }

  Future<void> load(String url) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'light_last_values_v1:${Uri.parse(url).origin}';
      final raw = prefs.getString(key);
      if (raw != null) restore(raw);
      _save = (value) async {
        if (!await prefs.setString(key, value)) {
          throw StateError('Light memory not saved');
        }
      };
    } catch (_) {
      // Storage unavailable: remembering within this session still works.
    }
  }

  void restore(String raw) {
    try {
      final data = jsonDecode(raw);
      if (data is! Map || data['version'] != 1 || data['lights'] is! Map) {
        return;
      }
      for (final entry in (data['lights'] as Map).entries) {
        if (entry.key is! String ||
            !(entry.key as String).startsWith('light.') ||
            entry.value is! Map) {
          continue;
        }
        final values = valid(entry.value as Map);
        if (values.isNotEmpty) {
          _lights.putIfAbsent(entry.key as String, () => values);
        }
      }
      _trim();
    } catch (_) {
      /* Malformed cache is never fatal. */
    }
  }

  String encode() => jsonEncode({'version': 1, 'lights': _lights});

  void _trim() {
    while (_lights.length > limit) {
      _lights.remove(_lights.keys.first);
    }
  }

  void observe(String id, String? state, Map? attributes) {
    if (!id.startsWith('light.')) return;
    if (state == null) {
      if (_lights.remove(id) != null) _changed();
      return;
    }
    if (state == 'off') {
      unawaited(flush());
      return;
    }
    if (state != 'on' || attributes == null) return;
    final fresh = valid(attributes);
    if (fresh.isEmpty) return;
    final next = valid(_merge(_lights[id] ?? {}, fresh));
    if (jsonEncode(next) == jsonEncode(_lights[id])) return;
    _lights.remove(id);
    _lights[id] = next;
    _trim();
    _changed();
  }

  void _changed() {
    _dirty = true;
    // At most one write per two seconds, even during continuous effect updates.
    if (_save != null) {
      _timer ??= Timer(const Duration(seconds: 2), () {
        unawaited(flush());
      });
    }
  }

  Map<String, dynamic> resolve(
    String id,
    String? state,
    Map<String, dynamic> attributes,
  ) {
    if (state != 'off') return attributes;
    final values = _merge(_lights[id] ?? {}, valid(attributes));
    final result = {...attributes};
    // Do not let stale/null representations override the selected live one.
    if (values.containsKey('hs_color') || values.containsKey('rgb_color')) {
      result.remove('hs_color');
      result.remove('rgb_color');
    }
    return result..addAll(values);
  }

  bool hasLastValues(
    String id,
    String? state,
    Map<String, dynamic> attributes,
  ) =>
      state == 'off' &&
      valid(resolve(id, state, attributes)).keys
          .any((key) => key != 'color_mode');

  Future<void> flush() {
    _timer?.cancel();
    _timer = null;
    if (!_dirty || _save == null) return _writes;
    _dirty = false;
    final raw = encode(), save = _save!;
    _writes = _writes.then((_) => save(raw)).catchError((Object _) {
      _dirty = true;
    });
    return _writes;
  }

  void dispose() {
    _timer?.cancel();
    unawaited(flush());
  }
}
