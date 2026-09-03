import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'client.dart';

/// The panel as a Home Assistant device, over MQTT discovery.
///
/// One `device` block ties every entity to the same panel; each entity is a
/// retained config under `homeassistant/{component}/{id}/{object}/config`,
/// states are retained on `nspanel/{id}/{object}`, and commands arrive on
/// `nspanel/{id}/{object}/set`. Availability is a will, so HA marks the panel
/// unavailable the moment the socket drops.
///
/// Sensor traffic is rate-limited here, not at the source: the proximity
/// sensor runs at 10 Hz and nobody wants that on a broker.
/// What counts as "audio to play" rather than "words to speak".
bool isPlayable(String text) =>
    text.startsWith('http://') ||
    text.startsWith('https://') ||
    text.startsWith('/') ||
    text.startsWith('media-source://') ||
    text.startsWith('sound:');

class PanelBridge {
  PanelBridge({
    required this.mqtt,
    required this.deviceId,
    required this.name,
    required this.version,
    this.presenceDelta = 12,
    this.onBrightness,
    this.onVolume,
    this.onScreensaver,
    this.onPage,
    this.onSay,
    this.onPlay,
    this.onStop,
    this.onWake,
  });

  final MqttClient mqtt;
  final String deviceId;
  final String name;
  final String version;
  final double presenceDelta;

  final void Function(int)? onBrightness;
  final void Function(int)? onVolume;
  final void Function(bool)? onScreensaver;
  final void Function(int)? onPage;
  final void Function(String)? onSay;
  final void Function(String)? onPlay;
  final VoidCallback? onStop;
  final VoidCallback? onWake;

  String get base => 'nspanel/$deviceId';
  String get availabilityTopic => '$base/availability';

  Map<String, dynamic> get _device => {
        'identifiers': ['nspanel_$deviceId'],
        'name': name,
        'manufacturer': 'Sonoff',
        'model': 'NSPanel Pro 86',
        'sw_version': version,
      };

  /// Every entity, as HA discovery wants it. Public so a test can read it.
  Map<String, Map<String, dynamic>> discoveryConfigs() {
    Map<String, dynamic> e(String object, Map<String, dynamic> extra, {bool command = false}) => {
          'name': extra.remove('name'),
          'unique_id': 'nspanel_${deviceId}_$object',
          'state_topic': '$base/$object',
          if (command) 'command_topic': '$base/$object/set',
          'availability_topic': availabilityTopic,
          'device': _device,
          ...extra,
        };

    final diag = {'entity_category': 'diagnostic'};
    return {
      'sensor/$deviceId/proximity': e('proximity', {
        'name': 'Proximity', 'state_class': 'measurement', 'icon': 'mdi:signal-distance-variant',
      }),
      'binary_sensor/$deviceId/presence': e('presence', {
        'name': 'Presence', 'device_class': 'occupancy',
      }),
      'sensor/$deviceId/illuminance': e('illuminance', {
        'name': 'Illuminance', 'device_class': 'illuminance', 'unit_of_measurement': 'lx',
        'state_class': 'measurement',
      }),
      'binary_sensor/$deviceId/screensaver_active': e('screensaver', {
        'name': 'Screensaver', 'icon': 'mdi:image-frame',
      }),
      'switch/$deviceId/screensaver': e('screensaver', {
        'name': 'Screensaver', 'icon': 'mdi:image-frame',
      }, command: true),
      'sensor/$deviceId/last_touch': e('last_touch', {
        'name': 'Last touch', 'device_class': 'timestamp', ...diag,
      }),
      'number/$deviceId/page': e('page', {
        'name': 'Page', 'min': 0, 'max': 20, 'step': 1, 'mode': 'box', 'icon': 'mdi:view-carousel',
      }, command: true),
      'number/$deviceId/brightness': e('brightness', {
        'name': 'Screen brightness', 'min': 0, 'max': 255, 'step': 1, 'mode': 'slider',
        'icon': 'mdi:brightness-6',
      }, command: true),
      'number/$deviceId/volume': e('volume', {
        'name': 'Volume', 'min': 0, 'max': 100, 'step': 1, 'mode': 'slider', 'icon': 'mdi:volume-high',
        'unit_of_measurement': '%',
      }, command: true),
      'notify/$deviceId/announce': {
        'name': 'Announce',
        'unique_id': 'nspanel_${deviceId}_announce',
        'command_topic': '$base/say/set',
        'availability_topic': availabilityTopic,
        'device': _device,
        'icon': 'mdi:bullhorn',
      },
      'button/$deviceId/stop': {
        'name': 'Stop audio',
        'unique_id': 'nspanel_${deviceId}_stop',
        'command_topic': '$base/stop/set',
        'availability_topic': availabilityTopic,
        'device': _device,
        'icon': 'mdi:stop',
      },
      'sensor/$deviceId/rssi': e('rssi', {
        'name': 'Wi-Fi signal', 'device_class': 'signal_strength', 'unit_of_measurement': 'dBm',
        'state_class': 'measurement', ...diag,
      }),
      'sensor/$deviceId/soc_temperature': e('soc_temperature', {
        'name': 'SoC temperature', 'device_class': 'temperature', 'unit_of_measurement': '°C',
        'state_class': 'measurement', ...diag,
      }),
      'sensor/$deviceId/slow_frames': e('slow_frames', {
        'name': 'Slow frames', 'icon': 'mdi:speedometer-slow', 'state_class': 'total_increasing', ...diag,
      }),
      'sensor/$deviceId/version': e('version', {'name': 'App version', 'icon': 'mdi:tag', ...diag}),
    };
  }

