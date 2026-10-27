import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nspanel_app/cards/env.dart';
import 'package:nspanel_app/cards/registry.dart';
import 'package:nspanel_app/cards/weather_card.dart';
import 'package:nspanel_app/config/screensaver.dart';
import 'package:nspanel_app/config/settings.dart';
import 'package:nspanel_app/ha/connection.dart';
import 'package:nspanel_app/ha/states.dart';
import 'package:nspanel_app/ui/saver_weather.dart';
import 'package:nspanel_app/util/weather.dart';

import 'connection_test.dart' show FakeHa, st;

// what Met.no sends through HA, entry for entry
final _forecast = [
  {
    'datetime': '2026-10-25T12:00:00+00:00',
    'condition': 'cloudy',
    'temperature': 11.6,
    'templow': 9.0,
    'precipitation': 0.0,
    'precipitation_probability': 4.6,
  },
  {
    'datetime': '2026-10-25T13:00:00+00:00',
    'condition': 'rainy',
    'temperature': 11.8,
    'precipitation': 1.24,
    'precipitation_probability': 80.1,
  },
  {
    'datetime': '2026-10-25T14:00:00+00:00',
    'condition': 'cloudy',
    'temperature': 12.0,
  },
];

Future<PanelEnv> _env(FakeHa fake) async {
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
  return PanelEnv(
    states: states,
    conn: conn,
    settings: Settings(url: 'http://x', token: 't'),
  );
}

void main() {
  test('rain, as short as a tile allows', () {
    expect(
      rainOf(_forecast[0])!.text,
      '5% · 0mm',
      reason: 'a dry hour says how dry',
    );
    expect(rainOf(_forecast[0])!.wet, isFalse);
    expect(rainOf(_forecast[1])!.text, '80% · 1.2mm');
    expect(rainOf(_forecast[1])!.wet, isTrue);
    expect(rainOf(_forecast[2]), isNull, reason: 'the provider sends neither');
    expect(rainOf({'precipitation': 0.4}, unit: 'in')!.text, '0.4in');
    expect(rainOf({'precipitation': 0})!.text, '0mm');
    expect(
      rainOf({'precipitation_probability': 40})!.text,
      '40%',
      reason: 'a provider that sends only the chance',
    );
    expect(
      rainOf({'precipitation_probability': 3, 'precipitation': 0.8})!.text,
      '3% · 0.8mm',
    );
  });

  test("Home Assistant's own weather card maps onto ours", () {
    final c = weatherConfigFromHa({
      'type': 'weather-forecast',
      'entity': 'weather.home',
      'name': 'Garden',
      'forecast_type': 'hourly',
      'forecast_slots': 4,
      'show_current': false,
    });
    expect(c['entity'], 'weather.home');
    expect(c['title'], 'Garden');
    expect(c['forecast_type'], 'hourly');
    expect(c['forecast_count'], 4);
    expect(c['show_forecast'], isTrue);
    expect(c.containsKey('show_current'), isFalse);
    expect(
      weatherConfigFromHa({'entity': 'weather.home'})['forecast_count'],
      5,
      reason: "HA's default",
    );
  });

  test('the screensaver weather keys, kept through the overrides from HA', () {
    final s = ScreensaverConfig.fromMap({
      'weather': 'weather.home',
      'weather_forecast': false,
    });
    expect(s.weather, 'weather.home');
    expect(s.weatherForecast, isFalse);
    final o = s.withOverrides({'after': 60});
    expect(o.weather, 'weather.home');
    expect(o.weatherForecast, isFalse);
    expect(
      ScreensaverConfig.fromMap({'weather': 'sensor.temp'}).weather,
      isNull,
      reason: 'only a weather entity',
    );
    expect(ScreensaverConfig.fromMap({}).weather, isNull);
  });

  testWidgets(
    'show_precipitation puts the chance and the amount under each hour',
    (tester) async {
      final fake = FakeHa({
        'weather.home': st('weather.home', 'cloudy', {
          'friendly_name': 'Home',
          'temperature': 11.6,
          'temperature_unit': '°C',
          'precipitation_unit': 'mm',
          'forecast': _forecast,
        }),
      });
      final env = await _env(fake);
      Future<void> show(Map<String, dynamic> c) async {
        await tester.pumpWidget(
          MaterialApp(home: Scaffold(body: buildCard(c, env))),
        );
        await tester.pump(const Duration(milliseconds: 50));
      }

      await show({
        'type': 'custom:nspanel-weather-card',
        'entity': 'weather.home',
        'forecast_type': 'hourly',
        'show_precipitation': true,
        'height': 300,
      });
      expect(find.text('80% · 1.2mm'), findsOneWidget);
      expect(find.text('5% · 0mm'), findsOneWidget);
      expect(
        find.text('–'),
        findsOneWidget,
        reason: 'an hour without rain data says so',
      );

      // off by default: the card looks as it did
      await show({
        'type': 'custom:nspanel-weather-card',
        'entity': 'weather.home',
        'height': 300,
      });
      expect(find.text('80% · 1.2mm'), findsNothing);

      // HA's own card renders, as ours
      await show({
        'type': 'weather-forecast',
        'entity': 'weather.home',
        'name': 'Garden',
        'show_precipitation': true,
        'height': 320, // the test font is taller than Roboto
      });
      expect(find.byType(WeatherCard), findsOneWidget);
      expect(find.text('Garden'), findsOneWidget);
      expect(find.text('80% · 1.2mm'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      unawaited(env.conn.dispose());
    },
  );

  testWidgets('the screensaver weather: now, and today', (tester) async {
    final fake = FakeHa({
      'weather.home': st('weather.home', 'rainy', {
        'temperature': 11.6,
        'temperature_unit': '°C',
        'forecast': [_forecast[1]..['templow'] = 9.0],
      }),
    });
    final env = await _env(fake);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SaverWeather(entity: 'weather.home', env: env),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('12°  Rainy'), findsOneWidget);
    expect(find.text('12° / 9° · 80% · 1.2mm rain'), findsOneWidget);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SaverWeather(entity: 'weather.home', env: env, forecast: false),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('12°  Rainy'), findsOneWidget);
    expect(find.textContaining('rain'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    unawaited(env.conn.dispose());
  });
}
