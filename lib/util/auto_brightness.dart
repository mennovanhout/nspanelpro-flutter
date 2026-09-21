import 'dart:math';

/// Screen brightness from the light sensor.
///
/// Perceived brightness is logarithmic, so the curve is too: 0 lx gives
/// [min], [daylightLux] and anything above gives [max], and in between the
/// log of the reading sets the level. 500 lx is a bright room; a panel in a
/// hallway that never sees the sun wants a lower daylight point so it still
/// reaches its maximum.
int autoBrightness({
  required double lux,
  required int min,
  required int max,
  required double daylightLux,
}) {
  final lo = min.clamp(0, 255);
  final hi = max.clamp(lo, 255);
  if (daylightLux <= 1 || lux <= 0) return lux <= 0 ? lo : hi;
  final t = (log(1 + lux) / log(1 + daylightLux)).clamp(0.0, 1.0);
  return (lo + (hi - lo) * t).round();
}

/// Smooths the sensor and decides when a change is worth applying: an
/// exponential average of the readings, and a new level only when it is at
/// least [step] away from the last one, so a cloud passing does not make the
/// panel flicker.
class BrightnessFollower {
  BrightnessFollower({this.alpha = 0.25, this.step = 6});
  final double alpha;
  final int step;
  double? _lux;
  int? _applied;

  double? get lux => _lux;
  int? get applied => _applied;

  /// Feeds a reading; returns the level to apply, or null for "leave it".
  int? feed(
    double lux, {
    required int min,
    required int max,
    required double daylightLux,
  }) {
    _lux = _lux == null ? lux : _lux! * (1 - alpha) + lux * alpha;
    final target = autoBrightness(
      lux: _lux!,
      min: min,
      max: max,
      daylightLux: daylightLux,
    );
    if (_applied != null && (target - _applied!).abs() < step) return null;
    _applied = target;
    return target;
  }

  /// Somebody set the brightness by hand: start again from there.
  void reset() {
    _applied = null;
  }
}
