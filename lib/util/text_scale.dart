import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// The panel's text size setting. Small print gets all of it and the big
/// numbers none, tapering in between: the small text is what is hard to read
/// from across a room, and a 64 px temperature grown by 40% only pushes the
/// rest of its card off the bottom. Android 14's own font scale works this way.
class PanelTextScaler extends TextScaler {
  const PanelTextScaler(this.factor);

  final double factor;

  static const _full = 18.0, _none = 40.0;

  @override
  double scale(double fontSize) {
    final share = ((_none - fontSize) / (_none - _full)).clamp(0.0, 1.0);
    final scaled = fontSize * (1 + (factor - 1) * share);
    // never past where the taper starts handing the size back
    return math.max(scaled, math.min(fontSize, _none));
  }

  @override
  double get textScaleFactor => factor;

  @override
  bool operator ==(Object other) =>
      other is PanelTextScaler && other.factor == factor;

  @override
  int get hashCode => factor.hashCode;

  @override
  String toString() => 'PanelTextScaler($factor)';
}
