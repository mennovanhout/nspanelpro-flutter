import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../config/screensaver.dart';

/// Level detector, separate from MQTT's telemetry/presence pulse semantics.
/// Never expires an unchanged value: Android sensors may be on-change only.
class ProximityPresence {
  ProximityPresence(this.config, this.onChanged);
  final ScreensaverConfig config;
  final void Function(bool) onChanged;
  bool near = false, _dark = false, _saver = false;
  int _hits = 0;

  /// Readings to ignore after the screen changes (about two seconds at 10 Hz).
  /// The display's own light reaches the sensor, so the level moves when a
  /// dark photo replaces the dashboard or the backlight goes off, and that
  /// must not read as somebody walking up.
  static const _settle = 20;
  int _skip = 0;
  // Resting level per screen state: 0 dashboard, 1 screensaver, 2 backlight off.
  final _rest = <int, double>{};
  int get _mode => _dark ? 2 : (_saver ? 1 : 0);
  final _samples = <double>[];
  Timer? _leave;

  void dark(bool value) {
    if (_dark == value) return;
    _dark = value;
    _screenChanged();
  }

  void saver(bool value) {
    if (_saver == value) return;
    _saver = value;
    _screenChanged();
  }

  void _screenChanged() {
    _samples.clear();
    _hits = 0;
    _leave?.cancel();
    _leave = null;
    _skip = _settle;
    // Every photo and every night is different; only the dashboard's level
    // is worth keeping.
    if (_mode != 0) _rest.remove(_mode);
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
      if (_skip > 0) {
        _skip--;
        return;
      }
      var base = _rest[_mode];
      if (base == null) {
        // A known near reading must not become the new resting level.
        if (near) {
          base = _rest[0];
        } else {
          _samples.add(value);
          if (_samples.length < 20) return;
          _samples.sort();
          base = _rest[_mode] = _samples[_samples.length ~/ 2];
          _samples.clear();
          if (_mode != 0) debugPrint('proximity: resting at $base');
        }
      }
      if (base == null) return;
      final threshold = math.max(config.proximityDelta, base.abs() * .15);
      final distance = (value - base).abs();
      enter = distance > threshold;
      leave = distance < threshold * .8;
      if (!near && !enter) _rest[_mode] = base * .99 + value * .01;
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
