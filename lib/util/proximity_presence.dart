import 'dart:async';
import 'dart:math' as math;

import '../config/screensaver.dart';

/// Level detector, separate from MQTT's telemetry/presence pulse semantics.
/// Never expires an unchanged value: Android sensors may be on-change only.
class ProximityPresence {
  ProximityPresence(this.config, this.onChanged);
  final ScreensaverConfig config;
  final void Function(bool) onChanged;
  bool near = false, _dark = false;
  int _hits = 0;
  final _rest = <bool, double>{};
  final _samples = <double>[];
  Timer? _leave;

  void dark(bool value) {
    if (_dark == value) return;
    _dark = value;
    _samples.clear();
    _hits = 0;
    _leave?.cancel();
    _leave = null;
  }

  void feed(double value) {
    if (!value.isFinite) return;
    bool enter, leave;
    if (config.proximityAbove != null || config.proximityBelow != null) {
      final above = config.proximityAbove, below = config.proximityBelow;
      enter =
          (above != null && value > above) || (below != null && value < below);
      leave =
          (above == null || value < above * .8) &&
          (below == null || value > below * 1.2);
    } else {
      var base = _rest[_dark];
      if (base == null) {
        // A known near reading must not become the new resting level.
        if (near) {
          base = _rest[!_dark];
        } else {
          _samples.add(value);
          if (_samples.length < 20) return;
          _samples.sort();
          base = _rest[_dark] = _samples[_samples.length ~/ 2];
          _samples.clear();
        }
      }
      if (base == null) return;
      final threshold = math.max(config.proximityDelta, base.abs() * .15);
      final distance = (value - base).abs();
      enter = distance > threshold;
      leave = distance < threshold * .8;
      if (!near && !enter) _rest[_dark] = base * .99 + value * .01;
    }
    if (!near) {
      _hits = enter ? _hits + 1 : 0;
      if (_hits >= 2) {
        near = true;
        onChanged(true);
      }
    } else if (leave) {
      _leave ??= Timer(const Duration(milliseconds: 500), () {
        _leave = null;
        near = false;
        _hits = 0;
        onChanged(false);
      });
    } else {
      _leave?.cancel();
      _leave = null;
    }
  }

  void dispose() {
    _leave?.cancel();
  }
}
