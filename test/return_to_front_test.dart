import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nspanel_app/util/return_to_front.dart';

// testWidgets for its fake clock: tester.pump(d) moves the Timers along.
void main() {
  testWidgets('another app on screen for return_after seconds: the app comes back', (t) async {
    var calls = 0;
    final r = ReturnToFront(bringToFront: () async => calls++)..seconds = 30;
    await t.pumpWidget(const SizedBox());

    r.foreground = false; // the stock launcher's menu, after a stray Home press
    await t.pump(const Duration(seconds: 29));
    expect(calls, 0);
    await t.pump(const Duration(seconds: 1));
    expect(calls, 1);

    // it did not take: again a period later, not in a tight loop
    await t.pump(const Duration(seconds: 29));
    expect(calls, 1);
    await t.pump(const Duration(seconds: 1));
    expect(calls, 2);

    // back in front: nothing more
    r.foreground = true;
    await t.pump(const Duration(minutes: 5));
    expect(calls, 2);
    r.dispose();
  });

  testWidgets('coming back by hand in time, or 0, means it never pulls itself forward', (t) async {
    var calls = 0;
    final r = ReturnToFront(bringToFront: () async => calls++)..seconds = 30;
    await t.pumpWidget(const SizedBox());

    r.foreground = false;
    await t.pump(const Duration(seconds: 20));
    r.foreground = true; // somebody tapped back to the dashboard
    await t.pump(const Duration(minutes: 1));
    expect(calls, 0);

    // off by default, and off when HA sets 0 while it is away
    final off = ReturnToFront(bringToFront: () async => calls++);
    off.foreground = false;
    await t.pump(const Duration(hours: 1));
    expect(calls, 0);

    r.foreground = false;
    await t.pump(const Duration(seconds: 10));
    r.seconds = 0;
    await t.pump(const Duration(minutes: 1));
    expect(calls, 0);

    // and turned on while away, it starts counting then
    r.seconds = 15;
    await t.pump(const Duration(seconds: 15));
    expect(calls, 1);
    r.dispose();
    off.dispose();
  });
}
