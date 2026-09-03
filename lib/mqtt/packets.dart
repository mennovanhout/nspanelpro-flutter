import 'dart:convert';
import 'dart:typed_data';

/// MQTT 3.1.1, the parts a panel needs: CONNECT, PUBLISH at QoS 0 (retained
/// where it matters), SUBSCRIBE, PINGREQ, DISCONNECT, and decoding what comes
/// back. Hand-rolled like the HA client, for the same reason: it is small,
/// it has no dependency to rot, and it is testable against a fake broker.

class MqttPacket {
  const MqttPacket(this.type, this.flags, this.body);
  final int type;
  final int flags;
  final Uint8List body;
}

const mqttConnect = 1, mqttConnack = 2, mqttPublish = 3, mqttSubscribe = 8, mqttSuback = 9;
const mqttPingreq = 12, mqttPingresp = 13, mqttDisconnect = 14;

List<int> _str(String s) {
  final b = utf8.encode(s);
  return [b.length >> 8, b.length & 0xff, ...b];
}

List<int> _frame(int type, int flags, List<int> body) {
  final out = <int>[(type << 4) | (flags & 0x0f)];
  var len = body.length;
  do {
    var d = len % 128;
    len ~/= 128;
    if (len > 0) d |= 0x80;
    out.add(d);
  } while (len > 0);
  return out..addAll(body);
}

List<int> encodeConnect({
  required String clientId,
  String? username,
  String? password,
  int keepAlive = 60,
  String? willTopic,
  String? willMessage,
  bool willRetain = true,
}) {
  var flags = 0x02; // clean session
  if (username != null) flags |= 0x80;
  if (password != null) flags |= 0x40;
  if (willTopic != null) flags |= 0x04 | (willRetain ? 0x20 : 0);
  final body = <int>[
    ..._str('MQTT'), 4, flags, keepAlive >> 8, keepAlive & 0xff,
    ..._str(clientId),
    if (willTopic != null) ...[..._str(willTopic), ..._str(willMessage ?? '')],
    if (username != null) ..._str(username),
    if (password != null) ..._str(password),
  ];
  return _frame(mqttConnect, 0, body);
}

List<int> encodePublish(String topic, String payload, {bool retain = false}) =>
    _frame(mqttPublish, retain ? 0x01 : 0, [..._str(topic), ...utf8.encode(payload)]);

List<int> encodeSubscribe(int packetId, List<String> topics) => _frame(
      mqttSubscribe,
      0x02,
      [packetId >> 8, packetId & 0xff, for (final t in topics) ...[..._str(t), 0]],
    );

List<int> encodePingReq() => _frame(mqttPingreq, 0, const []);
List<int> encodeDisconnect() => _frame(mqttDisconnect, 0, const []);

/// A PUBLISH from the broker, pulled apart.
({String topic, String payload}) decodePublish(MqttPacket p) {
  final b = p.body;
  final len = (b[0] << 8) | b[1];
  final topic = utf8.decode(b.sublist(2, 2 + len));
  var at = 2 + len;
  if ((p.flags >> 1) & 0x03 != 0) at += 2; // packet id at QoS 1/2
  return (topic: topic, payload: utf8.decode(b.sublist(at), allowMalformed: true));
}

/// Feed it bytes as they arrive - any chunking - and take whole packets out.
class MqttDecoder {
  final _buf = BytesBuilder(copy: false);
  Uint8List _pending = Uint8List(0);

  void add(List<int> bytes) {
    _buf.add(_pending);
    _buf.add(bytes);
    _pending = _buf.takeBytes();
  }

  MqttPacket? next() {
    final b = _pending;
    if (b.length < 2) return null;
    var len = 0, mult = 1, i = 1;
    while (true) {
      if (i >= b.length) return null;
      final d = b[i++];
      len += (d & 0x7f) * mult;
      if (d & 0x80 == 0) break;
      mult *= 128;
      if (mult > 128 * 128 * 128) throw const FormatException('bad remaining length');
    }
    if (b.length < i + len) return null;
    final packet = MqttPacket(b[0] >> 4, b[0] & 0x0f, Uint8List.sublistView(b, i, i + len));
    _pending = Uint8List.sublistView(b, i + len);
    return packet;
  }
}
