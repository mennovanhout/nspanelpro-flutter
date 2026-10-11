import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ha/states.dart';
import 'light_capabilities.dart';

enum LightChannel { brightness, temperature, hue, saturation }

/// Shared normalized range policy. HA receives one property per command.
class LightColor {
  LightColor(
    this.state, {
    Map<String, dynamic>? attributes,
    this.lastValues = false,
  }) : attributes = attributes ?? state?.attributes ?? const {},
       caps = LightCapabilities(state);
  final Map<String, dynamic> attributes;
  final bool lastValues;
  final HaState? state;
  final LightCapabilities caps;
  double? number(String key) {
    final v = attributes[key];
    return v is num && v.isFinite ? v.toDouble() : null;
  }

  ({double min, double max})? get range {
    var lo = number('min_color_temp_kelvin');
    var hi = number('max_color_temp_kelvin');
    if (lo == null || hi == null) {
      final minM = number('min_mireds'), maxM = number('max_mireds');
      if (minM == null || maxM == null || minM <= 0 || maxM <= minM) {
        return null;
      }
      lo = 1000000 / maxM;
      hi = 1000000 / minM;
    }
    return lo > 0 && hi.floorToDouble() > lo.ceilToDouble()
        ? (min: lo.ceilToDouble(), max: hi.floorToDouble())
        : null;
  }

  bool get color =>
      caps.color &&
      !(state?.isOn == true && state?.attributes['color_mode'] == 'brightness');
  bool get white =>
      caps.brightness &&
      !(state?.isOn == true &&
          state?.attributes['color_mode'] == 'brightness') &&
      (caps.modes.contains('color_temp') || caps.modes.contains('rgbww')) &&
      range != null;
  List<String> get effects {
    final list = state?.attributes['effect_list'];
    return state?.supports(4) == true && list is List
        ? list.whereType<String>().toList()
        : [];
  }

  bool allows(LightChannel ch) => switch (ch) {
    LightChannel.brightness => caps.brightness,
    LightChannel.temperature => white,
    _ => color,
  };

  (double, double) get hs {
    final hs = attributes['hs_color'];
    if (hs is List &&
        hs.length == 2 &&
        hs.every((v) => v is num && v.isFinite)) {
      return (
        (hs[0] as num).toDouble() % 360,
        (hs[1] as num).toDouble().clamp(0, 100),
      );
    }
    final rgb = attributes['rgb_color'];
    if (rgb is List &&
        rgb.length >= 3 &&
        rgb.take(3).every((v) => v is num && v.isFinite)) {
      final hsv = HSVColor.fromColor(
        Color.fromARGB(
          255,
          (rgb[0] as num).round().clamp(0, 255),
          (rgb[1] as num).round().clamp(0, 255),
          (rgb[2] as num).round().clamp(0, 255),
        ),
      );
      return (hsv.hue, hsv.saturation * 100);
    }
    return (0, 100);
  }

  double value(LightChannel ch) => switch (ch) {
    LightChannel.brightness =>
      state?.isOn == true
          ? ((number('brightness') ?? 255) / 255).clamp(0, 1)
          : lastValues && state?.state == 'off'
          ? ((number('brightness') ?? 0) / 255).clamp(0, 1)
          : 0,
    LightChannel.hue => hs.$1 / 360,
    LightChannel.saturation => hs.$2 / 100,
    LightChannel.temperature =>
      range == null
          ? .5
          : (((number('color_temp_kelvin') ??
                            ((number('color_temp') ?? 0) > 0
                                ? 1000000 / number('color_temp')!
                                : (range!.min + range!.max) / 2)) -
                        range!.min) /
                    (range!.max - range!.min))
                .clamp(0, 1),
  };

  double snap(LightChannel ch, double v) {
    v = v.clamp(0, 1);
    if (ch == LightChannel.hue) return ((v * 360).round() % 360) / 360;
    if (ch == LightChannel.temperature && range != null) {
      final r = range!;
      if (r.max <= r.min) return 0;
      return ((r.min + v * (r.max - r.min)).round() - r.min) / (r.max - r.min);
    }
    return (v * 100).round() / 100;
  }

  Map<String, dynamic> payload(
    LightChannel ch,
    Map<LightChannel, double> values,
  ) => switch (ch) {
    LightChannel.brightness => {'brightness_pct': (values[ch]! * 100).round()},
    LightChannel.temperature => {
      'color_temp_kelvin':
          (range!.min + values[ch]! * (range!.max - range!.min)).round(),
    },
    _ => {
      'hs_color': [
        ((values[LightChannel.hue]! * 360).round() % 360),
        (values[LightChannel.saturation]! * 100).round(),
      ],
    },
  };

  static Color kelvin(double k) {
    final t = k.clamp(1000, 40000) / 100;
    double channel(double v) => v.clamp(0, 255);
    return Color.fromARGB(
      255,
      channel(t <= 66 ? 255 : 329.698727446 * math.pow(t - 60, -.1332047592))
          .round(),
      channel(
        t <= 66
            ? 99.4708025861 * math.log(t) - 161.1195681661
            : 288.1221695283 * math.pow(t - 60, -.0755148492),
      ).round(),
      channel(
        t >= 66
            ? 255
            : t <= 19
            ? 0
            : 138.5177312231 * math.log(t - 10) - 305.0447927307,
      ).round(),
    );
  }
}
