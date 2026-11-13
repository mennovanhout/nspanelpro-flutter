import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:nspanel_app/cards/env.dart';
import 'package:nspanel_app/cards/registry.dart';
import 'package:nspanel_app/config/settings.dart';
import 'package:nspanel_app/ha/connection.dart';
import 'package:nspanel_app/ha/states.dart';
import 'package:nspanel_app/ui/keypad.dart';
import 'package:nspanel_app/ui/sheet.dart';
import 'package:nspanel_app/util/text_scale.dart';

import 'connection_test.dart' show FakeHa, st;
import 'package:nspanel_app/l10n/strings.dart';

final _house = {
  'light.l': st('light.l', 'on', {
    'friendly_name': 'A rather long light name in the hallway',
    'brightness': 128,
    'supported_color_modes': ['brightness'],
  }),
  'cover.c': st('cover.c', 'open', {
    'friendly_name': 'Cover',
    'current_position': 40,
  }),
  'climate.c': st('climate.c', 'heat', {
    'friendly_name': 'Hall',
    'temperature': 21.5,
    'min_temp': 7,
    'max_temp': 35,
    'current_temperature': 20,
    'hvac_modes': ['off', 'heat'],
  }),
  'media_player.m': st('media_player.m', 'playing', {
    'friendly_name': 'Radio',
    'volume_level': .4,
    'media_title': 'A track with quite a long title to see what it does',
    'media_artist': 'Somebody',
    'supported_features': 16437,
  }),
  'script.s': st('script.s', 'off', {'friendly_name': 'Go'}),
  'switch.sw': st('switch.sw', 'on', {'friendly_name': 'Switch'}),
  'sensor.t': st('sensor.t', '21.5', {
    'friendly_name': 'Temperature',
    'unit_of_measurement': '°C',
  }),
  'binary_sensor.leak': st('binary_sensor.leak', 'on', {'friendly_name': 'Leak'}),
  'binary_sensor.door': st('binary_sensor.door', 'off', {'friendly_name': 'Door'}),
  'alarm_control_panel.a': st('alarm_control_panel.a', 'disarmed', {
    'friendly_name': 'Alarm',
    'code_format': 'number',
    'code_arm_required': false,
    'supported_features': 7,
  }),
  'weather.w': st('weather.w', 'rainy', {
    'friendly_name': 'Home',
    'temperature': 11.6,
    'temperature_unit': '°C',
    'humidity': 80,
    'wind_speed': 12,
    'wind_speed_unit': 'km/h',
  }),
};

Future<(FakeHa, PanelEnv, HaConnection)> _env() async {
  final fake = FakeHa({..._house});
  final states = HaStates();
  final conn = HaConnection(
    transportFactory: () async => fake,
    token: 'good',
    states: states,
  );
  final ready = Completer<void>();
  conn.onReady = ready.complete;
  await conn.start();
  await ready.future.timeout(const Duration(seconds: 2));
  final env = PanelEnv(
    states: states,
    conn: conn,
    settings: Settings(url: 'http://x', token: 't'),
  );
  return (fake, env, conn);
}

Widget _app(
  Map<String, dynamic> config,
  PanelEnv env, {
  double scale = 1,
  Strings strings = Strings.en,
}) => L(
  strings: ValueNotifier(strings),
  child: MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: PanelTextScaler(scale),
      ),
      child: child!,
    ),
    home: Scaffold(
      body: Center(child: SizedBox(width: 460, child: buildCard(config, env))),
    ),
  ),
);

