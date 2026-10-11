import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:nspanel_app/config/screensaver.dart';
import 'package:nspanel_app/util/display_controller.dart';
import 'package:nspanel_app/util/proximity_presence.dart';

class Driver implements DisplayDriver {
  int offs = 0, ons = 0;
  int? systemTimeout;
  @override
  Future<void> idleTimeout(int? milliseconds) async {
    systemTimeout = milliseconds;
  }

  bool saverOn = false, cpu = false, fail = false;
  Completer<bool>? pending;
  @override
  Future<bool> off() async {
    offs++;
    return pending?.future ?? !fail;
  }

  @override
  Future<void> on() async {
    ons++;
  }

  @override
  Future<void> holdCpu(bool on) async {
    cpu = on;
  }

  @override
  Future<void> saver(bool on) async {
    saverOn = on;
  }
}

const config = ScreensaverConfig(
  afterSeconds: 15,
  sleep: true,
  keepAwakeOnProximity: true,
  proximityAbove: 200,
);
void touch(
  DisplayController c,
  int fingers, {
  bool on = true,
  bool foreground = true,
}) => c.platform(
  kind: 'touch',
  screenOn: on,
  inForeground: foreground,
  pointerCount: fingers,
);

void main() {
  testWidgets('held finger and multi-touch inhibit idle until final release', (
    t,
  ) async {
    final d = Driver();
    final c = DisplayController(d)..configure(config, active: true);
    touch(c, 1);
    await t.pump(const Duration(seconds: 30));
    expect(d.offs, 0);
    expect(d.systemTimeout, 15000);
    touch(c, 2);
    touch(c, 1);
    await t.pump(const Duration(seconds: 30));
    expect(d.offs, 0);
    touch(c, 0);
    await t.pump(const Duration(seconds: 14));
    expect(d.offs, 0);
    await t.pump(const Duration(seconds: 1));
    await t.pump(const Duration(milliseconds: 1));
    expect(d.offs, 1);
    c.dispose();
  });
  testWidgets('near holds awake and complete timeout starts after leaving', (
    t,
  ) async {
    final d = Driver();
    final c = DisplayController(d)..configure(config, active: true);
    c.proximity(true);
    await t.pump(const Duration(seconds: 40));
    expect(d.offs, 0);
    c.proximity(false);
    await t.pump(const Duration(seconds: 14));
    expect(d.offs, 0);
    await t.pump(const Duration(seconds: 1));
    await t.pump(const Duration(milliseconds: 1));
    expect(d.offs, 1);
    c.dispose();
  });
  testWidgets('foreign app and setup cannot be shut down by idle', (t) async {
    final d = Driver();
    final c = DisplayController(d)..configure(config, active: true);
    touch(c, 0, foreground: false);
    await t.pump(const Duration(seconds: 30));
    expect(d.offs, 0);
    c.platform(
      kind: 'lifecycle',
      screenOn: true,
      inForeground: true,
      pointerCount: 0,
    );
    await t.pump(const Duration(seconds: 14));
    expect(d.offs, 0);
    c.configure(config, active: false);
    await t.pump(const Duration(seconds: 30));
    expect(d.offs, 0);
    c.dispose();
  });
  testWidgets('new activity compensates a sleep already in flight', (t) async {
    final d = Driver()..pending = Completer<bool>();
    final c = DisplayController(d)..configure(config, active: true);
    await t.pump(const Duration(seconds: 15));
    await t.pump(const Duration(milliseconds: 1));
    expect(d.offs, 1);
    touch(c, 1);
    d.pending!.complete(true);
    await t.pump(const Duration(milliseconds: 1));
    expect(d.ons, 1);
    expect(c.saving, false);
    c.dispose();
  });
  testWidgets('screensaver duration changes and existing dark stays dark', (
    t,
  ) async {
    final d = Driver();
    final c = DisplayController(d)
      ..configure(
        const ScreensaverConfig(
          afterSeconds: 15,
          sleep: true,
          sleepAfterSeconds: 60,
        ),
        active: true,
      );
    await t.pump(const Duration(seconds: 15));
    await t.pump(const Duration(milliseconds: 1));
    expect(c.saving, true);
    expect(d.offs, 0);
    c.configure(config, active: true);
    await t.pump(const Duration(milliseconds: 1));
    expect(d.offs, 1);
    c.configure(
      const ScreensaverConfig(
        afterSeconds: 15,
        sleep: true,
        sleepAfterSeconds: 60,
      ),
      active: true,
    );
    await t.pump(const Duration(milliseconds: 1));
    expect(d.ons, 0);
    c.dispose();
  });
  testWidgets('forced sleep waits for a fresh approach', (t) async {
    final d = Driver();
    final c = DisplayController(d)..configure(config, active: true);
    c.proximity(true);
    c.sleep(force: true);
    await t.pump(const Duration(milliseconds: 1));
    await t.pump(const Duration(milliseconds: 1));
    expect(d.offs, 1);
    c.proximity(true);
    await t.pump(const Duration(milliseconds: 1));
    expect(d.ons, 0);
    c.proximity(false);
    c.proximity(true);
    await t.pump(const Duration(milliseconds: 1));
    expect(d.ons, 1);
    c.dispose();
  });
  testWidgets('failed sleep remains visible without retry loop', (t) async {
    final d = Driver()..fail = true;
    final c = DisplayController(d)..configure(config, active: true);
    await t.pump(const Duration(seconds: 15));
    await t.pump(const Duration(milliseconds: 1));
    expect(c.interactive, true);
    expect(c.saving, true);
    await t.pump(const Duration(seconds: 60));
    expect(d.offs, 1);
    c.dispose();
  });
  testWidgets('cold start in the dark retains CPU and does not wake', (
    t,
  ) async {
    final d = Driver();
    final c = DisplayController(d);
    c.platform(
      kind: 'snapshot',
      screenOn: false,
      inForeground: true,
      pointerCount: 0,
    );
    c.configure(config, active: true);
    await t.pump();
    expect(c.saving, true);
    expect(d.cpu, true);
    expect(d.ons, 0);
    c.dispose();
  });
  testWidgets('turning sleep off reveals saver without dismissing it', (
    t,
  ) async {
    final d = Driver();
    final c = DisplayController(d)..configure(config, active: true);
    await t.pump(const Duration(seconds: 15));
    await t.pump(const Duration(milliseconds: 1));
    c.configure(
      const ScreensaverConfig(afterSeconds: 15, sleep: false),
      active: true,
    );
    await t.pump();
    expect(d.ons, 1);
    c.platform(
      kind: 'screen',
      screenOn: true,
      inForeground: true,
      pointerCount: 0,
    );
    expect(c.saving, true);
    expect(d.saverOn, true);
    c.dispose();
  });
  testWidgets(
    'leaving app while sleep is in flight restores external display',
    (t) async {
      final d = Driver()..pending = Completer<bool>();
      final c = DisplayController(d)..configure(config, active: true);
      await t.pump(const Duration(seconds: 15));
      await t.pump(const Duration(milliseconds: 1));
      c.platform(
        kind: 'lifecycle',
        screenOn: true,
        inForeground: false,
        pointerCount: 0,
      );
      d.pending!.complete(true);
      await t.pump();
      expect(d.ons, 1);
      expect(d.cpu, false);
      c.dispose();
    },
  );
  testWidgets('configuration reload and telemetry do not postpone idle', (
    t,
  ) async {
    final d = Driver();
    final c = DisplayController(d)..configure(config, active: true);
    await t.pump(const Duration(seconds: 10));
    c.configure(config, active: true);
    c.platform(
      kind: 'snapshot',
      screenOn: true,
      inForeground: true,
      pointerCount: 0,
    );
    // The very first snapshot establishes an awake epoch, so measure from it.
    await t.pump(const Duration(seconds: 10));
    c.platform(
      kind: 'snapshot',
      screenOn: true,
      inForeground: true,
      pointerCount: 0,
    );
    c.configure(config, active: true);
    await t.pump(const Duration(seconds: 5));
    await t.pump(const Duration(milliseconds: 1));
    expect(d.offs, 1);
    c.dispose();
  });
  testWidgets('presence hysteresis holds unchanged near and rejects noise', (
    t,
  ) async {
    final seen = <bool>[];
    final p = ProximityPresence(config, seen.add);
    p.feed(210);
    p.feed(210);
    expect(seen, [true]);
    await t.pump(const Duration(seconds: 60));
    expect(seen, [true]);
    p.feed(150);
    await t.pump(const Duration(milliseconds: 499));
    p.feed(180);
    await t.pump(const Duration(seconds: 1));
    expect(seen, [true]);
    p.feed(150);
    await t.pump(const Duration(milliseconds: 500));
    expect(seen, [true, false]);
    p.dispose();
  });
}
