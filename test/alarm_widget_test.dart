import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nspanel_app/cards/alarm_card.dart';
import 'package:nspanel_app/cards/env.dart';
import 'package:nspanel_app/config/settings.dart';
import 'package:nspanel_app/ha/connection.dart';
import 'package:nspanel_app/ha/states.dart';

import 'connection_test.dart' show FakeHa, st;

void main() {
  testWidgets('arm without a code; the keypad refuses 0000 and takes 1234; sounds follow the state',
      (tester) async {
    final fake = FakeHa({
      'alarm_control_panel.home': st('alarm_control_panel.home', 'disarmed', {
        'friendly_name': 'Home Alarm', 'code_format': 'number', 'code_arm_required': false,
        'supported_features': 7,
      }),
    });
    final states = HaStates();
    final conn = HaConnection(transportFactory: () async => fake, token: 'good', states: states);
    final ready = Completer<void>();
    conn.onReady = ready.complete;
    await conn.start();
    await ready.future.timeout(const Duration(seconds: 2));

    final played = <String>[];
    final env = PanelEnv(states: states, conn: conn, settings: Settings(url: 'http://x', token: 't'), play: played.add);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AlarmCard(
          config: {
            'type': 'custom:nspanel-alarm-card',
            'entity': 'alarm_control_panel.home',
            'modes': ['home', 'away', 'night'],
          },
          env: env,
        ),
      ),
    ));
    await tester.pump();
    expect(find.text('Disarmed'), findsOneWidget);
    expect(find.text('Home Alarm'), findsOneWidget);
    for (final m in ['Home', 'Away', 'Night']) {
      expect(find.text(m), findsOneWidget);
    }

    // no code to arm: straight to the service, optimistic label, then the state
    await tester.tap(find.text('Away'));
    await tester.pump();
    expect(find.text('Arming…'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Armed away'), findsOneWidget);
    expect(find.text('Disarm'), findsOneWidget);
    expect(find.text('Away'), findsNothing);
    expect(played, ['sound:armed']);

    // disarm wants a code: the keypad
    await tester.tap(find.text('Disarm'));
    await tester.pumpAndSettle();
    expect(find.text('Enter the code'), findsOneWidget);
    final confirm = find.widgetWithText(FilledButton, 'Disarm');
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull, reason: 'nothing typed yet');
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.text('0'));
      await tester.pump();
    }
    await tester.tap(confirm);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Wrong code'), findsOneWidget);
    expect(find.text('Armed away'), findsOneWidget, reason: 'still armed');
    expect(find.text('Enter the code'), findsNothing);

    for (final k in ['1', '2', '3', '4']) {
      await tester.tap(find.text(k));
      await tester.pump();
    }
    await tester.tap(confirm);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Wrong code'), findsNothing);
    expect(find.text('Disarmed'), findsOneWidget);
    expect(find.text('Away'), findsOneWidget);
    expect(played, ['sound:armed', 'sound:disarmed']);
    expect(fake.calls.last, contains('"code":"1234"'));

    await tester.pump(const Duration(seconds: 4)); // the wrong-code and echo timers
    // not awaited: under fake async a real-time wait in dispose never ends
    unawaited(conn.dispose());
  });
}
