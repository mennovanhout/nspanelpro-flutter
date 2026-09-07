import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nspanel_app/cards/env.dart';
import 'package:nspanel_app/cards/switch_card.dart';
import 'package:nspanel_app/config/settings.dart';
import 'package:nspanel_app/ha/connection.dart';
import 'package:nspanel_app/ha/states.dart';

import 'connection_test.dart' show FakeHa, st;

void main() {
  testWidgets('a tap is echoed at once, then confirmed by the state; turn_on/turn_off, never toggle',
      (tester) async {
    final fake = FakeHa({
      'switch.garden': st('switch.garden', 'off', {'friendly_name': 'Garden lights'}),
      'input_boolean.guest': st('input_boolean.guest', 'on', {'friendly_name': 'Guest mode'}),
      'switch.dead': st('switch.dead', 'unavailable', {'friendly_name': 'Pond pump'}),
    });
    final states = HaStates();
    final conn = HaConnection(transportFactory: () async => fake, token: 'good', states: states);
    final ready = Completer<void>();
    conn.onReady = ready.complete;
    await conn.start();
    await ready.future.timeout(const Duration(seconds: 2));

    final env = PanelEnv(states: states, conn: conn, settings: Settings(url: 'http://x', token: 't'));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SwitchCard(
          config: {
            'type': 'custom:nspanel-switch-card',
            'height': 300,
            'columns': 3,
            'switches': [
              {'entity': 'switch.garden', 'name': 'Garden'},
              'input_boolean.guest', // the bare form
              {'entity': 'switch.dead'},
            ],
          },
          env: env,
        ),
      ),
    ));
    await tester.pump();
    expect(find.text('Garden'), findsOneWidget);
    expect(find.text('Guest mode'), findsOneWidget);
    expect(find.text('Pond pump'), findsOneWidget);
    expect(find.text('Unavailable'), findsOneWidget);
    expect(find.text('On'), findsOneWidget);
    expect(find.text('Off'), findsOneWidget);

    // the tap shows On before HA has answered (the fake answers 50 ms later)
    await tester.tap(find.text('Garden'));
    await tester.pump();
    expect(find.text('On'), findsNWidgets(2));
    expect(fake.calls.last, 'homeassistant.turn_on {"entity_id":"switch.garden"}');
    await tester.pump(const Duration(milliseconds: 100));
    expect(states.get('switch.garden')?.state, 'on');
    expect(find.text('On'), findsNWidgets(2));

    // and the other way, off a tile that is on
    await tester.tap(find.text('Guest mode'));
    await tester.pump();
    expect(fake.calls.last, 'homeassistant.turn_off {"entity_id":"input_boolean.guest"}');
    await tester.pump(const Duration(milliseconds: 100));
    expect(states.get('input_boolean.guest')?.state, 'off');

    // the unavailable one does nothing
    final before = fake.calls.length;
    await tester.tap(find.text('Pond pump'));
    await tester.pump();
    expect(fake.calls.length, before);

    // let the echo timers run out before the test ends
    await tester.pump(const Duration(seconds: 2));
    unawaited(conn.dispose());
  });
}
