import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../config/screensaver.dart';
import 'device.dart';
import 'display.dart';
import 'display_controller.dart';
import 'proximity.dart';
import 'proximity_presence.dart';

class NativeDisplayDriver implements DisplayDriver {
  final _power = DisplayPower();
  static const _control = MethodChannel(
    'nl.mennovanhout.nspanel/displayControl',
  );
  @override
  Future<void> idleTimeout(int? milliseconds) async {
    try {
      await _control.invokeMethod<void>('idleTimeout', milliseconds);
    } on MissingPluginException {
      /* Non-Android host. */
    }
  }

  @override
  Future<bool> off() => _power.off();
  @override
  Future<void> on() => _power.on();
  @override
  Future<void> holdCpu(bool on) => Device.holdCpu(on);
  @override
  Future<void> saver(bool on) async {
    try {
      await _control.invokeMethod<void>('saver', on);
    } on MissingPluginException {
      /* Widget tests and non-Android hosts. */
    }
  }
}

/// App-lifetime platform subscriptions; no dependency on HA or MQTT sockets.
class DisplaySession {
  DisplaySession() {
    controller.addListener(_changed);
    _events = const EventChannel('nl.mennovanhout.nspanel/displayEvents')
        .receiveBroadcastStream()
        .listen(
          (dynamic event) {
            final e = event as Map;
            final stamp = e['elapsed'];
            if (stamp is num) {
              _elapsed = stamp.toInt();
              _clock.reset();
            }
            lastEvent = Map<String, dynamic>.from(e);
            activity.add(lastEvent!);
            controller.platform(
              kind: e['kind'] as String,
              screenOn: e['interactive'] == true,
              inForeground: e['foreground'] == true,
              pointerCount: (e['fingers'] as num?)?.toInt() ?? 0,
            );
          },
          onError: (Object e) => debugPrint(
            'display: platform stream unavailable (${e.runtimeType})',
          ),
        );
  }
  final activity = StreamController<Map<String, dynamic>>.broadcast(sync: true);
  Map<String, dynamic>? lastEvent;
  final _clock = Stopwatch()..start();
  int _elapsed = 0;
  int get elapsedMilliseconds => _elapsed + _clock.elapsedMilliseconds;
  final controller = DisplayController(NativeDisplayDriver());
  StreamSubscription<dynamic>? _events;
  StreamSubscription<double>? _sensor;
  ProximityPresence? _presence;
  ScreensaverConfig? _sensorConfig;
  bool _disposed = false;
  bool _updating = false;

  void configure(ScreensaverConfig? config, {required bool active}) {
    controller.configure(config, active: active);
    _changed();
  }

  void _changed() {
    if (_disposed || _updating) return;
    _updating = true;
    try {
      _updateSensor();
    } finally {
      _updating = false;
    }
  }

  void _updateSensor() {
    final s = controller.config;
    if (!controller.enabled ||
        !controller.foreground ||
        s == null ||
        (!s.wakeOnProximity && !s.keepAwakeOnProximity)) {
      _sensor?.cancel();
      _sensor = null;
      _presence?.dispose();
      _presence = null;
      _sensorConfig = null;
      controller.proximity(false);
      return;
    }
    final old = _sensorConfig;
    if (_sensor == null ||
        old?.proximityAbove != s.proximityAbove ||
        old?.proximityBelow != s.proximityBelow ||
        old?.proximityDelta != s.proximityDelta) {
      _sensor?.cancel();
      _presence?.dispose();
      _sensorConfig = s;
      controller.proximity(false);
      final detector = ProximityPresence(s, controller.proximity);
      _presence = detector;
      _sensor = Proximity.stream.listen(
        detector.feed,
        onError: (Object e) {
          debugPrint('display: proximity unavailable (${e.runtimeType})');
          controller.proximity(false);
        },
      );
    }
    _presence?.dark(!controller.interactive);
  }

  void dispose() {
    _disposed = true;
    _events?.cancel();
    _sensor?.cancel();
    _presence?.dispose();
    controller.removeListener(_changed);
    activity.close();
    controller.dispose();
  }
}
