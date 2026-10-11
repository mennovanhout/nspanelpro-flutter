import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nspanel_app/cards/light_capabilities.dart';
import 'package:nspanel_app/ha/states.dart';

void main() {
  final cases = jsonDecode(
    File('test/fixtures/light-capabilities.json').readAsStringSync(),
  ) as List;
  for (final c in cases) {
    test(c['name'] as String, () {
      final s = HaState.fromJson((c['state'] as Map).cast<String, dynamic>());
      final caps = LightCapabilities(s);
      expect(caps.available, c['available']);
      expect(caps.brightness, c['brightness']);
      expect(caps.color, c['color']);
      expect(caps.temperature, c['temperature']);
    });
  }
  test('presets preserve their meaning and unavailable lights cannot act', () {
    final relay = HaState(
      entityId: 'light.test',
      state: 'on',
      attributes: {
        'supported_color_modes': ['onoff'],
      },
    );
    final caps = LightCapabilities(relay);
    expect(caps.allowsPreset(relay, {'brightness_pct': 50}), false);
    expect(
      caps.allowsPreset(relay, {
        'rgb_color': [255, 0, 0],
      }),
      false,
    );
    expect(caps.allowsPreset(relay, {'color_temp_kelvin': 2700}), false);
    expect(caps.allowsPreset(relay, {'brightness_pct': 0}), true);
    expect(caps.allowsPreset(relay, {'scene': 'scene.evening'}), true);
    expect(caps.allowsPreset(relay, {'effect': 'Rainbow'}), false);
    final effect = HaState(
      entityId: 'light.test',
      state: 'on',
      attributes: {
        'supported_color_modes': ['rgb'],
        'supported_features': 4,
        'effect_list': ['Rainbow'],
      },
    );
    expect(
      LightCapabilities(effect).allowsPreset(effect, {'effect': 'Rainbow'}),
      true,
    );
    expect(
      LightCapabilities(effect).allowsPreset(effect, {'effect': 'Missing'}),
      false,
    );
    expect(
      LightCapabilities(null).allowsPreset(null, {'scene': 'scene.evening'}),
      false,
    );
  });
}
