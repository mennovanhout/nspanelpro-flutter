import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nspanel_app/cards/env.dart';
import 'package:nspanel_app/cards/switch_card.dart';
import 'package:nspanel_app/config/settings.dart';
import 'package:nspanel_app/ha/connection.dart';
import 'package:nspanel_app/ha/states.dart';
import 'package:nspanel_app/ui/sheet.dart';
import 'package:nspanel_app/ui/theme.dart';

import 'connection_test.dart' show FakeHa, st;

/// Refuse services through the real websocket result path, without updating state.
class RefusingHa extends FakeHa {
  RefusingHa(super.states) {
    super.messages.listen(_results.add);
  }
  final _results = StreamController<String>();
  @override
  Stream<String> get messages => _results.stream;
  @override
  void send(String data) {
    final msg = jsonDecode(data) as Map<String, dynamic>;
    if (msg['type'] != 'call_service') {
      super.send(data);
      return;
    }
    sent.add(msg);
    calls.add(
      '${msg['domain']}.${msg['service']} ${jsonEncode(msg['service_data'])}',
    );
    _results.add(
      jsonEncode({
        'id': msg['id'],
        'type': 'result',
        'success': false,
        'error': {'code': 'test_refusal', 'message': 'Service refused'},
      }),
    );
  }

  @override
  Future<void> close() async {
    await super.close();
    await _results.close();
  }
}

Future<(FakeHa, HaStates)> mount(
  WidgetTester tester, {
  String entity = 'switch.test',
  String state = 'off',
  Map<String, dynamic> attributes = const {},
  Map<String, dynamic> config = const {},
  bool refuses = false,
}) async {
  tester.view.physicalSize = const Size(480, 480);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final seed = {
    entity: st(entity, state, {'friendly_name': 'Test entity', ...attributes}),
  };
  final fake = refuses ? RefusingHa(seed) : FakeHa(seed);
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
        body: PageView(
          children: [
            Align(
              alignment: Alignment.topCenter,
              child: SwitchCard(
                config: {'entity': entity, 'height': 160, ...config},
                env: PanelEnv(
                  states: states,
                  conn: conn,
                  settings: Settings(url: 'http://fake', token: 'test'),
                ),
              ),
            ),
            const Center(child: Text('Next page')),
          ],
        ),
      ),
    ),
  );
  await tester.pump();
  return (fake, states);
}

Future<void> open(WidgetTester tester) async {
  await tester.longPress(find.text('Test entity'));
  await tester.pump(const Duration(milliseconds: 250));
  expect(find.byType(ControlSheet), findsOneWidget);
}

