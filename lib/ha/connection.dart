import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'states.dart';
import 'transport.dart';

enum HaStatus { connecting, online, offline, authFailed }

typedef TransportFactory = Future<HaTransport> Function();

/// The Home Assistant websocket, and nothing else.
///
/// A port of kiosk/app.js from the cards repo, which was verified against a
/// fake HA speaking the real protocol: auth handshake, get_states, a
/// state_changed subscription, call_service, and generic subscribeMessage for
/// the weather forecast. Reconnects with backoff.
class HaConnection {
  HaConnection({
    required this.transportFactory,
    required this.token,
    required this.states,
  });

  final TransportFactory transportFactory;
  final String token;
  final HaStates states;

  final ValueNotifier<HaStatus> status = ValueNotifier(HaStatus.connecting);

  /// Called after every successful auth + state seed, so the app can (re)load
  /// the dashboard config on each reconnect.
  void Function()? onReady;

  HaTransport? _t;
  StreamSubscription<String>? _listen;
  int _id = 1;
  final _pending = <int, Completer<dynamic>>{};
  final _subs = <int, void Function(dynamic)>{};
  Duration _backoff = const Duration(seconds: 1);
  Timer? _retryTimer;
  bool _closed = false;
  bool _authed = false;

  bool get isOnline => _authed;

  Future<void> start() => _connect();

  Future<void> dispose() async {
    _closed = true;
    _retryTimer?.cancel();
    await _listen?.cancel();
    await _t?.close();
    _failPending();
  }

  Future<void> _connect() async {
    if (_closed) return;
    status.value = HaStatus.connecting;
    try {
      _t = await transportFactory();
    } catch (_) {
      _retry();
      return;
    }
    _listen = _t!.messages.listen(
      _onMessage,
      onDone: () {
        if (!_closed) _retry();
      },
      onError: (_) {
        if (!_closed) _retry();
      },
    );
  }

  void _failPending() {
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(StateError('socket closed'));
    }
    _pending.clear();
    _subs.clear();
  }

  void _retry() {
    _authed = false;
    status.value = HaStatus.offline;
    _failPending();
    _retryTimer?.cancel();
    // Back off, but never so far that a panel left overnight takes minutes to
    // notice HA came back.
    _retryTimer = Timer(_backoff, _connect);
    _backoff = Duration(milliseconds: min(_backoff.inMilliseconds * 2, 15000));
  }

  void _onMessage(String raw) {
    final dynamic msg;
    try {
      msg = jsonDecode(raw);
    } catch (_) {
      return;
    }
    if (msg is! Map) return;
    switch (msg['type']) {
      case 'auth_required':
        _t!.send(jsonEncode({'type': 'auth', 'access_token': token}));
      case 'auth_invalid':
        _closed = true;
        status.value = HaStatus.authFailed;
      case 'auth_ok':
        _authed = true;
        _backoff = const Duration(seconds: 1);
        status.value = HaStatus.online;
        _seed();
      case 'result':
        final c = _pending.remove(msg['id']);
        if (c == null) return;
        if (msg['success'] == true) {
          c.complete(msg['result']);
        } else {
          final err = msg['error'];
          c.completeError(StateError(err is Map ? '${err['message']}' : 'call failed'));
        }
      case 'event':
        _subs[msg['id']]?.call(msg['event']);
    }
  }

  Future<dynamic> send(Map<String, dynamic> payload) {
    if (!_authed || _t == null) return Future.error(StateError('not connected'));
    final id = _id++;
    final c = Completer<dynamic>();
    _pending[id] = c;
    _t!.send(jsonEncode({'id': id, ...payload}));
    return c.future;
  }

  /// Same shape as the frontend's connection.subscribeMessage. Resolves to an
  /// unsubscribe function.
  Future<Future<void> Function()> subscribe(
    Map<String, dynamic> payload,
    void Function(dynamic event) onEvent,
  ) {
    if (!_authed || _t == null) return Future.error(StateError('not connected'));
    final id = _id++;
    _subs[id] = onEvent;
    final c = Completer<dynamic>();
    _pending[id] = c;
    _t!.send(jsonEncode({'id': id, ...payload}));
    return c.future.then((_) => () async {
          _subs.remove(id);
          try {
            await send({'type': 'unsubscribe_events', 'subscription': id});
          } catch (_) {
            // already gone; nothing to release
          }
        }).catchError((Object e) {
      _subs.remove(id);
      throw e;
    });
  }

  /// get_states once, then every state_changed. Not subscribe_entities: its
  /// compressed diff format is more code to get right, and a panel's handful
  /// of cards filters client-side cheaply.
  Future<void> _seed() async {
    try {
      final list = await send({'type': 'get_states'}) as List;
      states.replaceAll({
        for (final s in list.cast<Map>())
          s['entity_id'] as String: HaState.fromJson(s.cast<String, dynamic>()),
      });
      await subscribe({'type': 'subscribe_events', 'event_type': 'state_changed'}, (ev) {
        final d = (ev as Map?)?['data'];
        if (d is! Map) return;
        final id = d['entity_id'];
        if (id is! String) return;
        final ns = d['new_state'];
        states.update(id, ns is Map ? HaState.fromJson(ns.cast<String, dynamic>()) : null);
      });
      onReady?.call();
    } catch (e) {
      debugPrint('seed failed: $e');
    }
  }

  Future<void> callService(String domain, String service, [Map<String, dynamic>? data]) async {
    try {
      await send({
        'type': 'call_service',
        'domain': domain,
        'service': service,
        'service_data': data ?? const {},
      });
    } catch (e) {
      debugPrint('call_service $domain.$service failed: $e');
    }
  }

  Future<Map<String, dynamic>> fetchLovelace(String? urlPath) async {
    final r = await send({
      'type': 'lovelace/config',
      'url_path': (urlPath == null || urlPath.isEmpty) ? null : urlPath,
      'force': false,
    });
    return (r as Map).cast<String, dynamic>();
  }
}
