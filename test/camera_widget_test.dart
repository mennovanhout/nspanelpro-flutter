import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nspanel_app/cards/camera_card.dart';
import 'package:nspanel_app/cards/env.dart';
import 'package:nspanel_app/config/settings.dart';
import 'package:nspanel_app/ha/connection.dart';
import 'package:nspanel_app/ha/states.dart';
import 'package:nspanel_app/ui/page_scope.dart';

import 'connection_test.dart' show FakeHa, st;

// a 1x1 png
final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=');

void main() {
  testWidgets('it only asks for pictures while its page is showing and the panel is awake', (tester) async {
    final fake = FakeHa({
      'camera.door': st('camera.door', 'idle', {'friendly_name': 'Front door'}),
    });
    final states = HaStates();
    final conn = HaConnection(transportFactory: () async => fake, token: 'good', states: states);
    final ready = Completer<void>();
    conn.onReady = ready.complete;
    await conn.start();
    await ready.future.timeout(const Duration(seconds: 2));
    final env = PanelEnv(states: states, conn: conn, settings: Settings(url: 'http://x', token: 't'));

    final asked = <String>[];
    Future<Uint8List?> fetch(String entity, int w, int h) async {
      asked.add('$entity ${w}x$h');
      return _png;
    }

    final shown = ValueNotifier<int>(0);
    final awake = ValueNotifier<bool>(true);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: PageScope(
          index: 2, // the camera lives on the third page
          shown: shown,
          awake: awake,
          child: CameraCard(
            config: {'type': 'custom:nspanel-camera-card', 'entity': 'camera.door', 'height': 300, 'interval': 1},
            env: env,
            fetch: fetch,
          ),
        ),
      ),
    ));
    // page one is showing: nothing is asked for, however long it takes
    await tester.pump(const Duration(seconds: 5));
    expect(asked, isEmpty);
    expect(find.text('Loading…'), findsOneWidget);

    // an automation turns to the camera page: the first still is asked for at once
    shown.value = 2;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
    expect(asked.length, 1);
    expect(asked.single, startsWith('camera.door '));
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('Front door'), findsOneWidget);

    // and then one a second
    await tester.pump(const Duration(milliseconds: 1050));
    await tester.pump(const Duration(milliseconds: 1050));
    expect(asked.length, 3);

    // the screensaver comes up: it stops, and keeps the last picture
    awake.value = false;
    await tester.pump();
    final before = asked.length;
    await tester.pump(const Duration(seconds: 5));
    expect(asked.length, before);
    expect(find.byType(Image), findsOneWidget);

    // woken: it picks up again
    awake.value = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 10));
    expect(asked.length, before + 1);

    // swiped away: stops again
    shown.value = 0;
    await tester.pump();
    final after = asked.length;
    await tester.pump(const Duration(seconds: 3));
    expect(asked.length, after);
    unawaited(conn.dispose());
  });

  testWidgets('a camera that does not answer says so, and is asked less often', (tester) async {
    final fake = FakeHa({'camera.door': st('camera.door', 'idle', {})});
    final states = HaStates();
    final conn = HaConnection(transportFactory: () async => fake, token: 'good', states: states);
    final ready = Completer<void>();
    conn.onReady = ready.complete;
    await conn.start();
    await ready.future.timeout(const Duration(seconds: 2));
    final env = PanelEnv(states: states, conn: conn, settings: Settings(url: 'http://x', token: 't'));
    var asked = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CameraCard(
          config: {'entity': 'camera.door', 'interval': 0.5},
          env: env,
          fetch: (_, _, _) async {
            asked++;
            return null;
          },
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 10));
    expect(asked, 1);
    await tester.pump(const Duration(seconds: 2));
    expect(asked, 1, reason: 'not at the 0.5 s interval after a failure');
    await tester.pump(const Duration(seconds: 12));
    expect(asked, greaterThanOrEqualTo(3));
    expect(find.text('No picture'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    unawaited(conn.dispose());
  });
}
