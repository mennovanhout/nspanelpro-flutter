import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nspanel_app/mqtt/bridge.dart';
import 'package:nspanel_app/mqtt/client.dart';
import 'package:nspanel_app/mqtt/packets.dart';

/// Records what the bridge publishes and lets a test push commands in.
class _Broker implements MqttTransport {
  final _out = StreamController<List<int>>();
  final _dec = MqttDecoder();
  final published = <String, String>{};
  final subscribed = <String>[];

  @override
  Stream<List<int>> get data => _out.stream;

  @override
  void send(List<int> bytes) {
    _dec.add(bytes);
    MqttPacket? p;
    while ((p = _dec.next()) != null) {
      switch (p!.type) {
        case mqttConnect:
          _out.add([mqttConnack << 4, 2, 0, 0]);
        case mqttSubscribe:
          final r = p.body.sublist(2);
          var at = 0;
          while (at < r.length) {
            final n = (r[at] << 8) | r[at + 1];
            subscribed.add(String.fromCharCodes(r.sublist(at + 2, at + 2 + n)));
            at += 2 + n + 1;
          }
          _out.add([mqttSuback << 4, 3, p.body[0], p.body[1], 0]);
        case mqttPublish:
          final m = decodePublish(p);
          published[m.topic] = m.payload;
        case mqttPingreq:
          _out.add([mqttPingresp << 4, 0]);
      }
    }
  }

  void deliver(String topic, String payload) => _out.add(encodePublish(topic, payload));

  @override
  Future<void> close() => _out.close();
}

