import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nspanel_app/cards/env.dart';
import 'package:nspanel_app/cards/light_sheet.dart';
import 'package:nspanel_app/cards/switch_card.dart';
import 'package:nspanel_app/config/settings.dart';
import 'package:nspanel_app/ha/connection.dart';
import 'package:nspanel_app/ha/states.dart';
import 'package:nspanel_app/ui/sheet.dart';
import 'package:nspanel_app/ui/theme.dart';

import 'connection_test.dart' show FakeHa, st;

Future<(FakeHa, HaStates)> mountTarget(
  WidgetTester t, {
  Map<String, dynamic> config = const {},
  Map<String, Map<String, dynamic>> targets = const {},
  ValueNotifier<Map<String, dynamic>>? updates,
}) async {
  t.view.physicalSize = const Size(480, 480);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  final fake = FakeHa({
    'switch.primary': st('switch.primary', 'off', {'friendly_name': 'Primary'}),
    ...targets,
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
  addTearDown(() => unawaited(conn.dispose()));
  final configs = updates ?? ValueNotifier(config);
  if (updates == null) addTearDown(configs.dispose);
  await t.pumpWidget(
    MaterialApp(
      theme: Ns.theme(),
      home: Scaffold(
        body: PageView(
          children: [
            Align(
              alignment: Alignment.topCenter,
              child: ValueListenableBuilder<Map<String, dynamic>>(
                valueListenable: configs,
                builder: (_, value, _) => SwitchCard(
                  config: {'entity': 'switch.primary', 'height': 160, ...value},
                  env: PanelEnv(
                    states: states,
                    conn: conn,
                    settings: Settings(url: 'http://fake', token: 'test'),
                  ),
                ),
              ),
            ),
            const Center(child: Text('Next page')),
          ],
        ),
      ),
    ),
  );
  await t.pump();
  return (fake, states);
}

Future<void> openTarget(WidgetTester t) async {
  await t.longPress(find.text('Primary'));
  await t.pumpAndSettle();
  expect(find.byType(ControlSheet), findsOneWidget);
}

Future<void> closeTarget(WidgetTester t) async {
  await t.tap(find.byIcon(Icons.close));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('HA config replaces cached detail bindings without restart', (
    t,
  ) async {
    final config = ValueNotifier<Map<String, dynamic>>({});
    addTearDown(config.dispose);
    final (fake, _) = await mountTarget(
      t,
      updates: config,
      targets: {
        'light.detail': st('light.detail', 'off', {
          'supported_color_modes': ['onoff'],
        }),
      },
    );
    await openTarget(t);
    expect(find.byType(LightSheet), findsNothing);
    await closeTarget(t);
    config.value = {
      'switches': [
        {'entity': 'switch.primary', 'detail_entity': 'light.detail'},
      ],
    };
    await t.pump();
    await openTarget(t);
    expect(find.byType(LightSheet), findsOneWidget);
    await closeTarget(t);
    config.value = {'entity': 'switch.primary'};
    await t.pump();
    await openTarget(t);
    expect(find.byType(LightSheet), findsNothing);
    expect(fake.calls, isEmpty);
  });

  testWidgets('updated tile entity replaces old handlers and pending echo', (
    t,
  ) async {
    final config = ValueNotifier<Map<String, dynamic>>({});
    addTearDown(config.dispose);
    final (fake, _) = await mountTarget(
      t,
      updates: config,
      targets: {
        'input_boolean.secondary': st('input_boolean.secondary', 'off', {
          'friendly_name': 'Secondary',
        }),
      },
    );
    await t.tap(find.text('Primary'));
    await t.pump();
    expect(find.text('On'), findsOneWidget);
    config.value = {'entity': 'input_boolean.secondary'};
    await t.pump();
    expect(find.text('Primary'), findsNothing);
    expect(find.text('Off'), findsOneWidget);
    await t.tap(find.text('Secondary'));
    await t.pump();
    expect(fake.calls, [
      'homeassistant.turn_on {"entity_id":"switch.primary"}',
      'homeassistant.turn_on {"entity_id":"input_boolean.secondary"}',
    ]);
    await t.pump(const Duration(seconds: 2));
    expect(t.takeException(), isNull);
  });

  for (final grid in [false, true]) {
    testWidgets(
      'detail target selects light dialog, tap keeps primary (grid=$grid)',
      (t) async {
        final item = {
          'entity': 'switch.primary',
          'detail_entity': ' light.detail ',
        };
        final (fake, _) = await mountTarget(
          t,
          config: grid
              ? {
                  'switches': [item],
                }
              : item,
          targets: {
            'light.detail': st('light.detail', 'off', {
              'supported_color_modes': ['onoff'],
            }),
          },
        );
        await openTarget(t);
        expect(find.byType(LightSheet), findsOneWidget);
        expect(fake.calls, isEmpty);
        await closeTarget(t);
        expect(fake.calls, isEmpty);
        await openTarget(t);
        await t.tap(find.text('Turn on'));
        await t.pumpAndSettle();
        expect(fake.calls, ['light.turn_on {"entity_id":"light.detail"}']);
        // Target is now on, but the primary switch remains off.
        expect(find.text('Off'), findsOneWidget);
        await t.tap(find.text('Primary'));
        await t.pump();
        expect(
          fake.calls.last,
          'homeassistant.turn_on {"entity_id":"switch.primary"}',
        );
        await t.pump(const Duration(seconds: 2));
      },
    );
  }

  testWidgets(
    'missing detail entity stays unavailable and never operates primary',
    (t) async {
      final (fake, _) = await mountTarget(
        t,
        config: {'detail_entity': 'light.missing'},
      );
      await openTarget(t);
      expect(
        t.widget<ControlSheet>(find.byType(ControlSheet)).actions.last.enabled,
        isFalse,
      );
      await t.tap(find.text('Turn on'));
      await t.pump();
      await closeTarget(t);
      expect(fake.calls, isEmpty);
    },
  );

  testWidgets(
    'detail availability follows target state independently of primary',
    (t) async {
      final (fake, states) = await mountTarget(
        t,
        config: {'detail_entity': 'light.detail'},
        targets: {
          'light.detail': st('light.detail', 'unavailable', {
            'supported_color_modes': ['onoff'],
          }),
        },
      );
      await openTarget(t);
      expect(
        t.widget<ControlSheet>(find.byType(ControlSheet)).actions.last.enabled,
        isFalse,
      );
      states.update(
        'light.detail',
        const HaState(
          entityId: 'light.detail',
          state: 'on',
          attributes: {
            'supported_color_modes': ['onoff'],
          },
        ),
      );
      await t.pump();
      expect(
        t.widget<ControlSheet>(find.byType(ControlSheet)).actions.last.enabled,
        isTrue,
      );
      expect(find.text('Turn off'), findsOneWidget);
      expect(fake.calls, isEmpty);
    },
  );

  testWidgets('other detail domains remain read-only', (t) async {
    final (fake, _) = await mountTarget(
      t,
      config: {'detail_entity': 'sensor.detail'},
      targets: {'sensor.detail': st('sensor.detail', '42', {})},
    );
    await openTarget(t);
    final sheet = t.widget<ControlSheet>(find.byType(ControlSheet));
    expect(sheet.state, '42');
    expect(sheet.actions, isEmpty);
    expect(fake.calls, isEmpty);
  });

  testWidgets(
    'disabled detail target holds and pager swipes send no services',
    (t) async {
      final (fake, _) = await mountTarget(
        t,
        config: {'detail_entity': 'light.detail', 'more_info': false},
      );
      await t.longPress(find.text('Primary'));
      await t.pumpAndSettle();
      expect(find.byType(ControlSheet), findsNothing);
      await t.drag(find.text('Primary'), const Offset(-420, 0));
      await t.pumpAndSettle();
      expect(find.text('Next page').hitTestable(), findsOneWidget);
      expect(fake.calls, isEmpty);
    },
  );

  for (final target in ['', '   ', 12]) {
    testWidgets('invalid optional detail target uses primary ($target)', (
      t,
    ) async {
      final (fake, _) = await mountTarget(t, config: {'detail_entity': target});
      await openTarget(t);
      await t.tap(find.text('Turn on'));
      await t.pumpAndSettle();
      expect(fake.calls, [
        'homeassistant.turn_on {"entity_id":"switch.primary"}',
      ]);
    });
  }
}
