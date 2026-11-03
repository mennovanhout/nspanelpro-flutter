import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nspanel_app/cards/env.dart';
import 'package:nspanel_app/cards/registry.dart';
import 'package:nspanel_app/config/settings.dart';
import 'package:nspanel_app/ha/connection.dart';
import 'package:nspanel_app/ha/states.dart';

import 'connection_test.dart' show FakeHa, st;

void main() {
  // The config two people reported as a gray card, entity for entity -
  // including the window listed twice.
  const reported = [
    'front_door',
    'back_door',
    'patio_door',
    'play_room_window',
    'stairs_window',
    'master_bedroom_window',
    'play_room_window',
  ];

  for (final n in [2, 7]) {
    testWidgets('a status card lays out without throwing ($n entities)', (
      tester,
    ) async {
      final fake = FakeHa({
        for (final e in reported)
          'binary_sensor.$e': st(
            'binary_sensor.$e',
            e == 'back_door' ? 'on' : 'off',
            {'device_class': 'door'},
          ),
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
      await ready.future.timeout(const Duration(seconds: 2));
      final env = PanelEnv(
        states: states,
        conn: conn,
        settings: Settings(url: 'http://x', token: 't'),
      );

      // a page is a column of cards, as on the panel
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  buildCard({
                    'type': 'custom:nspanel-status-card',
                    'title': 'House',
                    'height': 240,
                    'only_problems': false,
                    'entities': [
                      for (final e in reported.take(n))
                        {'entity': 'binary_sensor.$e', 'name': e},
                    ],
                  }, env),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(
        tester.takeException(),
        isNull,
        reason: 'a layout error is what draws the gray card',
      );
      expect(find.text('front_door'), findsOneWidget);
      expect(
        find.text('Open'),
        findsOneWidget,
        reason: 'the open back door is shown as open',
      );
      // the tiles keep their own height
      expect(
        tester.getSize(find.text('front_door').first).height,
        lessThan(62),
      );
      unawaited(conn.dispose());
    });
  }
}