void main() {
  late _Broker broker;
  late MqttClient mqtt;
  late PanelBridge bridge;
  final commands = <String>[];

  setUp(() {
    commands.clear();
    broker = _Broker();
    mqtt = MqttClient(transportFactory: () async => broker, clientId: 'c');
    bridge = PanelBridge(
      mqtt: mqtt,
      deviceId: 'abc123',
      name: 'NSPanel Dining',
      version: '0.2.0',
      onBrightness: (v) => commands.add('brightness $v'),
      onVolume: (v) => commands.add('volume $v'),
      onScreensaver: (on) => commands.add('screensaver $on'),
      onPage: (i) => commands.add('page $i'),
      onSay: (t) => commands.add('say $t'),
      onPlay: (u) => commands.add('play $u'),
      onStop: () => commands.add('stop'),
      onWake: () => commands.add('wake'),
    );
  });

  tearDown(() => mqtt.dispose());

  test('every entity belongs to one device and points at the same availability topic', () {
    final configs = bridge.discoveryConfigs();
    expect(configs.length, greaterThanOrEqualTo(12));
    for (final e in configs.entries) {
      final c = e.value;
      expect(c['unique_id'], startsWith('nspanel_abc123_'), reason: e.key);
      expect((c['device'] as Map)['identifiers'], ['nspanel_abc123'], reason: e.key);
      expect(c['availability_topic'], 'nspanel/abc123/availability', reason: e.key);
      expect(c['name'], isNotNull, reason: e.key);
    }
    expect(configs['number/abc123/brightness']!['command_topic'], 'nspanel/abc123/brightness/set');
    expect(configs['sensor/abc123/illuminance']!['device_class'], 'illuminance');
    expect(configs['binary_sensor/abc123/presence']!['device_class'], 'occupancy');
    expect(configs['notify/abc123/announce']!['command_topic'], 'nspanel/abc123/say/set');
    expect(configs['switch/abc123/screensaver']!['state_topic'], 'nspanel/abc123/screensaver');
  });

  test('on connect it announces itself: discovery, online, version, subscriptions', () async {
    bridge.start();
    await pumpEventQueue();
    final discovery = broker.published.keys.where((k) => k.startsWith('homeassistant/')).toList();
    expect(discovery.length, bridge.discoveryConfigs().length);
    expect(jsonDecode(broker.published['homeassistant/sensor/abc123/proximity/config']!)['name'], 'Proximity');
    expect(broker.published['nspanel/abc123/availability'], 'online');
    expect(broker.published['nspanel/abc123/version'], '0.2.0');
    expect(broker.subscribed, containsAll([
      'nspanel/abc123/brightness/set',
      'nspanel/abc123/volume/set',
      'nspanel/abc123/page/set',
      'nspanel/abc123/screensaver/set',
      'nspanel/abc123/say/set',
      'nspanel/abc123/stop/set',
    ]));
  });

  test('commands from HA dispatch to the right hook', () async {
    bridge.start();
    await pumpEventQueue();
    broker.deliver('nspanel/abc123/brightness/set', '128');
    broker.deliver('nspanel/abc123/volume/set', '40.0');
    broker.deliver('nspanel/abc123/screensaver/set', 'ON');
    broker.deliver('nspanel/abc123/screensaver/set', 'off');
    broker.deliver('nspanel/abc123/page/set', '2');
    broker.deliver('nspanel/abc123/say/set', 'Dinner is ready');
    broker.deliver('nspanel/abc123/say/set', 'https://x/chime.mp3');
    broker.deliver('nspanel/abc123/say/set', '{"url": "https://x/bell.mp3"}');
    broker.deliver('nspanel/abc123/say/set', '{"message": "Hello"}');
    broker.deliver('nspanel/abc123/stop/set', 'PRESS');
    await pumpEventQueue();
    expect(commands, [
      'brightness 128',
      'volume 40',
      'screensaver true',
      'screensaver false',
      'page 2',
      'say Dinner is ready',
      'play https://x/chime.mp3',
      'play https://x/bell.mp3',
      'say Hello',
      'stop',
    ]);
  });

  test('a doorbell: built-in sounds, HA paths, media browser ids, wake and volume', () async {
    bridge.start();
    await pumpEventQueue();
    broker.deliver('nspanel/abc123/say/set', 'sound:doorbell');
    broker.deliver('nspanel/abc123/say/set', '/local/sounds/bell.mp3');
    broker.deliver('nspanel/abc123/say/set', 'media-source://media_source/local/bell.mp3');
    broker.deliver('nspanel/abc123/say/set', '{"sound": "chime", "wake": true, "volume": 80}');
    broker.deliver('nspanel/abc123/say/set', '{"message": "Someone is at the door", "wake": true}');
    await pumpEventQueue();
    expect(commands, [
      'play sound:doorbell',
      'play /local/sounds/bell.mp3',
      'play media-source://media_source/local/bell.mp3',
      'volume 80',
      'wake',
      'play sound:chime',
      'wake',
      'say Someone is at the door',
    ]);
  });

  test('proximity is rate-limited and presence is derived from a learned baseline', () async {
    bridge.start();
    await pumpEventQueue();
    // twenty quiet readings set the resting level
    for (var i = 0; i < 20; i++) {
      bridge.proximity(55 + (i % 3).toDouble());
    }
    await pumpEventQueue();
    expect(broker.published['nspanel/abc123/presence'], isNull, reason: 'nobody there yet');
    // a sustained departure is presence
    bridge.proximity(80);
    bridge.proximity(82);
    await pumpEventQueue();
    expect(broker.published['nspanel/abc123/presence'], 'ON');
    // one spike back near baseline is not "gone" until it holds
    bridge.proximity(56);
    await pumpEventQueue();
    expect(broker.published['nspanel/abc123/presence'], 'OFF');
    // the raw value went out at most once in this burst (1 s minimum interval)
    expect(broker.published['nspanel/abc123/proximity'], isNotNull);
  });

  test('state is retained and unchanged values are not re-sent', () async {
    bridge.start();
    await pumpEventQueue();
    bridge.screensaver(true);
    bridge.screensaver(true);
    bridge.page(1);
    await pumpEventQueue();
    expect(broker.published['nspanel/abc123/screensaver'], 'ON');
    expect(broker.published['nspanel/abc123/page'], '1');
  });

  test('the update entity: state JSON and the install command', () async {
    final broker = _Broker();
    final mqtt = MqttClient(transportFactory: () async => broker, clientId: 'c');
    var installs = 0;
    final b = PanelBridge(mqtt: mqtt, deviceId: 'd1', name: 'P', version: '0.2.0', onInstall: () => installs++);
    b.start();
    await pumpEventQueue();
    final cfg = jsonDecode(broker.published['homeassistant/update/d1/app/config']!) as Map;
    expect(cfg['payload_install'], 'install');
    expect(cfg['command_topic'], 'nspanel/d1/update/set');
    expect(cfg['device_class'], 'firmware');
    b.updateState(installed: '0.2.0', latest: '0.3.0', url: 'https://r', notes: 'Alarm card');
    await pumpEventQueue();
    final st = jsonDecode(broker.published['nspanel/d1/update']!) as Map;
    expect(st['installed_version'], '0.2.0');
    expect(st['latest_version'], '0.3.0');
    expect(st['release_url'], 'https://r');
    expect(st['in_progress'], false);
    b.updateState(installed: '0.2.0', latest: '0.3.0', inProgress: true, percent: 40);
    await pumpEventQueue();
    expect((jsonDecode(broker.published['nspanel/d1/update']!) as Map)['update_percentage'], 40);
    broker.deliver('nspanel/d1/update/set', 'install');
    await pumpEventQueue();
    expect(installs, 1);
    mqtt.dispose();
  });
}
