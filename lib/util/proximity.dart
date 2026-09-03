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

/// Decides, reading by reading, when the proximity sensor says somebody
/// walked up to a sleeping panel.
///
/// The sensor reports a graded level whose resting value depends on where
/// the panel hangs - 58 on one wall in this house, 410 on another - and
/// whose noise grows with it. The display's own light also reaches the
/// sensor, so the level shifts when the bright dashboard is replaced by a
/// dark photo. Hence: the first [skip] readings after going to sleep are
/// ignored while the screen changes, the next [baseline] readings set the
/// resting level, and an approach is [confirm] readings in a row that are
/// further from it than [delta] or [relative] times the resting level,
/// whichever is larger. Between approaches the resting level drifts slowly
/// with the readings. Absolute [below] / [above] bounds bypass all of that.
class ApproachDetector {
  ApproachDetector({
    required this.delta,
    this.below,
    this.above,
    this.relative = 0.15,
    this.skip = 20,
    this.baseline = 20,
    this.confirm = 2,
  });

  final double delta;
  final double? below;
  final double? above;
  final double relative;
  final int skip;
  final int baseline;
  final int confirm;

  final _samples = <double>[];
  var _seen = 0;
  var _hits = 0;
  double? _resting;

  /// The resting level once it is known.
  double? get resting => _resting;

  /// Feeds one reading; true when it completes an approach.
  bool feed(double v) {
    if (below != null && v < below!) return true;
    if (above != null && v > above!) return true;
    if (below != null || above != null) return false;
    if (_seen++ < skip) return false;
    if (_resting == null) {
      _samples.add(v);
      if (_samples.length < baseline) return false;
      final sorted = [..._samples]..sort();
      _resting = sorted[sorted.length ~/ 2];
      return false;
    }
    final threshold = delta > _resting! * relative ? delta : _resting! * relative;
    if ((v - _resting!).abs() > threshold) {
      return ++_hits >= confirm;
    }
    _hits = 0;
    _resting = _resting! * 0.99 + v * 0.01;
    return false;
  }
}
