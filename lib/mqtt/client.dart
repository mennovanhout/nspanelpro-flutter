import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'packets.dart';

/// A byte pipe to the broker, abstracted so a test can be the broker.
abstract class MqttTransport {
  Stream<List<int>> get data;
  void send(List<int> bytes);
  Future<void> close();
}

class SocketMqttTransport implements MqttTransport {
  SocketMqttTransport._(this._s);
  final Socket _s;

  static Future<SocketMqttTransport> connect(String host, int port) async =>
      SocketMqttTransport._(await Socket.connect(host, port, timeout: const Duration(seconds: 8)));

  @override
  Stream<List<int>> get data => _s;
  @override
  void send(List<int> bytes) => _s.add(bytes);
  @override
  Future<void> close() => _s.close();
}

typedef MqttTransportFactory = Future<MqttTransport> Function();

/// QoS 0 client with a will, keepalive, and reconnect. State goes out
/// retained so HA sees it on restart; commands come in on subscriptions that
/// are re-established on every reconnect.
class MqttClient {
  MqttClient({
    required this.transportFactory,
    required this.clientId,
    this.username,
    this.password,
    this.keepAlive = 60,
    this.willTopic,
    this.willMessage,
  });

  final MqttTransportFactory transportFactory;
  final String clientId;
  final String? username, password, willTopic, willMessage;
  final int keepAlive;

  final ValueNotifier<bool> connected = ValueNotifier(false);
  void Function()? onConnected;

  MqttTransport? _t;
  StreamSubscription<List<int>>? _listen;
  final _dec = MqttDecoder();
  final _subs = <String, void Function(String topic, String payload)>{};
  Timer? _ping, _retryTimer;
  Duration _backoff = const Duration(seconds: 1);
  bool _closed = false;
  int _packetId = 1;
  DateTime _lastRx = DateTime.now();

  Future<void> start() => _connect();

  Future<void> dispose() async {
    _closed = true;
    _ping?.cancel();
    _retryTimer?.cancel();
    if (connected.value) {
      try {
        _t?.send(encodeDisconnect());
      } catch (_) {}
    }
    await _listen?.cancel();
    await _t?.close();
    connected.value = false;
  }

  Future<void> _connect() async {
    if (_closed) return;
    try {
      _t = await transportFactory();
    } catch (e) {
      debugPrint('mqtt: connect failed: $e');
      _retry();
      return;
    }
    _lastRx = DateTime.now();
    _listen = _t!.data.listen(_onData, onDone: _onClosed, onError: (_) => _onClosed());
    _t!.send(encodeConnect(
      clientId: clientId,
      username: username,
      password: password,
      keepAlive: keepAlive,
      willTopic: willTopic,
      willMessage: willMessage,
    ));
  }

  void _onClosed() {
    if (_closed) return;
    _retry();
  }

  void _retry() {
    connected.value = false;
    _ping?.cancel();
    _listen?.cancel();
    _listen = null;
    _t = null;
    _retryTimer?.cancel();
    _retryTimer = Timer(_backoff, _connect);
    _backoff = Duration(milliseconds: min(_backoff.inMilliseconds * 2, 30000));
  }

  void _onData(List<int> bytes) {
    _lastRx = DateTime.now();
    _dec.add(bytes);
    MqttPacket? p;
    while ((p = _dec.next()) != null) {
      _handle(p!);
    }
  }

  void _handle(MqttPacket p) {
    switch (p.type) {
      case mqttConnack:
        if (p.body.length >= 2 && p.body[1] == 0) {
          _backoff = const Duration(seconds: 1);
          connected.value = true;
          _startPing();
          if (_subs.isNotEmpty) _t?.send(encodeSubscribe(_nextId(), _subs.keys.toList()));
          onConnected?.call();
        } else {
          debugPrint('mqtt: connection refused, code ${p.body.isNotEmpty ? p.body.last : '?'}');
          _closed = p.body.length >= 2 && (p.body[1] == 4 || p.body[1] == 5); // bad credentials: do not hammer
          _t?.close();
          if (!_closed) _retry();
          connected.value = false;
        }
      case mqttPublish:
        final m = decodePublish(p);
        final cb = _subs[m.topic];
        if (cb != null) cb(m.topic, m.payload);
      case mqttPingresp:
      case mqttSuback:
        break;
    }
  }

  int _nextId() {
    _packetId = _packetId >= 0xffff ? 1 : _packetId + 1;
    return _packetId;
  }

  void _startPing() {
    _ping?.cancel();
    _ping = Timer.periodic(Duration(seconds: max(5, keepAlive ~/ 2)), (_) {
      if (DateTime.now().difference(_lastRx).inSeconds > keepAlive * 1.5) {
        debugPrint('mqtt: keepalive timed out');
        _t?.close();
        _retry();
        return;
      }
      _t?.send(encodePingReq());
    });
  }

  /// Fire and forget. Retained so the last value is there for anyone who
  /// connects later - which includes Home Assistant after a restart.
  void publish(String topic, String payload, {bool retain = true}) {
    if (!connected.value) return;
    _t?.send(encodePublish(topic, payload, retain: retain));
  }

  void subscribe(String topic, void Function(String topic, String payload) onMessage) {
    _subs[topic] = onMessage;
    if (connected.value) _t?.send(encodeSubscribe(_nextId(), [topic]));
  }
}
