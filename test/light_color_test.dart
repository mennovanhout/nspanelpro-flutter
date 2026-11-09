import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nspanel_app/cards/env.dart';
import 'package:nspanel_app/cards/light_color.dart';
import 'package:nspanel_app/cards/light_card.dart';
import 'package:nspanel_app/cards/light_sheet.dart';
import 'package:nspanel_app/cards/switch_card.dart';
import 'package:nspanel_app/config/settings.dart';
import 'package:nspanel_app/ha/connection.dart';
import 'package:nspanel_app/ha/states.dart';
import 'package:nspanel_app/ui/light_track.dart';
import 'package:nspanel_app/ui/sheet.dart';
import 'package:nspanel_app/ui/theme.dart';

import 'connection_test.dart' show st;
import 'service_ha.dart' show ServiceHa;

const attrs = <String, dynamic>{
  'supported_color_modes': ['rgb', 'color_temp'],
  'color_mode': 'hs',
  'hs_color': [180, 40],
  'brightness': 128,
  'min_color_temp_kelvin': 2000,
  'max_color_temp_kelvin': 6500,
  'color_temp_kelvin': 3000,
  'supported_features': 4,
  'effect_list': ['Solid', 'Rainbow'],
  'effect': 'Solid',
};
const favorites = [
  {'effect': 'Solid'},
  {'effect': 'Rainbow', 'name': 'Regenbogen'},
  {'effect': 'Missing'},
];
Future<(ServiceHa, HaStates)> mount(
  WidgetTester t, {
  Map<String, dynamic> config = const {},
  String state = 'on',
  bool shortcut = false,
  bool lightCard = false,
}) async {
  t.view.physicalSize = const Size(480, 480);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  final fake = ServiceHa({
    'light.test': st('light.test', state, attrs),
    'switch.quick': st('switch.quick', 'off', {}),
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
  final env = PanelEnv(
    states: states,
    conn: conn,
    settings: Settings(url: 'http://fake', token: 'test'),
  );
  final c = {'entity': 'light.test', 'effect_favorites': favorites, ...config};
  await t.pumpWidget(
    MaterialApp(
      theme: Ns.theme(),
      home: Scaffold(
        body: shortcut
            ? SwitchCard(
                config: {
                  'entity': 'switch.quick',
                  'detail_entity': 'light.test',
                  ...config,
                },
                env: env,
              )
            : lightCard
            ? LightCard(config: c, env: env)
            : Builder(
                builder: (context) => TextButton(
                  onPressed: () => showControlSheetBuilder(
                    context,
                    (_) => LightSheet(config: c, env: env),
                  ),
                  child: const Text('Open'),
                ),
              ),
      ),
    ),
  );
  if (shortcut) {
    await t.longPress(find.byType(SwitchCard));
  } else if (lightCard) {
    await t.longPress(find.byType(LightCard));
  } else {
    await t.tap(find.text('Open'));
  }
  await t.pumpAndSettle();
  return (fake, states);
}

Finder track(String ch) =>
    find.byKey(ValueKey(ch == 'brightness' ? 'sheet-level' : 'light-$ch'));
LightTrack slider(WidgetTester t, String ch) => t.widget<LightTrack>(track(ch));
Future<void> at(WidgetTester t, String ch, double value) async {
  final r = t.getRect(track(ch));
  await t.tapAt(Offset(r.center.dx, r.top + r.height * (1 - value)));
  await t.pump();
}

Map<String, dynamic> last(ServiceHa f) =>
    f.sent.lastWhere((m) => m['type'] == 'call_service')['service_data']
        as Map<String, dynamic>;
void expectStableOpacity(WidgetTester t) {
  final sheet = find.byType(LightSheet);
  final opacity = find.descendant(of: sheet, matching: find.byType(Opacity));
  expect(t.widgetList<Opacity>(opacity).every((w) => w.opacity == 1), isTrue);
  expect(
    find.descendant(
      of: sheet,
      matching: find.byWidgetPredicate(
        (w) => w is ColoredBox && w.color == const Color(0x550B0D10),
      ),
    ),
    findsNothing,
  );
}

void main() {
  testWidgets(
    'reopening a real light card ignores its off/optimistic zero when showing history',
    (t) async {
      final (f, states) = await mount(
        t,
        lightCard: true,
        config: {'height': 444},
      );
      states.update(
        'light.test',
        HaState(
          entityId: 'light.test',
          state: 'off',
          attributes: {
            ...attrs,
            'brightness': null,
            'hs_color': null,
            'color_mode': null,
          },
        ),
      );
      await t.pumpAndSettle();
      await t.tap(find.byIcon(Icons.close));
      await t.pumpAndSettle();
      await t.longPress(find.byType(LightCard));
      await t.pumpAndSettle();
      expect(slider(t, 'brightness').value, 128 / 255);
      expect(find.text('Off · last values'), findsOneWidget);
      expect(f.calls, isEmpty);
    },
  );

  testWidgets(
    'off details recall confirmed values, mark history, retain plain turn on',
    (t) async {
      final (f, states) = await mount(t, config: {'step_target': 'last_used'});
      Color powerColor(String label) => t
          .widget<SheetButton>(
            find.ancestor(
              of: find.text(label),
              matching: find.byType(SheetButton),
            ),
          )
          .color;
      final onColor = powerColor('Turn off');
      expect(onColor.g, greaterThan(onColor.r));
      expect(onColor.b, onColor.g);
      states.update(
        'light.test',
        HaState(
          entityId: 'light.test',
          state: 'off',
          attributes: {
            ...attrs,
            'brightness': null,
            'hs_color': null,
            'color_mode': null,
            'color_temp_kelvin': null,
            'effect': null,
          },
        ),
      );
      await t.pumpAndSettle();
      expect(powerColor('Turn on'), Ns.surface);
      expect(t.widget<Text>(find.text('Turn on')).style?.color, Ns.text);
      expect(find.text('Off · last values'), findsOneWidget);
      expect(slider(t, 'brightness').value, 128 / 255);
      expect(slider(t, 'hue').value, .5);
      expect(slider(t, 'saturation').value, .4);
      await t.tap(find.text('Effects'));
      await t.pumpAndSettle();
      final solid = t.widget<SheetButton>(
        find.ancestor(
          of: find.text('Solid'),
          matching: find.byType(SheetButton),
        ),
      );
      expect(solid.selected, isTrue);
      expect(solid.onTap, isNotNull);
      await t.tap(find.text('Back'));
      await t.pumpAndSettle();
      expect(f.calls, isEmpty);
      await t.tap(find.text('Turn on'));
      await t.pumpAndSettle();
      expect(f.calls.single, startsWith('light.turn_on '));
      expect(last(f), {'entity_id': 'light.test'});
    },
  );

  testWidgets(
    'power uses on-state TW tint and neutral off action despite remembered values',
    (t) async {
      final (f, states) = await mount(t);
      Color powerColor() => t
          .widget<SheetButton>(
            find.ancestor(
              of: find.text('Turn on'),
              matching: find.byType(SheetButton),
            ),
          )
          .color;
      states.update(
        'light.test',
        HaState(
          entityId: 'light.test',
          state: 'on',
          attributes: {
            ...attrs,
            'color_mode': 'color_temp',
            'color_temp_kelvin': 4000,
          },
        ),
      );
      await t.pumpAndSettle();
      final warm = t
          .widget<SheetButton>(
            find.ancestor(
              of: find.text('Turn off'),
              matching: find.byType(SheetButton),
            ),
          )
          .color;
      states.update(
        'light.test',
        HaState(
          entityId: 'light.test',
          state: 'off',
          attributes: {
            ...attrs,
            'brightness': null,
            'color_mode': null,
            'color_temp_kelvin': null,
            'hs_color': null,
          },
        ),
      );
      await t.pumpAndSettle();
      expect(warm, isNot(Ns.amber));
      expect(warm.r, greaterThan(warm.b));
      expect(powerColor(), Ns.surface);
      expect(f.calls, isEmpty);
    },
  );

  for (final config in [
    {'accent': '#12abcd'},
    {'follow_color': false},
  ]) {
    testWidgets('power preview respects $config', (t) async {
      final (_, states) = await mount(t, config: config);
      final button = t.widget<SheetButton>(
        find.ancestor(
          of: find.text('Turn off'),
          matching: find.byType(SheetButton),
        ),
      );
      expect(
        button.color,
        config.containsKey('accent') ? const Color(0xff12abcd) : Ns.amber,
      );
      states.update(
        'light.test',
        HaState(entityId: 'light.test', state: 'off', attributes: attrs),
      );
      await t.pumpAndSettle();
      final off = t.widget<SheetButton>(
        find.ancestor(
          of: find.text('Turn on'),
          matching: find.byType(SheetButton),
        ),
      );
      expect(off.color, Ns.surface);
    });
  }

  testWidgets(
    'off failed edit rolls back to remembered value; acknowledgement does not learn draft',
    (t) async {
      final (f, states) = await mount(t);
      states.update(
        'light.test',
        HaState(
          entityId: 'light.test',
          state: 'off',
          attributes: {
            ...attrs,
            'brightness': null,
            'hs_color': null,
            'effect': null,
          },
        ),
      );
      await t.pumpAndSettle();
      f.refuses = true;
      await at(t, 'brightness', .8);
      await t.pumpAndSettle();
      expect(slider(t, 'brightness').value, 128 / 255);
      expect(
        states.lightMemory.resolve('light.test', 'off', {})['brightness'],
        128,
      );
      f.refuses = false;
      await at(t, 'brightness', .8);
      await t.pumpAndSettle();
      expect(
        states.lightMemory.resolve('light.test', 'off', {})['brightness'],
        128,
      );
      await t.pump(const Duration(seconds: 2));
      expect(slider(t, 'brightness').value, 128 / 255);
    },
  );

  testWidgets(
    'off temperature mode and last values remain subordinate to live capabilities',
    (t) async {
      final (_, states) = await mount(t);
      states.update(
        'light.test',
        HaState(
          entityId: 'light.test',
          state: 'on',
          attributes: {
            ...attrs,
            'color_mode': 'color_temp',
            'color_temp_kelvin': 4000,
          },
        ),
      );
      states.update(
        'light.test',
        HaState(
          entityId: 'light.test',
          state: 'off',
          attributes: {
            ...attrs,
            'color_mode': null,
            'color_temp_kelvin': null,
            'brightness': null,
          },
        ),
      );
      await t.pumpAndSettle();
      expect(slider(t, 'temperature').value, (4000 - 2000) / 4500);
      states.update(
        'light.test',
        HaState(
          entityId: 'light.test',
          state: 'off',
          attributes: {
            'supported_color_modes': ['onoff'],
          },
        ),
      );
      await t.pumpAndSettle();
      expect(find.byType(LightTrack), findsNothing);
      expect(t.widget<ControlSheet>(find.byType(ControlSheet)).state, 'Off');
    },
  );

  for (final c in jsonDecode(
    File('test/fixtures/light-color.json').readAsStringSync(),
  ) as List) {
    test(c['name'] as String, () {
      final p = LightColor(
        HaState.fromJson((c['state'] as Map).cast<String, dynamic>()),
      );
      expect(p.white, c['white']);
      expect(p.color, c['color']);
      expect(p.range == null ? null : [p.range!.min, p.range!.max], c['range']);
      for (final e in (c['values'] as Map).entries) {
        expect(
          p.value(LightChannel.values.byName(e.key as String)),
          closeTo((e.value as num).toDouble(), .00001),
        );
      }
    });
  }
  testWidgets('RGB targets and unlabelled geometry with brightness default', (
    t,
  ) async {
    final (f, _) = await mount(t);
    expect(t.getSize(track('hue')).height, 308);
    expect(t.getSize(track('hue')).width, closeTo(103.333, .01));
    expect(
      t.getSize(find.byKey(const ValueKey('sheet-increase'))),
      const Size(96, 147),
    );
    expect(find.text('hue'), findsNothing);
    expect(find.textContaining('kelvin'), findsNothing);
    await at(t, 'hue', .75);
    expect(last(f), {
      'entity_id': 'light.test',
      'hs_color': [270, 40],
    });
    await t.tap(find.byKey(const ValueKey('sheet-increase')));
    await t.pump();
    expect(last(f), {'entity_id': 'light.test', 'brightness_pct': 55});
    expect(t.takeException(), isNull);
  });
  testWidgets('last used survives browsing but resets on mode and reopen', (
    t,
  ) async {
    final (f, _) = await mount(t, config: {'step_target': 'last_used'});
    expect(slider(t, 'brightness').active, true);
    await at(t, 'hue', .99);
    await t.tap(find.text('Presets'));
    await t.pump();
    await t.tap(find.text('Back'));
    await t.pump();
    expect(slider(t, 'hue').active, true);
    await t.tap(find.byKey(const ValueKey('sheet-increase')));
    await t.pump();
    expect((last(f)['hs_color'] as List).first, 14);
    await t.tap(find.text('White'));
    await t.pump();
    expect(slider(t, 'brightness').active, true);
    expect(t.getSize(track('temperature')), const Size(162, 308));
    await at(t, 'temperature', .5);
    expect(last(f), {'entity_id': 'light.test', 'color_temp_kelvin': 4250});
    await t.tap(find.byKey(const ValueKey('sheet-increase')));
    await t.pump();
    expect(last(f)['color_temp_kelvin'], 4475);
    await t.tap(find.byIcon(Icons.close));
    await t.pumpAndSettle();
    await t.tap(find.text('Open'));
    await t.pumpAndSettle();
    expect(slider(t, 'brightness').active, true);
  });
  testWidgets('drag previews, sends only on release; cancel does not select', (
    t,
  ) async {
    final (f, _) = await mount(t, config: {'step_target': 'last_used'});
    var g = await t.startGesture(t.getCenter(track('saturation')));
    await g.moveBy(const Offset(0, -70));
    await t.pump();
    expect(f.calls, isEmpty);
    expect(slider(t, 'brightness').enabled, false);
    expectStableOpacity(t);
    await g.cancel();
    await t.pump();
    expect(f.calls, isEmpty);
    expect(slider(t, 'brightness').active, true);
    g = await t.startGesture(t.getCenter(track('saturation')));
    await g.moveBy(const Offset(0, -70));
    await t.pump();
    await g.up();
    await t.pump();
    expect(f.calls.length, 1);
    expect(slider(t, 'saturation').active, true);
    expect(last(f).keys, unorderedEquals(['entity_id', 'hs_color']));
  });
  testWidgets('pending is locked, rejection rolls back, timeout allows retry', (
    t,
  ) async {
    final (f, _) = await mount(t);
    f.delay = true;
    await at(t, 'hue', .75);
    expect(slider(t, 'hue').enabled, false);
    expectStableOpacity(t);
    await t.pump(const Duration(seconds: 2));
    expect(slider(t, 'hue').value, .75);
    await t.tap(find.byKey(const ValueKey('sheet-increase')));
    await t.pump();
    expect(f.calls.length, 1);
    f.refuses = true;
    f.respond(f.sent.last['id'] as int);
    await t.pump();
    await t.pump();
    expect(find.text('On · Command failed'), findsOneWidget);
    expect(slider(t, 'hue').value, .5);
    await at(t, 'hue', .25);
    await t.pump(const Duration(seconds: 11));
    await t.pump();
    expect(find.text('On · No response'), findsOneWidget);
    expect(slider(t, 'hue').enabled, true);
    f.refuses = false;
    f.delay = false;
    await at(t, 'hue', .2);
    expect(f.calls.length, 3);
  });
  testWidgets(
    'effects selected, unsupported disabled; color on off omits brightness',
    (t) async {
      final (f, _) = await mount(t, state: 'off');
      await at(t, 'hue', .25);
      expect(last(f), {
        'entity_id': 'light.test',
        'hs_color': [90, 40],
      });
      await t.tap(find.text('Effects'));
      await t.pump();
      await t.tap(find.text('Missing'));
      await t.pump();
      expect(f.calls.length, 1);
      await t.tap(find.text('Regenbogen'));
      await t.pumpAndSettle();
      expect(last(f), {'entity_id': 'light.test', 'effect': 'Rainbow'});
      expect(find.byType(LightSheet), findsNothing);
    },
  );
  testWidgets('selected effect stays visible and follows confirmed state', (
    t,
  ) async {
    final (f, states) = await mount(t);
    await t.tap(find.text('Effects'));
    await t.pump();
    Finder button(String label) =>
        find.ancestor(of: find.text(label), matching: find.byType(SheetButton));
    final selected = button('Solid');
    expect(t.widget<SheetButton>(selected).selected, true);
    expect(
      t
          .widget<Opacity>(
            find.descendant(of: selected, matching: find.byType(Opacity)),
          )
          .opacity,
      1,
    );
    final container = t.widget<Container>(
      find.descendant(of: selected, matching: find.byType(Container)).first,
    );
    final border =
        (container.foregroundDecoration! as BoxDecoration).border! as Border;
    expect(border.top.color, Ns.text);
    expect(border.top.width, 2);
    expect(t.getSize(selected), const Size(220, 76));
    await t.tap(find.text('Solid'));
    await t.pump();
    expect(f.calls, isEmpty);
    expect(
      t
          .widget<Opacity>(
            find.descendant(
              of: button('Missing'),
              matching: find.byType(Opacity),
            ),
          )
          .opacity,
      .35,
    );
    states.update(
      'light.test',
      HaState(
        entityId: 'light.test',
        state: 'on',
        attributes: {...attrs, 'effect': 'Rainbow'},
      ),
    );
    await t.pump();
    expect(t.widget<SheetButton>(button('Solid')).selected, false);
    expect(t.widget<SheetButton>(button('Regenbogen')).selected, true);
  });
  testWidgets('target-only updates, capability fallback, no hidden sends', (
    t,
  ) async {
    final (f, states) = await mount(
      t,
      shortcut: true,
      config: {'step_target': 'last_used'},
    );
    await at(t, 'saturation', .2);
    expect(last(f)['entity_id'], 'light.test');
    states.update(
      'light.test',
      HaState(
        entityId: 'light.test',
        state: 'on',
        attributes: {
          'supported_color_modes': ['brightness'],
          'brightness': 51,
        },
      ),
    );
    await t.pump();
    expect(track('saturation'), findsNothing);
    expect(slider(t, 'brightness').active, true);
    await t.tap(find.byKey(const ValueKey('sheet-increase')));
    await t.pump();
    expect(last(f)['brightness_pct'], 25);
    states.update(
      'light.test',
      HaState(entityId: 'light.test', state: 'unavailable', attributes: attrs),
    );
    await t.pump();
    await at(t, 'hue', .3);
    expect(f.calls.length, 2);
  });
  testWidgets('brightness drag preserves white target fill', (t) async {
    final (_, states) = await mount(t);
    states.update(
      'light.test',
      HaState(
        entityId: 'light.test',
        state: 'on',
        attributes: {...attrs, 'color_mode': 'color_temp'},
      ),
    );
    await t.pump();
    final color = slider(t, 'brightness').color;
    final g = await t.startGesture(t.getCenter(track('brightness')));
    await g.moveBy(const Offset(0, -50));
    await t.pump();
    expect(slider(t, 'brightness').color, color);
    await g.cancel();
    await t.pump();
  });
}
