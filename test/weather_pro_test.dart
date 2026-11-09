import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nspanel_app/cards/env.dart';
import 'package:nspanel_app/cards/registry.dart';
import 'package:nspanel_app/cards/weather_card.dart';
import 'package:nspanel_app/cards/weather_pro_card.dart';
import 'package:nspanel_app/config/settings.dart';
import 'package:nspanel_app/ha/connection.dart';
import 'package:nspanel_app/ha/states.dart';

import 'connection_test.dart' show FakeHa, st;

void main() {
  testWidgets('style: pro draws the pro page, in English, with no artwork by default', (t) async {
    final fake = FakeHa({
      'weather.home': st('weather.home', 'rainy', {
        'friendly_name': 'Home', 'temperature': 11.6, 'temperature_unit': '°C',
        'humidity': 80, 'wind_speed': 12, 'wind_speed_unit': 'km/h',
        'forecast': [
          {'datetime': '2026-11-09T12:00:00+00:00', 'condition': 'rainy', 'temperature': 12, 'templow': 9},
        ],
      }),
    });
    final states = HaStates();
    final conn = HaConnection(transportFactory: () async => fake, token: 'good', states: states);
    final ready = Completer<void>();
    conn.onReady = ready.complete;
    await conn.start();
    await ready.future.timeout(const Duration(seconds: 2));
    final env = PanelEnv(states: states, conn: conn, settings: Settings(url: 'http://x', token: 't'));

    await t.pumpWidget(MaterialApp(home: Scaffold(body: buildCard({
      'type': 'custom:nspanel-weather-card', 'entity': 'weather.home', 'style': 'pro', 'height': 480,
    }, env))));
    await t.pump(const Duration(milliseconds: 50));
    expect(find.byType(WeatherProCard), findsOneWidget);
    expect(find.text('Rainy'), findsOneWidget);
    expect(find.text('Mon'), findsOneWidget);
    expect(find.byType(Image), findsNothing, reason: 'no background_url, no picture to fetch');

    // without the key it is the ordinary card, exactly as before
    await t.pumpWidget(MaterialApp(home: Scaffold(body: buildCard({
      'type': 'custom:nspanel-weather-card', 'entity': 'weather.home', 'height': 300,
    }, env))));
    await t.pump(const Duration(milliseconds: 50));
    expect(find.byType(WeatherCard), findsOneWidget);
    expect(find.byType(WeatherProCard), findsNothing);
    await t.pumpWidget(const SizedBox());
    unawaited(conn.dispose());
  });
}
