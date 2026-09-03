import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nspanel_app/cards/alarm_card.dart';
import 'package:nspanel_app/ha/connection.dart';
import 'package:nspanel_app/ha/states.dart';

import 'connection_test.dart' show FakeHa, st;

void main() {
  test('modes: the config order, minus what the entity cannot do', () {
    // ARM_HOME=1, ARM_AWAY=2, ARM_NIGHT=4: night listed but unsupported is dropped
    expect(alarmModesFor(['night', 'away', 'home'], 3).map((m) => m.key), ['away', 'home']);
    expect(alarmModesFor([], 7).map((m) => m.key), ['home', 'away']);
    expect(alarmModesFor(['vacation', 'custom_bypass'], 48).map((m) => m.key), ['vacation', 'custom_bypass']);
    expect(alarmModesFor(['home', 'bogus'], null).map((m) => m.key), ['home']);
  });

  test('a code is asked for exactly when HA would want one', () {
    expect(alarmNeedsCode(codeFormat: null, codeArmRequired: true, arming: true), isFalse);
    expect(alarmNeedsCode(codeFormat: null, codeArmRequired: true, arming: false), isFalse);
    expect(alarmNeedsCode(codeFormat: 'number', codeArmRequired: false, arming: true), isFalse);
    expect(alarmNeedsCode(codeFormat: 'number', codeArmRequired: false, arming: false), isTrue);
    expect(alarmNeedsCode(codeFormat: 'number', codeArmRequired: null, arming: true), isTrue);
  });

  test('every state has a look; unknown ones read as unavailable', () {
    expect(alarmLook('armed_away', Colors.green).label, 'Armed away');
    expect(alarmLook('triggered', Colors.green).label, 'TRIGGERED');
    expect(alarmLook('disarmed', Colors.green).color, Colors.green);
    expect(alarmLook(null, Colors.green).label, 'Unavailable');
  });

  test('callService says whether HA accepted it: a wrong alarm code is false', () async {
    final fake = FakeHa({
      'alarm_control_panel.home': st('alarm_control_panel.home', 'armed_away', {'code_format': 'number'}),
    });
    final states = HaStates();
    final conn = HaConnection(transportFactory: () async => fake, token: 'good', states: states);
    final ready = Completer<void>();
    conn.onReady = ready.complete;
    await conn.start();
    await ready.future.timeout(const Duration(seconds: 2));

    expect(
      await conn.callService('alarm_control_panel', 'alarm_disarm', {'entity_id': 'alarm_control_panel.home', 'code': '0000'}),
      isFalse,
    );
    expect(
      await conn.callService('alarm_control_panel', 'alarm_disarm', {'entity_id': 'alarm_control_panel.home', 'code': '1234'}),
      isTrue,
    );
    await conn.dispose();
  });
}
