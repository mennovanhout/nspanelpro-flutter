import 'package:flutter/services.dart';

/// The panel's proximity sensor, as a stream of readings.
///
/// The NSPanel Pro exposes a standard Android proximity sensor, and unlike a
/// phone's it reports a graded value at roughly 10 Hz rather than near/far.
/// The Kotlin side registers a listener while someone is subscribed and drops
/// it when they are not, so the sensor costs nothing while the dashboard is
/// in use.
class Proximity {
  static const _events = EventChannel('nl.mennovanhout.nspanel/proximity');
  static const _methods = MethodChannel('nl.mennovanhout.nspanel/sensors');

  static Stream<double>? _stream;

  static Stream<double> get stream =>
      _stream ??= _events.receiveBroadcastStream().map((v) => (v as num).toDouble());

  /// null when the device has no proximity sensor.
  static Future<double?> maxRange() async {
    try {
      return (await _methods.invokeMethod<num>('proximityMaxRange'))?.toDouble();
    } catch (_) {
      return null;
    }
  }
}
