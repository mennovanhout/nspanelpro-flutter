import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nspanel_app/config/screensaver.dart';
import 'package:nspanel_app/ui/display_overlay.dart';
import 'package:nspanel_app/ui/screensaver.dart';
import 'package:nspanel_app/util/display_controller.dart';

import 'display_controller_test.dart' show Driver;

void main() {
  testWidgets(
    'screensaver covers modal routes and wake does not press underlying action',
    (t) async {
      final c = DisplayController(Driver())
        ..configure(
          const ScreensaverConfig(afterSeconds: 15, sleep: false),
          active: true,
        );
      int actions = 0;
      late BuildContext home;
      await t.pumpWidget(
        MaterialApp(
          builder: (context, child) =>
              DisplayOverlay(controller: c, child: child!),
          home: Builder(
            builder: (context) {
              home = context;
              return const Scaffold();
            },
          ),
        ),
      );
      showDialog<void>(
        context: home,
        builder: (_) => AlertDialog(
          content: TextButton(
            onPressed: () => actions++,
            child: const Text('Simulated action'),
          ),
        ),
      );
      await t.pump(const Duration(milliseconds: 300));
      final position = t.getCenter(find.text('Simulated action'));
      c.sleep(force: true);
      await t.pump();
      await t.pump(const Duration(milliseconds: 1));
      expect(find.byType(Screensaver), findsOneWidget);
      await t.tapAt(position);
      await t.pump();
      expect(actions, 0);
      expect(find.byType(Screensaver), findsNothing);
      expect(find.text('Simulated action'), findsOneWidget);
      await t.tapAt(position);
      expect(actions, 1);
      await t.pumpWidget(const SizedBox());
      c.dispose();
    },
  );
}
