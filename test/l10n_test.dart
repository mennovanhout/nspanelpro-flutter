import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nspanel_app/cards/env.dart';
import 'package:nspanel_app/cards/registry.dart';
import 'package:nspanel_app/config/settings.dart';
import 'package:nspanel_app/ha/connection.dart';
import 'package:nspanel_app/ha/states.dart';
import 'package:nspanel_app/l10n/ha_language.dart';
import 'package:nspanel_app/l10n/strings.dart';

import 'connection_test.dart' show FakeHa, st;

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

/// Every word, as a closure, so one test can hold all three languages to
/// "said something" - a blank label is the failure a table like this has.
List<String> _everything(Strings t) => [
  t.unavailable, t.unknown, t.missing, t.on, t.off, t.turnOn, t.turnOff,
  t.stateOpen, t.stateClosed, t.loading, t.connecting, t.commandFailed,
  for (final s in ['home', 'not_home', 'locked', 'unlocked', 'idle', 'standby', 'above_horizon'])
    t.state(s),
  ...t.daysShort, ...t.daysLong, ...t.months,
  t.lightLow, t.lightMid, t.lightFull,
  t.coverOpening, t.coverClosing, t.coverPercentOpen(40), t.coverOpen,
  t.coverStop, t.coverClose, t.coverPresetOpen, t.coverPresetHalf, t.coverPresetShut,
  for (final m in ['off', 'heat', 'cool', 'heat_cool', 'auto', 'dry', 'fan_only'])
    t.hvacMode(m)!,
  for (final a in ['heating', 'cooling', 'drying', 'fan', 'idle', 'off', 'preheating', 'defrosting'])
    t.hvacAction(a),
  t.climateNow('21.5'), t.climateEco, t.climateDay, t.climateWarm,
  t.mediaNothing, t.mediaPaused, t.mediaPlaying, t.mediaPrevious, t.mediaPause,
  t.mediaPlay, t.mediaNext, t.mediaStop,
  t.detected, t.clear, t.wet, t.dry, t.problem, t.ok, t.allClear,
  t.tapAgain, t.run, t.cameraUnavailable, t.noPicture,
  for (final m in ['home', 'away', 'night', 'custom_bypass', 'vacation']) ...[
    t.alarmMode(m),
    t.armIn(m),
  ],
  t.disarm, t.disarmed, t.armedHome, t.armedAway, t.armedNight, t.armedVacation,
  t.armedBypass, t.arming, t.disarming, t.pending, t.triggered, t.changedBy('Anna'),
  t.enterCode, t.wrongCode,
  for (final c in [
    'clear-night', 'cloudy', 'exceptional', 'fog', 'hail', 'lightning',
    'lightning-rainy', 'partlycloudy', 'pouring', 'rainy', 'snowy',
    'snowy-rainy', 'sunny', 'windy', 'windy-variant',
  ])
    t.condition(c),
  t.night, t.rainLine('80%'),
  t.tokenRejected, t.noCards('x'), t.defaultDashboardShort, t.theDefaultDashboard,
  t.couldNotLoad('x', 'e'), t.notTakenOver('x'), t.emptyForDefault,
  t.dashboardsHere, t.howToChange,
  t.setupTitle, t.setupIntro, t.setupBothNeeded, t.setupUrl, t.setupToken,
  t.setupNewToken, t.setupDashboard, t.setupExample, t.setupDeviceName, t.setupMqtt,
  t.setupMqttUser, t.setupMqttPass, t.setupPassKept, t.setupTextSize(80, 140),
  t.setupConnect, t.setupNoProximity, t.setupProximityNow('55'), t.setupApp,
  t.setupUpdateTo('1.0.0'), t.setupCheckUpdates,
];

