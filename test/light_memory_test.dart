import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nspanel_app/ha/light_memory.dart';
import 'package:nspanel_app/ha/states.dart';
import 'package:nspanel_app/cards/light_color.dart';

const id = 'light.test';
const values = <String, dynamic>{
  'brightness': 128,
  'color_mode': 'hs',
  'hs_color': [180, 40],
  'color_temp_kelvin': 3000,
  'effect': 'Rainbow',
};
const caps = <String, dynamic>{
  'supported_color_modes': ['rgb', 'color_temp'],
  'min_color_temp_kelvin': 2000,
  'max_color_temp_kelvin': 6500,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('confirmed on values survive off/null/zero and unavailable without changing HA', () {
    final states = HaStates();
    states.update(
      id,
      const HaState(
        entityId: id,
        state: 'on',
        attributes: {...caps, ...values},
      ),
    );
    const off = HaState(
      entityId: id,
      state: 'off',
      attributes: {
        ...caps,
        'brightness': 0,
        'hs_color': null,
        'color_temp_kelvin': null,
        'color_mode': null,
        'effect': null,
      },
    );
    states.update(id, off);
    final a = states.lightMemory.resolve(id, off.state, off.attributes);
    expect(a['brightness'], 128);
    expect(a['hs_color'], [180, 40]);
    expect(a['color_mode'], 'hs');
    expect(a['effect'], 'Rainbow');
    expect(states.get(id), same(off));
    expect(off.attributes['brightness'], 0);
    expect(LightColor(off).value(LightChannel.brightness), 0);
    expect(
      LightColor(
        off,
        attributes: a,
        lastValues: true,
      ).value(LightChannel.brightness),
      128 / 255,
    );
    states.lightMemory.observe(id, 'unavailable', {'brightness': 42});
    expect(states.lightMemory.resolve(id, 'off', {})['brightness'], 128);
    expect(states.lightMemory.resolve(id, 'unavailable', {}), isEmpty);
  });

  test(
    'live valid RGB and temperature win over cached alternate representations',
    () {
      final m = LightMemory()..observe(id, 'on', values);
      final a = m.resolve(id, 'off', {
        'brightness': 200,
        'rgb_color': [255, 0, 0],
        'color_temp': 250,
        'color_mode': 'color_temp',
      });
      expect(a['brightness'], 200);
      expect(a['hs_color'], isNull);
      expect(a['rgb_color'], [255, 0, 0]);
      expect(a['color_temp_kelvin'], 4000);
      expect(a['color_mode'], 'color_temp');
      m.observe(id, 'on', {'brightness': 0});
      expect(m.resolve(id, 'off', {})['brightness'], 128);
    },
  );

  test('cache never restores capabilities, availability, temperature range or effects list', () {
    final m = LightMemory()
      ..observe(id, 'on', {
        ...values,
        ...caps,
        'effect_list': ['Rainbow'],
        'supported_features': 4,
      });
    const current = HaState(
      entityId: id,
      state: 'off',
      attributes: {
        'supported_color_modes': ['onoff'],
      },
    );
    final p = LightColor(
      current,
      attributes: m.resolve(id, 'off', current.attributes),
      lastValues: true,
    );
    expect(p.caps.brightness, isFalse);
    expect(p.color, isFalse);
    expect(p.white, isFalse);
    expect(p.range, isNull);
    expect(p.effects, isEmpty);
    expect(m.encode(), isNot(contains('supported_color_modes')));
  });

  test(
    'restart restores only validated fields; removed entity forgets history',
    () {
      final a = LightMemory()..observe(id, 'on', values);
      final b = LightMemory()..restore(a.encode());
      expect(b.resolve(id, 'off', {})['effect'], 'Rainbow');
      b.observe(id, null, null);
      expect(b.resolve(id, 'off', {}), isEmpty);
      b.restore('{broken');
      b.restore('{"version":2,"lights":{}}');
      expect(b.resolve(id, 'off', {}), isEmpty);
      b.restore(
        jsonEncode({
          'version': 1,
          'lights': {
            id: {
              'brightness': -1,
              'hs_color': ['bad', 40],
              'color_mode': 'unknown',
              'effect': 12,
              'color_temp_kelvin': null,
            },
            'switch.fake': values,
          },
        }),
      );
      expect(b.hasLastValues(id, 'off', {}), isFalse);
    },
  );

  test('invalid/nonfinite attributes cannot poison subsequent persistence', () {
    final m = LightMemory()
      ..observe(id, 'on', values)
      ..observe(id, 'on', {
        'brightness': double.nan,
        'hs_color': [double.infinity, 20],
        'color_temp_kelvin': -5,
      });
    final b = LightMemory()..restore(m.encode());
    expect(b.resolve(id, 'off', {})['brightness'], 128);
    expect(b.resolve(id, 'off', {})['hs_color'], [180, 40]);
  });

  test('bounded memory evicts old lights and isolates entity IDs', () {
    final m = LightMemory();
    for (var i = 0; i < 140; i++) {
      m.observe('light.$i', 'on', {'brightness': i + 1});
    }
    expect((jsonDecode(m.encode())['lights'] as Map).length, 128);
    expect(m.resolve('light.0', 'off', {}), isEmpty);
    expect(m.resolve('light.139', 'off', {})['brightness'], 140);
  });

  test(
    'batched preferences survive restart and stay scoped to HA origin',
    () async {
      final m = LightMemory();
      await m.load('http://one:8123');
      m.observe(id, 'on', values);
      m.observe(id, 'on', {'brightness': 180});
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('light_last_values_v1:http://one:8123'), isNull);
      m.observe(id, 'off', {});
      await m.flush();
      final restarted = LightMemory();
      await restarted.load('http://one:8123/path');
      expect(restarted.resolve(id, 'off', {})['brightness'], 180);
      final other = LightMemory();
      await other.load('http://two:8123');
      expect(other.resolve(id, 'off', {}), isEmpty);
      m.dispose();
      restarted.dispose();
      other.dispose();
    },
  );
}
