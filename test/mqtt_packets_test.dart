import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nspanel_app/mqtt/packets.dart';

/// Reads the length-prefixed strings MQTT uses, for pulling a CONNECT apart.
class _Reader {
  _Reader(this.b);
  final List<int> b;
  int at = 0;
  int u8() => b[at++];
  int u16() => (u8() << 8) | u8();
  String str() {
    final n = u16();
    final s = utf8.decode(b.sublist(at, at + n));
    at += n;
    return s;
  }
}

void main() {
  test('CONNECT carries the will, the credentials and clean session', () {
    final bytes = encodeConnect(
      clientId: 'nspanel-abc',
      username: 'mqtt',
      password: 'secret',
      keepAlive: 60,
      willTopic: 'nspanel/abc/availability',
      willMessage: 'offline',
    );
    final dec = MqttDecoder()..add(bytes);
    final p = dec.next()!;
    expect(p.type, mqttConnect);
    final r = _Reader(p.body);
    expect(r.str(), 'MQTT');
    expect(r.u8(), 4);
    final flags = r.u8();
    expect(flags & 0x02, 0x02, reason: 'clean session');
    expect(flags & 0x04, 0x04, reason: 'will flag');
    expect(flags & 0x20, 0x20, reason: 'will retain');
    expect(flags & 0x80, 0x80, reason: 'username');
    expect(flags & 0x40, 0x40, reason: 'password');
    expect(r.u16(), 60);
    expect(r.str(), 'nspanel-abc');
    expect(r.str(), 'nspanel/abc/availability');
    expect(r.str(), 'offline');
    expect(r.str(), 'mqtt');
    expect(r.str(), 'secret');
    expect(r.at, p.body.length);
  });

  test('PUBLISH round-trips, retained flag included', () {
    final bytes = encodePublish('nspanel/abc/proximity', '57', retain: true);
    final p = (MqttDecoder()..add(bytes)).next()!;
    expect(p.type, mqttPublish);
    expect(p.flags & 0x01, 1);
    final m = decodePublish(p);
    expect(m.topic, 'nspanel/abc/proximity');
    expect(m.payload, '57');
  });

  test('the decoder handles bytes arriving in any chunking', () {
    final a = encodePublish('t/1', 'one');
    final b = encodePublish('t/2', 'two');
    final c = encodePingReq();
    final all = [...a, ...b, ...c];

    // one byte at a time
    final d1 = MqttDecoder();
    final got1 = <String>[];
    for (final byte in all) {
      d1.add([byte]);
      MqttPacket? p;
      while ((p = d1.next()) != null) {
        got1.add(p!.type == mqttPublish ? decodePublish(p).payload : 'ping');
      }
    }
    expect(got1, ['one', 'two', 'ping']);

    // everything at once
    final d2 = MqttDecoder()..add(all);
    final got2 = <String>[];
    MqttPacket? p;
    while ((p = d2.next()) != null) {
      got2.add(p!.type == mqttPublish ? decodePublish(p).payload : 'ping');
    }
    expect(got2, ['one', 'two', 'ping']);
  });

  test('remaining length uses the multi-byte encoding above 127', () {
    final big = 'x' * 300;
    final bytes = encodePublish('t', big);
    expect(bytes[1] & 0x80, 0x80, reason: 'continuation bit on the first length byte');
    final p = (MqttDecoder()..add(bytes)).next()!;
    expect(decodePublish(p).payload.length, 300);
  });

  test('SUBSCRIBE has the required flags and a QoS byte per topic', () {
    final bytes = encodeSubscribe(7, ['a/set', 'b/set']);
    final p = (MqttDecoder()..add(bytes)).next()!;
    expect(p.type, mqttSubscribe);
    expect(p.flags, 0x02);
    final r = _Reader(p.body);
    expect(r.u16(), 7);
    expect(r.str(), 'a/set');
    expect(r.u8(), 0);
    expect(r.str(), 'b/set');
    expect(r.u8(), 0);
  });
}