void main() {
  test("HA's language codes, regional or not, and the ones we do not speak", () {
    expect(langFromCode('nl'), Lang.nl);
    expect(langFromCode('nl-BE'), Lang.nl);
    expect(langFromCode('de_AT'), Lang.de);
    expect(langFromCode('DE-ch'), Lang.de);
    expect(langFromCode('en-GB'), Lang.en);
    expect(langFromCode('fr'), isNull);
    expect(langFromCode(''), isNull);
    expect(langFromCode(null), isNull);
  });

  test('every word exists in all three languages, and Dutch and German are not English', () {
    final en = _everything(Strings.en);
    for (final t in [Strings.nl, Strings.de]) {
      final other = _everything(t);
      expect(other.length, en.length);
      expect(other.where((s) => s.trim().isEmpty), isEmpty, reason: '${t.lang}');
      // words that really are the same (OK, Auto, Eco, Warm, Pause, Night)
      // exist, but most of the table has to differ, or it was not translated
      var same = 0;
      for (var i = 0; i < en.length; i++) {
        if (en[i] == other[i]) same++;
      }
      expect(same, lessThan(en.length ~/ 8), reason: '${t.lang}: $same the same');
    }
  });

  test('the date line reads naturally in each language', () {
    final d = DateTime(2026, 11, 16); // a Monday
    expect(Strings.en.longDate(d), 'Monday 16 November');
    expect(Strings.nl.longDate(d), 'maandag 16 november');
    expect(Strings.de.longDate(d), 'Montag, 16. November');
    expect(Strings.nl.dayShort(d), 'ma');
    expect(Strings.de.armIn('away'), 'Abwesend aktivieren');
    expect(Strings.en.armIn('away'), 'Arm away');
  });

  test("the panel's own language wins, then HA's, then English", () {
    Settings s({String language = '', String ha = ''}) =>
        Settings(url: 'http://x', token: 't', language: language, haLanguage: ha);
    expect(s().lang, Lang.en);
    expect(s(ha: 'nl-BE').lang, Lang.nl);
    expect(s(ha: 'fr').lang, Lang.en, reason: 'a language we do not speak');
    expect(s(language: 'de', ha: 'nl').lang, Lang.de);
  });

  test("HA's language: the user's profile, else the system's, followed live", () async {
    // the user never picked one: the system language
    var fake = FakeHa(const {}, systemLanguage: 'de');
    var env = await _env(fake);
    final heard = <String>[];
    final unsub = await followHaLanguage(env.conn, heard.add);
    await pumpEventQueue();
    expect(heard, ['de']);
    expect(unsub, isNotNull);

    // they pick Dutch in their profile; the panel hears it at once
    fake.setUserLanguage('nl-BE');
    await pumpEventQueue();
    expect(heard.last, 'nl-BE');
    await unsub!();
    unawaited(env.conn.dispose());

    // an HA without per-user frontend data: the system language, once
    fake = FakeHa(const {}, systemLanguage: 'nl', userData: false);
    env = await _env(fake);
    heard.clear();
    expect(await followHaLanguage(env.conn, heard.add), isNull);
    expect(heard, ['nl']);
    unawaited(env.conn.dispose());
  });

  testWidgets('a card under L speaks its language, and follows a change at once', (tester) async {
    final fake = FakeHa({
      'binary_sensor.door': st('binary_sensor.door', 'on', {
        'friendly_name': 'Door',
        'device_class': 'door',
      }),
      'light.desk': st('light.desk', 'unavailable', {'friendly_name': 'Desk'}),
    });
    final env = await _env(fake);
    final strings = ValueNotifier(Strings.nl);
    await tester.pumpWidget(
      L(
        strings: strings,
        child: MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                buildCard({
                  'type': 'custom:nspanel-status-card',
                  'entities': ['binary_sensor.door'],
                }, env),
                buildCard({
                  'type': 'custom:nspanel-light-card',
                  'entity': 'light.desk',
                }, env),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    expect(tester.takeException(), isNull);
    expect(find.text('Open'), findsOneWidget, reason: 'the door, in Dutch');
    expect(find.text('Niet beschikbaar'), findsOneWidget);

    // the select on the device page, without a new widget tree
    strings.value = Strings.de;
    await tester.pump();
    expect(find.text('Offen'), findsOneWidget);
    expect(find.text('Nicht verfügbar'), findsOneWidget);
    expect(find.text('Niet beschikbaar'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    unawaited(env.conn.dispose());
  });
}
