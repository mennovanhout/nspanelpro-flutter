import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nspanel_app/mqtt/client.dart';
import 'package:nspanel_app/mqtt/packets.dart';

/// A broker that speaks just enough MQTT 3.1.1 to exercise the client:
/// CONNACK, SUBACK, PINGRESP, and it keeps what was published.
class FakeBroker implements MqttTransport {
  FakeBroker({this.acceptPassword = 'ok'});
  final String acceptPassword;
  final _out = StreamController<List<int>>();
  final _dec = MqttDecoder();
  final published = <({String topic, String payload, bool retain})>[];
  final subscribed = <String>[];
  int pings = 0;
  bool closed = false;

  @override
  Stream<List<int>> get data => _out.stream;

  @override
  void send(List<int> bytes) {
    _dec.add(bytes);
    MqttPacket? p;
    while ((p = _dec.next()) != null) {
      _handle(p!);
    }
  }

  void _handle(MqttPacket p) {
    switch (p.type) {
      case mqttConnect:
        // the password is the last length-prefixed string in the body
        final b = p.body;
        final n = (b[b.length - 2 - _lastLen(b)] << 8) | b[b.length - 1 - _lastLen(b)];
        final pw = String.fromCharCodes(b.sublist(b.length - n));
        _out.add([mqttConnack << 4, 2, 0, pw == acceptPassword ? 0 : 5]);
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
        published.add((topic: m.topic, payload: m.payload, retain: p.flags & 1 == 1));
      case mqttPingreq:
        pings++;
        _out.add([mqttPingresp << 4, 0]);
    }
  }

  int _lastLen(List<int> b) {
    // walk back: the last string's length prefix sits before its bytes; we
    // find it by trying lengths from the end
    for (var n = 0; n < b.length - 2; n++) {
      final at = b.length - n - 2;
      if (((b[at] << 8) | b[at + 1]) == n) return n;
    }
    return 0;
  }

  /// Something arriving from the broker, e.g. a command from HA.
  void deliver(String topic, String payload) => _out.add(encodePublish(topic, payload));

  @override
  Future<void> close() async {
    closed = true;
    await _out.close();
  }
}

void main() {
  late FakeBroker broker;
  late MqttClient client;

  setUp(() {
    broker = FakeBroker();
    client = MqttClient(
      transportFactory: () async => broker,
      clientId: 'nspanel-test',
      username: 'mqtt',
      password: 'ok',
      willTopic: 'nspanel/test/availability',
      willMessage: 'offline',
    );
  });

  tearDown(() => client.dispose());

  test('connects, then publishes retained and subscribes', () async {
    final connected = Completer<void>();
    client.onConnected = connected.complete;
    await client.start();
    await connected.future.timeout(const Duration(seconds: 2));
    expect(client.connected.value, isTrue);

    client.publish('nspanel/test/proximity', '57');
    client.subscribe('nspanel/test/brightness/set', (_, _) {});
    await pumpEventQueue();

    expect(broker.published.single.topic, 'nspanel/test/proximity');
    expect(broker.published.single.retain, isTrue);
    expect(broker.subscribed, ['nspanel/test/brightness/set']);
  });

  test('a command from the broker reaches the right handler', () async {
    final connected = Completer<void>();
    client.onConnected = connected.complete;
    await client.start();
    await connected.future;

    final got = <String>[];
    client.subscribe('nspanel/test/brightness/set', (_, v) => got.add(v));
    await pumpEventQueue();
    broker.deliver('nspanel/test/brightness/set', '128');
    broker.deliver('nspanel/test/other', 'ignored');
    await pumpEventQueue();
    expect(got, ['128']);
  });

  test('subscriptions made before connecting are sent once connected', () async {
    client.subscribe('nspanel/test/page/set', (_, _) {});
    final connected = Completer<void>();
    client.onConnected = connected.complete;
    await client.start();
    await connected.future;
    await pumpEventQueue();
    expect(broker.subscribed, ['nspanel/test/page/set']);
  });

  test('nothing is published while disconnected', () async {
    client.publish('nspanel/test/x', '1');
    expect(broker.published, isEmpty);
  });

  test('bad credentials are reported once and not retried forever', () async {
    final bad = FakeBroker(acceptPassword: 'other');
    var attempts = 0;
    final c = MqttClient(
      transportFactory: () async {
        attempts++;
        return bad;
      },
      clientId: 'x',
      username: 'mqtt',
      password: 'ok',
    );
    await c.start();
    await pumpEventQueue();
    expect(c.connected.value, isFalse);
    expect(attempts, 1);
    await c.dispose();
  });
}
