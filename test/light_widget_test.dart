import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nspanel_app/cards/env.dart';
import 'package:nspanel_app/cards/light_card.dart';
import 'package:nspanel_app/config/settings.dart';
import 'package:nspanel_app/ha/connection.dart';
import 'package:nspanel_app/ha/states.dart';
import 'package:nspanel_app/ui/fill_card.dart';
import 'package:nspanel_app/ui/sheet.dart';
import 'package:nspanel_app/ui/theme.dart';

import 'connection_test.dart' show FakeHa, st;

Future<(FakeHa, HaStates)> mount(
  WidgetTester tester,
  List<String> modes, {
  Map<String, dynamic> config = const {},
}) async {
  tester.view.physicalSize = const Size(480, 480);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final fake = FakeHa({
    'light.test': st('light.test', 'on', {
      'friendly_name': 'Test light',
      'supported_color_modes': modes,
      'brightness': 128,
    }),
  });
  final states = HaStates();
  final conn = HaConnection(
    transportFactory: () async => fake,
    token: 'good',
    states: states,
  );
  final ready = Completer<void>();
  conn.onReady = ready.complete;
  await conn.start();
  await ready.future;
  addTearDown(() {
    unawaited(conn.dispose());
  });
  await tester.pumpWidget(
    MaterialApp(
      theme: Ns.theme(),
      home: Scaffold(
        body: LightCard(
          config: {'entity': 'light.test', 'height': 260, ...config},
          env: PanelEnv(
            states: states,
            conn: conn,
            settings: Settings(url: 'http://fake', token: 'test'),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return (fake, states);
}

void main() {
  testWidgets(
    'opening details preserves the card echo over a stale HA update',
    (tester) async {
      final (_, states) = await mount(tester, ['brightness']);
      await tester.tap(find.text('Mid'));
      await tester.pump();
      states.update(
        'light.test',
        const HaState(
          entityId: 'light.test',
          state: 'on',
          attributes: {
            'supported_color_modes': ['brightness'],
            'brightness': 25,
            'friendly_name': 'Test light',
          },
        ),
      );
      await tester.pump();
      await tester.longPress(find.text('Test light'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(tester.widget<ControlSheet>(find.byType(ControlSheet)).value, 0.5);
    },
  );

  testWidgets('onoff: no level controls; hold and vertical drag never toggle', (
    tester,
  ) async {
    final (fake, _) = await mount(tester, ['onoff']);
    expect(find.byType(ValueText), findsNothing);
    expect(find.text('Low'), findsNothing);
    await tester.drag(find.byType(FillCard), const Offset(0, -60));
    await tester.pump(const Duration(milliseconds: 200));
    expect(fake.calls, isEmpty);
    await tester.longPress(find.text('Test light'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(ControlSheet), findsOneWidget);
    expect(find.byIcon(Icons.add), findsNothing);
    expect(fake.calls, isEmpty);
    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(fake.calls, isEmpty);
    await tester.tap(find.text('Test light'));
    await tester.pump();
    expect(fake.calls, ['light.toggle {"entity_id":"light.test"}']);
  });

  testWidgets('dialog follows external updates and disables stale actions', (
    tester,
  ) async {
    final (fake, states) = await mount(tester, ['onoff']);
    await tester.longPress(find.text('Test light'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Turn off'), findsOneWidget);
    states.update(
      'light.test',
      const HaState(
        entityId: 'light.test',
        state: 'off',
        attributes: {
          'supported_color_modes': ['onoff'],
        },
      ),
    );
    await tester.pump();
    expect(find.text('Turn on'), findsOneWidget);
    states.update(
      'light.test',
      const HaState(
        entityId: 'light.test',
        state: 'unavailable',
        attributes: {
          'supported_color_modes': ['onoff'],
        },
      ),
    );
    await tester.pump();
    await tester.tap(find.text('Turn on'));
    await tester.pump();
    expect(fake.calls, isEmpty);
    expect(find.byType(ControlSheet), findsOneWidget);
    expect(find.text('Unavailable'), findsWidgets);
  });

  testWidgets('explicit incompatible presets do nothing; scene is preserved', (
    tester,
  ) async {
    final (fake, _) = await mount(
      tester,
      ['onoff'],
      config: {
        'presets': [
          {'name': 'Half', 'brightness_pct': 50},
          {'name': 'Evening', 'scene': 'scene.evening'},
        ],
      },
    );
    await tester.tap(find.text('Half'));
    await tester.pump();
    expect(fake.calls, isEmpty);
    await tester.tap(find.text('Evening'));
    await tester.pump();
    expect(fake.calls, ['scene.turn_on {"entity_id":"scene.evening"}']);
  });

  testWidgets(
    'dimmer sheet sends only on release and follows capability loss',
    (tester) async {
      final (fake, states) = await mount(tester, ['brightness']);
      await tester.longPress(find.text('Test light'));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byIcon(Icons.add), findsOneWidget);
      final gesture = await tester.startGesture(const Offset(120, 250));
      await gesture.moveBy(const Offset(0, -40));
      await tester.pump();
      expect(fake.calls, isEmpty);
      await gesture.up();
      await tester.pump();
      expect(fake.calls.length, 1);
      expect(fake.calls.single, contains('brightness_pct'));
      fake.calls.clear();
      states.update(
        'light.test',
        const HaState(
          entityId: 'light.test',
          state: 'on',
          attributes: {
            'supported_color_modes': ['onoff'],
          },
        ),
      );
      await tester.pump();
      expect(find.byIcon(Icons.add), findsNothing);
      expect(find.text('Low'), findsNothing);
      expect(fake.calls, isEmpty);
    },
  );

  testWidgets('long_press none and horizontal swipes do not issue commands', (
    tester,
  ) async {
    final (fake, _) = await mount(
      tester,
      ['onoff'],
      config: {'long_press': 'none'},
    );
    await tester.longPress(find.text('Test light'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(ControlSheet), findsNothing);
    await tester.drag(find.byType(FillCard), const Offset(-100, 0));
    await tester.pump();
    expect(fake.calls, isEmpty);
  });

  testWidgets('cancelled slider drag never commits', (tester) async {
    final (fake, _) = await mount(tester, ['brightness']);
    await tester.longPress(find.text('Test light'));
    await tester.pump(const Duration(milliseconds: 200));
    final gesture = await tester.startGesture(const Offset(120, 250));
    await gesture.moveBy(const Offset(0, -50));
    await tester.pump();
    await gesture.cancel();
    await tester.pump();
    expect(fake.calls, isEmpty);
  });
  testWidgets('cancelled card drag never commits', (tester) async {
    final (fake, _) = await mount(tester, ['brightness']);
    final gesture = await tester.startGesture(const Offset(120, 100));
    await gesture.moveBy(const Offset(0, -50));
    await tester.pump();
    await gesture.cancel();
    await tester.pump();
    expect(fake.calls, isEmpty);
  });
}
