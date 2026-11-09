import 'package:flutter/material.dart';

import '../config/dashboard.dart';
import '../ha/states.dart';
import '../ui/theme.dart';
import '../util/color.dart';
import 'env.dart';
import 'light_capabilities.dart';

/// Shared light policy and commands for a light card and switch-tile details.
/// Echo and gestures belong to their widgets; capability checks live here.
class LightControls {
  const LightControls(this.c, this.env);
  final CardConfig c;
  final PanelEnv env;
  String get entity => c.str('entity') ?? '';
  HaState? get current => env.states.get(entity);
  LightCapabilities get capabilities => LightCapabilities(current);

  List<CardConfig> get presets => c['presets'] is List
      ? c.maps('presets')
      : !capabilities.brightness
      ? const []
      : const [
          {'name': 'Low', 'brightness_pct': 15},
          {'name': 'Mid', 'brightness_pct': 50},
          {'name': 'Full', 'brightness_pct': 100},
        ];

  double entityValue(HaState? s) {
    if (s == null || !s.isOn) return 0;
    final b = s.numAttr('brightness');
    return b == null ? 1 : (b / 255).clamp(0.0, 1.0);
  }

  /// The colour to paint the card in: the bulb's own when it has one and is
  /// on, otherwise the configured accent. An explicit accent always wins.
  Color accent(HaState? s) {
    final explicit = parseHex(c.str('accent'));
    if (explicit != null) return explicit;
    if (c.boolOr('follow_color', true) && s != null && s.isOn) {
      final rgb = s.attributes['rgb_color'];
      if (rgb is List && rgb.length >= 3 && rgb.every((x) => x is num)) {
        return readableTint(rgb.cast<num>());
      }
    }
    return Ns.amber;
  }

  Future<void> call(String service, [Map<String, dynamic>? data]) async {
    if (!capabilities.available) return;
    await env.conn.callService('light', service, {
      'entity_id': entity,
      ...?data,
    });
  }

  void commit(double v) {
    if (!capabilities.available || !capabilities.brightness) return;
    final pct = (v * 100).round();
    if (pct == 0) {
      call('turn_off');
    } else {
      call('turn_on', {'brightness_pct': pct});
    }
  }

  void applyPreset(CardConfig p) {
    if (!capabilities.allowsPreset(current, p)) return;
    if (p['scene'] != null) {
      env.conn.callService('scene', 'turn_on', {'entity_id': p['scene']});
      return;
    }
    final pct = (p['brightness_pct'] as num?)?.toInt();
    if (pct == 0) {
      call('turn_off');
      return;
    }
    final data = <String, dynamic>{};
    if (pct != null) data['brightness_pct'] = pct;
    for (final k in ['color_temp_kelvin', 'rgb_color', 'effect']) {
      if (p[k] != null) data[k] = p[k];
    }
    call('turn_on', data);
  }
}
