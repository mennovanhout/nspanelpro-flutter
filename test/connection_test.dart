import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nspanel_app/ha/connection.dart';
import 'package:nspanel_app/ha/states.dart';
import 'package:nspanel_app/ha/transport.dart';

/// A fake Home Assistant speaking the real websocket protocol - the same
/// shape as dev/kiosk-mock.js in the cards repo. Service calls mutate its
/// house and echo back a state_changed, so the round trip is real.
class FakeHa implements HaTransport {
  FakeHa(this.states, {this.acceptToken = 'good'}) {
    scheduleMicrotask(() => _emit({'type': 'auth_required', 'ha_version': 'test'}));
  }

  final Map<String, Map<String, dynamic>> states;
  final String acceptToken;
  final _out = StreamController<String>();
  final calls = <String>[];
  final sent = <Map<String, dynamic>>[];
  final _subs = <int, String>{};
  bool closed = false;

  @override
  Stream<String> get messages => _out.stream;

  void _emit(Map<String, dynamic> m) => _out.add(jsonEncode(m));

  @override
  void send(String data) {
    final msg = (jsonDecode(data) as Map).cast<String, dynamic>();
    sent.add(msg);
    switch (msg['type']) {
      case 'auth':
        _emit(msg['access_token'] == acceptToken
            ? {'type': 'auth_ok', 'ha_version': 'test'}
            : {'type': 'auth_invalid', 'message': 'invalid access token'});
      case 'get_states':
        _emit({'id': msg['id'], 'type': 'result', 'success': true, 'result': states.values.toList()});
      case 'subscribe_events':
        _subs[msg['id'] as int] = msg['event_type'] as String;
        _emit({'id': msg['id'], 'type': 'result', 'success': true, 'result': null});
      case 'unsubscribe_events':
        _subs.remove(msg['subscription']);
        _emit({'id': msg['id'], 'type': 'result', 'success': true, 'result': null});
      case 'call_service':
        calls.add('${msg['domain']}.${msg['service']} ${jsonEncode(msg['service_data'])}');
        final data = (msg['service_data'] as Map?)?.cast<String, dynamic>() ?? const {};
        final id = data['entity_id'] as String?;
        _emit({'id': msg['id'], 'type': 'result', 'success': true, 'result': null});
        if (id != null && states[id] != null && msg['domain'] == 'light') {
          final s = states[id]!;
          if (msg['service'] == 'toggle') s['state'] = s['state'] == 'on' ? 'off' : 'on';
          if (msg['service'] == 'turn_on') {
            s['state'] = 'on';
            if (data['brightness_pct'] is num) {
              (s['attributes'] as Map)['brightness'] = ((data['brightness_pct'] as num) * 2.55).round();
            }
          }
          push(id);
        }
      case 'lovelace/config':
        _emit({
          'id': msg['id'],
          'type': 'result',
          'success': true,
          'result': {
            'views': [
              {
                'cards': [
                  {'type': 'custom:nspanel-light-card', 'entity': 'light.a'},
                ],
              },
            ],
          },
        });
      default:
        _emit({
          'id': msg['id'],
          'type': 'result',
          'success': false,
          'error': {'code': 'unknown_command', 'message': 'fake does not implement ${msg['type']}'},
        });
    }
  }

  void push(String id) {
    for (final e in _subs.entries) {
      if (e.value != 'state_changed') continue;
      _emit({
        'id': e.key,
        'type': 'event',
        'event': {
          'event_type': 'state_changed',
          'data': {'entity_id': id, 'new_state': states[id], 'old_state': null},
        },
      });
    }
  }

  @override
  Future<void> close() async {
    closed = true;
    await _out.close();
  }
}

Map<String, dynamic> st(String id, String state, [Map<String, dynamic>? attrs]) =>
    {'entity_id': id, 'state': state, 'attributes': attrs ?? {}};

void main() {
  late FakeHa fake;
  late HaStates states;
  late HaConnection conn;

  setUp(() {
    fake = FakeHa({
      'light.a': st('light.a', 'on', {'friendly_name': 'A', 'brightness': 173}),
      'sensor.t': st('sensor.t', '21.4', {'unit_of_measurement': '°C'}),
    });
    states = HaStates();
    conn = HaConnection(transportFactory: () async => fake, token: 'good', states: states);
  });

  tearDown(() => conn.dispose());

  test('auths, seeds every state, and reports online', () async {
    final ready = Completer<void>();
    conn.onReady = ready.complete;
    await conn.start();
    await ready.future.timeout(const Duration(seconds: 2));

    expect(conn.status.value, HaStatus.online);
    expect(states.get('light.a')?.isOn, isTrue);
    expect(states.get('sensor.t')?.numeric, 21.4);
    expect(fake.sent.first['type'], 'auth');
    expect(fake.sent.where((m) => m['type'] == 'subscribe_events').single['event_type'], 'state_changed');
  });

  test('a service call round-trips as a state_changed into the entity notifier', () async {
    final ready = Completer<void>();
    conn.onReady = ready.complete;
    await conn.start();
    await ready.future;

    final seen = <String>[];
    states.listen('light.a').addListener(() => seen.add(states.get('light.a')!.state));

    await conn.callService('light', 'toggle', {'entity_id': 'light.a'});
    await pumpEventQueue();
    expect(fake.calls, ['light.toggle {"entity_id":"light.a"}']);
    expect(seen, ['off']);
    expect(states.get('light.a')?.isOn, isFalse);

    await conn.callService('light', 'turn_on', {'entity_id': 'light.a', 'brightness_pct': 40});
    await pumpEventQueue();
    expect(states.get('light.a')?.numAttr('brightness'), 102);
  });

  test('an untouched entity never notifies', () async {
    final ready = Completer<void>();
    conn.onReady = ready.complete;
    await conn.start();
    await ready.future;

    var sensorNotified = 0;
    states.listen('sensor.t').addListener(() => sensorNotified++);
    await conn.callService('light', 'toggle', {'entity_id': 'light.a'});
    await pumpEventQueue();
    expect(sensorNotified, 0);
  });

  test('fetches the lovelace config', () async {
    final ready = Completer<void>();
    conn.onReady = ready.complete;
    await conn.start();
    await ready.future;

    final cfg = await conn.fetchLovelace('');
    expect((cfg['views'] as List).length, 1);
    final req = fake.sent.firstWhere((m) => m['type'] == 'lovelace/config');
    expect(req['url_path'], isNull);
  });

  test('a subscription can be released', () async {
    final ready = Completer<void>();
    conn.onReady = ready.complete;
    await conn.start();
    await ready.future;

    final unsub = await conn.subscribe({'type': 'subscribe_events', 'event_type': 'lovelace_updated'}, (_) {});
    await unsub();
    expect(fake.sent.any((m) => m['type'] == 'unsubscribe_events'), isTrue);
  });

  test('a rejected token is reported and not retried', () async {
    final bad = HaConnection(
      transportFactory: () async => FakeHa({}, acceptToken: 'other'),
      token: 'good',
      states: HaStates(),
    );
    await bad.start();
    await pumpEventQueue();
    expect(bad.status.value, HaStatus.authFailed);
    await bad.dispose();
  });
}