  void start() {
    mqtt.onConnected = _announce;
    mqtt.start();
  }

  void _announce() {
    for (final entry in discoveryConfigs().entries) {
      mqtt.publish('homeassistant/${entry.key}/config', jsonEncode(entry.value));
    }
    mqtt.publish(availabilityTopic, 'online');
    mqtt.publish('$base/version', version);

    mqtt.subscribe('$base/brightness/set', (_, v) => _int(v, onBrightness));
    mqtt.subscribe('$base/volume/set', (_, v) => _int(v, onVolume));
    mqtt.subscribe('$base/page/set', (_, v) => _int(v, onPage));
    mqtt.subscribe('$base/screensaver/set', (_, v) => onScreensaver?.call(v.trim().toUpperCase() == 'ON'));
    mqtt.subscribe('$base/stop/set', (_, _) => onStop?.call());
    // The notify entity sends the message text. Anything that names audio is
    // played - a URL, an HA path like /local/x.mp3, a media-source:// id from
    // HA's media browser, or a built-in `sound:doorbell` - and anything else
    // is spoken. JSON gets the same by key, plus `wake` and `volume`.
    mqtt.subscribe('$base/say/set', (_, v) {
      var text = v.trim();
      try {
        final j = jsonDecode(text);
        if (j is Map) {
          if (j['volume'] is num) onVolume?.call((j['volume'] as num).round());
          if (j['wake'] == true) onWake?.call();
          if (j['sound'] != null) {
            onPlay?.call('sound:${j['sound']}');
            return;
          }
          if (j['url'] != null) {
            onPlay?.call(j['url'].toString());
            return;
          }
          text = (j['message'] ?? '').toString().trim();
        }
      } catch (_) {
        // plain text
      }
      if (text.isEmpty) return;
      if (isPlayable(text)) {
        onPlay?.call(text);
      } else {
        onSay?.call(text);
      }
    });

    // re-publish whatever we know so a fresh HA sees state, not "unknown"
    _last.forEach((object, value) => mqtt.publish('$base/$object', value));
  }

  void _int(String v, void Function(int)? cb) {
    final n = num.tryParse(v.trim());
    if (n != null) cb?.call(n.round());
  }

  // ---- state, rate-limited ---------------------------------------------

  final _last = <String, String>{};
  final _lastAt = <String, DateTime>{};

  void _set(String object, String value, {Duration minInterval = Duration.zero, bool force = false}) {
    if (!force && _last[object] == value) return;
    final now = DateTime.now();
    final at = _lastAt[object];
    if (!force && at != null && now.difference(at) < minInterval) return;
    _last[object] = value;
    _lastAt[object] = now;
    mqtt.publish('$base/$object', value);
  }

  // presence from the graded proximity value: learn a resting level, then a
  // sustained departure from it is somebody there. The baseline adapts slowly
  // while nobody is, so a sensor that drifts over the day does not stick on.
  final _baselineSamples = <double>[];
  double? _baseline;
  int _departed = 0;
  bool _present = false;

  void proximity(double v) {
    if (_baseline == null) {
      _baselineSamples.add(v);
      if (_baselineSamples.length >= 20) {
        final s = [..._baselineSamples]..sort();
        _baseline = s[s.length ~/ 2];
      }
    } else {
      final away = (v - _baseline!).abs() > presenceDelta;
      _departed = away ? _departed + 1 : 0;
      final present = _departed >= 2;
      if (!present && !away) _baseline = _baseline! * 0.995 + v * 0.005;
      if (present != _present) {
        _present = present;
        _set('presence', present ? 'ON' : 'OFF');
      }
    }
    _set('proximity', v.round().toString(), minInterval: const Duration(seconds: 1));
  }

  void illuminance(double lux) =>
      _set('illuminance', lux.round().toString(), minInterval: const Duration(seconds: 2));

  void screensaver(bool on) => _set('screensaver', on ? 'ON' : 'OFF');
  void page(int i) => _set('page', i.toString());
  void brightness(int v) => _set('brightness', v.toString());
  void volume(int pct) => _set('volume', pct.toString());
  void rssi(int dbm) => _set('rssi', dbm.toString());
  void slowFrames(int n) => _set('slow_frames', n.toString());
  void temperature(double c) => _set('soc_temperature', c.toStringAsFixed(1));
  void touched() =>
      _set('last_touch', DateTime.now().toUtc().toIso8601String(), minInterval: const Duration(seconds: 5), force: false);
}