void main() {
  testWidgets('alarm arm buttons fill their 60px row', (t) async {
    final (_, env, conn) = await _env();
    await t.pumpWidget(
      _app({
        'type': 'custom:nspanel-alarm-card',
        'entity': 'alarm_control_panel.a',
        'modes': ['away', 'night'],
      }, env),
    );
    await t.pump();
    final box = t.renderObject<RenderBox>(
      find.ancestor(of: find.text('Away'), matching: find.byType(GestureDetector)).first,
    );
    expect(box.size.height, 60);
    await t.pumpWidget(const SizedBox());
    unawaited(conn.dispose());
  });

  testWidgets('the sheet reads through format, and percent without one', (t) async {
    late BuildContext ctx;
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            ctx = c;
            return const SizedBox();
          },
        ),
      ),
    );
    unawaited(
      showControlSheet(
        ctx,
        title: 'T',
        state: 'S',
        value: .5,
        accent: Colors.red,
        format: (v) => '${(v * 10).toStringAsFixed(1)}°',
      ),
    );
    await t.pumpAndSettle();
    expect(find.text('5.0°'), findsOneWidget);
    expect(find.text('50%'), findsNothing);
    Navigator.of(ctx, rootNavigator: true).pop();
    await t.pumpAndSettle();
    unawaited(
      showControlSheet(ctx, title: 'T', state: 'S', value: .5, accent: Colors.red),
    );
    await t.pumpAndSettle();
    expect(find.text('50%'), findsOneWidget);
    Navigator.of(ctx, rootNavigator: true).pop();
    await t.pumpAndSettle();
  });

  testWidgets('climate sheet shows the target temperature', (t) async {
    final (_, env, conn) = await _env();
    await t.pumpWidget(
      _app({
        'type': 'custom:nspanel-climate-card',
        'entity': 'climate.c',
        'height': 220,
      }, env),
    );
    await t.pump();
    await t.longPress(find.text('Hall'));
    await t.pumpAndSettle();
    final inSheet = find.byType(ControlSheet);
    expect(find.descendant(of: inSheet, matching: find.text('21.5°')), findsOneWidget);
    expect(find.descendant(of: inSheet, matching: find.textContaining('%')), findsNothing);
    await t.pumpWidget(const SizedBox());
    unawaited(conn.dispose());
  });

  group('media tap and long_press', () {
    Future<(FakeHa, HaConnection)> pump(WidgetTester t, Map<String, dynamic> extra) async {
      final (fake, env, conn) = await _env();
      await t.pumpWidget(
        _app({
          'type': 'custom:nspanel-media-card',
          'entity': 'media_player.m',
          'height': 220,
          ...extra,
        }, env),
      );
      await t.pump();
      return (fake, conn);
    }

    bool sheetOpen() => find.byType(ControlSheet).evaluate().isNotEmpty;

    Future<void> finish(WidgetTester t, HaConnection conn) async {
      await t.pumpWidget(const SizedBox());
      unawaited(conn.dispose());
    }

    testWidgets('default: tap plays, hold opens the sheet', (t) async {
      final (fake, conn) = await pump(t, {});
      await t.tap(find.textContaining('A track with'));
      await t.pump(const Duration(milliseconds: 400));
      expect(fake.calls.last, startsWith('media_player.media_play_pause'));
      expect(sheetOpen(), isFalse);
      await t.longPress(find.textContaining('A track with'));
      await t.pumpAndSettle();
      expect(sheetOpen(), isTrue);
      await finish(t, conn);
    });

    testWidgets('more_info: true opens the sheet on tap', (t) async {
      final (fake, conn) = await pump(t, {'more_info': true});
      final before = fake.calls.length;
      await t.tap(find.textContaining('A track with'));
      await t.pumpAndSettle();
      expect(sheetOpen(), isTrue);
      expect(fake.calls.length, before);
      await finish(t, conn);
    });

    testWidgets('tap: none does nothing and beats more_info', (t) async {
      final (fake, conn) = await pump(t, {'tap': 'none', 'more_info': true});
      final before = fake.calls.length;
      await t.tap(find.textContaining('A track with'));
      await t.pumpAndSettle();
      expect(sheetOpen(), isFalse);
      expect(fake.calls.length, before);
      await finish(t, conn);
    });

    testWidgets('long_press: play_pause', (t) async {
      final (fake, conn) = await pump(t, {'long_press': 'play_pause'});
      await t.longPress(find.textContaining('A track with'));
      await t.pump(const Duration(milliseconds: 400));
      expect(fake.calls.last, startsWith('media_player.media_play_pause'));
      expect(sheetOpen(), isFalse);
      await finish(t, conn);
    });
  });

  testWidgets('feedback_ms 0 is no tick, per button or card', (t) async {
    final (fake, env, conn) = await _env();
    await t.pumpWidget(
      _app({
        'type': 'custom:nspanel-button-card',
        'height': 200,
        'buttons': [
          {'entity': 'script.s', 'name': 'None', 'icon': 'mdi:star', 'feedback_ms': 0},
          {'entity': 'script.s', 'name': 'Some', 'icon': 'mdi:star'},
        ],
      }, env),
    );
    await t.pump();
    int checks() => t
        .widgetList<Icon>(find.byType(Icon))
        .where((i) => i.icon == MdiIcons.check)
        .length;
    final before = fake.calls.length;
    await t.tap(find.text('None'));
    await t.pump();
    expect(fake.calls.length, before + 1, reason: 'the service still runs');
    expect(checks(), 0);
    await t.tap(find.text('Some'));
    await t.pump();
    expect(checks(), 1);
    await t.pump(const Duration(milliseconds: 1300));
    expect(checks(), 0);
    await t.pumpWidget(const SizedBox());
    unawaited(conn.dispose());
  });

  testWidgets('status colours show on a problem only', (t) async {
    final (_, env, conn) = await _env();
    await t.pumpWidget(
      _app({
        'type': 'custom:nspanel-status-card',
        'height': 200,
        'entities': [
          {'entity': 'binary_sensor.leak', 'color': 'ff5252', 'background': '#3a1010'},
          {'entity': 'binary_sensor.door', 'color': '#ffd166', 'background': '#112233'},
        ],
      }, env),
    );
    await t.pump();
    Text text(String s) => t.widget<Text>(find.text(s));
    Color? tile(String s) {
      final c = t.widget<Container>(
        find.ancestor(of: find.text(s), matching: find.byType(Container)).first,
      );
      return (c.decoration as BoxDecoration).color;
    }

    expect(text('Leak').style!.color, const Color(0xFFFF5252));
    expect(tile('Leak'), const Color(0xFF3A1010));
    expect(text('Door').style!.color, isNot(const Color(0xFFFFD166)));
    expect(tile('Door'), isNot(const Color(0xFF112233)));
    await t.pumpWidget(const SizedBox());
    unawaited(conn.dispose());
  });

  test('the setup screen shows a non-standard MQTT port', () {
    Settings at(int? port) => Settings(
      url: 'u',
      token: 't',
      mqtt: {'host': '10.0.0.2', 'port': ?port},
    );
    expect(at(1884).mqttAddress, '10.0.0.2:1884');
    expect(at(1883).mqttAddress, '10.0.0.2');
    expect(at(null).mqttAddress, '10.0.0.2');
  });

  test('text size stays in range', () {
    final s = Settings(url: 'u', token: 't', textSize: 500);
    expect(s.textSize, Settings.maxTextSize);
    s.textSize = 10;
    expect(s.textSize, Settings.minTextSize);
    expect(Settings(url: 'u', token: 't').textSize, 100);
  });

  group('every card at the largest text size', () {
    // Each height has about 20 px to spare over what the card needs at 100%,
    // which is the room the README tells people to allow at the largest size.
    final cards = <String, Map<String, dynamic>>{
      'light': {'type': 'custom:nspanel-light-card', 'entity': 'light.l', 'height': 228},
      'cover': {'type': 'custom:nspanel-cover-card', 'entity': 'cover.c', 'height': 228},
      'climate': {'type': 'custom:nspanel-climate-card', 'entity': 'climate.c', 'height': 228},
      'media': {'type': 'custom:nspanel-media-card', 'entity': 'media_player.m', 'height': 228},
      'buttons x3': {
        'type': 'custom:nspanel-button-card',
        'height': 120,
        'columns': 3,
        'buttons': [
          {'entity': 'script.s', 'name': 'Good morning everyone'},
          {'entity': 'script.s', 'name': 'B'},
          {'entity': 'script.s', 'name': 'C'},
        ],
      },
      'switches': {
        'type': 'custom:nspanel-switch-card',
        'height': 160,
        'switches': [
          {'entity': 'switch.sw'},
        ],
      },
      'alarm': {
        'type': 'custom:nspanel-alarm-card',
        'entity': 'alarm_control_panel.a',
        'height': 180,
        'modes': ['home', 'away', 'night'],
      },
      'status x3': {
        'type': 'custom:nspanel-status-card',
        'height': 200,
        'columns': 3,
        'entities': ['binary_sensor.leak', 'binary_sensor.door', 'switch.sw'],
      },
      'sensor': {'type': 'custom:nspanel-sensor-card', 'entity': 'sensor.t', 'height': 200},
      'sensors': {
        'type': 'custom:nspanel-sensors-card',
        'height': 150,
        'entities': ['sensor.t', 'sensor.t', 'sensor.t'],
      },
      'weather': {
        'type': 'custom:nspanel-weather-card',
        'entity': 'weather.w',
        'height': 288,
        'show_precipitation': true,
      },
      'clock': {'type': 'custom:nspanel-clock-card', 'height': 304},
    };
    cards.forEach((name, config) {
      testWidgets(name, (t) async {
        t.view.physicalSize = const Size(480, 480);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        final (_, env, conn) = await _env();
        await t.pumpWidget(_app(config, env));
        await t.pump(const Duration(milliseconds: 100));
        expect(t.takeException(), isNull, reason: 'at the normal size');
        await t.pumpWidget(_app(config, env, scale: Settings.maxTextSize / 100));
        await t.pump(const Duration(milliseconds: 100));
        expect(t.takeException(), isNull);
        // Dutch and German words run longer than English ones
        for (final lang in [Strings.nl, Strings.de]) {
          await t.pumpWidget(
            _app(config, env, scale: Settings.maxTextSize / 100, strings: lang),
          );
          await t.pump(const Duration(milliseconds: 100));
          expect(t.takeException(), isNull, reason: '${lang.lang}');
        }
        await t.pumpWidget(const SizedBox());
        unawaited(conn.dispose());
      });
    });

    testWidgets('keypad', (t) async {
      t.view.physicalSize = const Size(480, 480);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      late BuildContext ctx;
      await t.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const PanelTextScaler(Settings.maxTextSize / 100),
            ),
            child: child!,
          ),
          home: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox();
            },
          ),
        ),
      );
      unawaited(
        showKeypadSheet(
          ctx,
          title: 'Disarm',
          accent: Colors.teal,
          onSubmit: (_) async => true,
        ),
      );
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });

    testWidgets('control sheet', (t) async {
      t.view.physicalSize = const Size(480, 480);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      late BuildContext ctx;
      await t.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const PanelTextScaler(Settings.maxTextSize / 100),
            ),
            child: child!,
          ),
          home: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox();
            },
          ),
        ),
      );
      unawaited(
        showControlSheet(
          ctx,
          title: 'Living room ceiling',
          state: 'Now 21.5° · Heating',
          value: .5,
          accent: Colors.red,
          actions: [
            for (final l in ['Off', 'Heat', 'Cool', 'Auto'])
              SheetAction(label: l, run: () {}),
          ],
        ),
      );
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
    });
  });
}