void main() {
  for (final domain in ['switch', 'input_boolean', 'fan', 'light']) {
    testWidgets(
      '$domain: hold and close never toggle; explicit action sends one command',
      (tester) async {
        final (fake, _) = await mount(
          tester,
          entity: '$domain.test',
          attributes: {
            'supported_color_modes': ['onoff'],
          },
        );
        await open(tester);
        expect(fake.calls, isEmpty);
        expect(find.byIcon(Icons.add), findsNothing);
        await tester.tap(find.byIcon(Icons.close));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        expect(fake.calls, isEmpty);
        await open(tester);
        await tester.tap(find.text('Turn on'));
        await tester.pump();
        expect(fake.calls, [
          '${domain == 'light' ? 'light' : 'homeassistant'}.turn_on {"entity_id":"$domain.test"}',
        ]);
        await tester.pump(const Duration(milliseconds: 250));
      },
    );
  }

  testWidgets(
    'short tap still uses the immediate echo and one explicit service',
    (tester) async {
      final (fake, _) = await mount(tester);
      await tester.tap(find.text('Test entity'));
      await tester.pump();
      expect(find.text('On'), findsOneWidget);
      expect(find.byType(ControlSheet), findsNothing);
      expect(fake.calls, ['homeassistant.turn_on {"entity_id":"switch.test"}']);
      await tester.pump(const Duration(seconds: 2));
    },
  );

  testWidgets('more_info false consumes a hold but still allows a short tap', (
    tester,
  ) async {
    final (fake, _) = await mount(tester, config: {'more_info': false});
    await tester.longPress(find.text('Test entity'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byType(ControlSheet), findsNothing);
    expect(fake.calls, isEmpty);
    await tester.tap(find.text('Test entity'));
    await tester.pump();
    expect(fake.calls.length, 1);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('horizontal swipe over a tile belongs to the pager', (
    tester,
  ) async {
    final (fake, _) = await mount(tester);
    await tester.drag(find.text('Test entity'), const Offset(-420, 0));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Next page').hitTestable(), findsOneWidget);
    expect(find.byType(ControlSheet), findsNothing);
    expect(fake.calls, isEmpty);
  });

  testWidgets(
    'cancelled touches before and after the hold timeout never toggle',
    (tester) async {
      final (fake, _) = await mount(tester);
      final first = await tester.startGesture(
        tester.getCenter(find.text('Test entity')),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await first.cancel();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(ControlSheet), findsNothing);
      final second = await tester.startGesture(
        tester.getCenter(find.text('Test entity')),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await second.cancel();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byType(ControlSheet), findsOneWidget);
      expect(fake.calls, isEmpty);
    },
  );

  testWidgets(
    'details follow live state, disable unavailable actions and recover',
    (tester) async {
      final (fake, states) = await mount(tester);
      await open(tester);
      states.update(
        'switch.test',
        const HaState(entityId: 'switch.test', state: 'on', attributes: {}),
      );
      await tester.pump();
      expect(find.text('Turn off'), findsOneWidget);
      states.update(
        'switch.test',
        const HaState(
          entityId: 'switch.test',
          state: 'unavailable',
          attributes: {},
        ),
      );
      await tester.pump();
      expect(
        tester.widget<ControlSheet>(find.byType(ControlSheet)).enabled,
        isFalse,
      );
      await tester.tap(find.text('Turn on'));
      await tester.pump();
      expect(fake.calls, isEmpty);
      states.update(
        'switch.test',
        const HaState(entityId: 'switch.test', state: 'off', attributes: {}),
      );
      await tester.pump();
      expect(
        tester.widget<ControlSheet>(find.byType(ControlSheet)).enabled,
        isTrue,
      );
    },
  );

  for (final state in ['unavailable', 'unknown']) {
    testWidgets('$state: inspectable without actionable controls', (
      tester,
    ) async {
      final (fake, _) = await mount(tester, state: state);
      await tester.tap(find.text('Test entity'));
      await tester.pump();
      await open(tester);
      await tester.tap(find.text('Turn on'));
      await tester.pump();
      expect(fake.calls, isEmpty);
      expect(
        tester.widget<ControlSheet>(find.byType(ControlSheet)).enabled,
        isFalse,
      );
    });
  }

  testWidgets('unsupported domain gets a read-only state', (tester) async {
    final (fake, _) = await mount(tester, entity: 'sensor.test', state: '42');
    await open(tester);
    final sheet = tester.widget<ControlSheet>(find.byType(ControlSheet));
    expect(sheet.state, '42');
    expect(sheet.actions, isEmpty);
    expect(sheet.showLevel, isFalse);
    expect(fake.calls, isEmpty);
  });

  testWidgets(
    'dimmable light details retain controls while off and react to capability loss',
    (tester) async {
      final (fake, states) = await mount(
        tester,
        entity: 'light.test',
        attributes: {
          'supported_color_modes': ['rgb'],
        },
      );
      await open(tester);
      expect(find.byIcon(Icons.add), findsOneWidget);
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
      expect(find.byIcon(Icons.add), findsNothing);
      expect(find.text('Mid'), findsNothing);
      expect(fake.calls, isEmpty);
    },
  );

  testWidgets(
    'HA rejection keeps details open with an error; short-tap echo rolls back',
    (tester) async {
      final (fake, _) = await mount(tester, refuses: true);
      await open(tester);
      await tester.tap(find.text('Turn on'));
      await tester.pump();
      expect(find.byType(ControlSheet), findsOneWidget);
      expect(
        tester.widget<ControlSheet>(find.byType(ControlSheet)).state,
        contains('Command failed'),
      );
      expect(find.text('Turn off'), findsNothing);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      await tester.tap(find.text('Test entity'));
      await tester.pump();
      expect(find.text('Off'), findsOneWidget);
      expect(fake.calls.length, 2);
      await tester.pump(const Duration(seconds: 2));
      expect(tester.takeException(), isNull);
    },
  );
}
