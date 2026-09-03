import 'dart:io';

import 'package:flutter/services.dart';

/// The panel's own hardware, past what Flutter gives us: a stable device id,
/// the light sensor, Wi-Fi signal, screen brightness and speaker volume.
/// One method channel and one event channel in MainActivity; nothing else.
class Device {
  static const _m = MethodChannel('nl.mennovanhout.nspanel/sensors');
  static const _light = EventChannel('nl.mennovanhout.nspanel/light');
  static Stream<double>? _lightStream;

  /// ANDROID_ID: stable across reinstalls with the same signing key, which is
  /// what makes it a usable MQTT device id.
  static Future<String> androidId() async {
    try {
      return (await _m.invokeMethod<String>('androidId')) ?? 'unknown';
    } catch (_) {
      return 'unknown';
    }
  }

  static Stream<double> get light =>
      _lightStream ??= _light.receiveBroadcastStream().map((v) => (v as num).toDouble());

  static Future<int?> wifiRssi() async {
    try {
      return await _m.invokeMethod<int>('wifiRssi');
    } catch (_) {
      return null;
    }
  }

  static Future<int?> brightness() async {
    try {
      return await _m.invokeMethod<int>('getBrightness');
    } catch (_) {
      return null;
    }
  }

  /// Needs WRITE_SETTINGS, granted once on the panel (or via adb appops).
  /// Returns false when it is not.
  static Future<bool> setBrightness(int v) async {
    try {
      return (await _m.invokeMethod<bool>('setBrightness', v.clamp(0, 255))) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// 0..100 of the media stream, which is what the speaker plays on.
  static Future<int?> volume() async {
    try {
      return await _m.invokeMethod<int>('getVolume');
    } catch (_) {
      return null;
    }
  }

  static Future<bool> setVolume(int pct) async {
    try {
      return (await _m.invokeMethod<bool>('setVolume', pct.clamp(0, 100))) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// The SoC, not the room - the Pro 86 exposes no ambient sensor to Android.
  static Future<double?> socTemperature() async {
    try {
      final raw = await File('/sys/class/thermal/thermal_zone0/temp').readAsString();
      final n = num.tryParse(raw.trim());
      return n == null ? null : n / 1000;
    } catch (_) {
      return null;
    }
  }
}
