import '../config/dashboard.dart';
import '../ha/states.dart';

/// Capability comes from HA's supported modes, never from a possibly absent
/// brightness value. An on/off effect can temporarily restrict a dimmable light.
class LightCapabilities {
  LightCapabilities(HaState? state)
    : available = state != null && !state.isBroken,
      modes = switch (state?.attributes['supported_color_modes']) {
        List values => values.whereType<String>().toSet(),
        _ => <String>{},
      },
      restricted =
          state?.isOn == true && state?.attr<String>('color_mode') == 'onoff';

  final bool available, restricted;
  final Set<String> modes;
  static const _dimmable = {
    'brightness',
    'color_temp',
    'hs',
    'xy',
    'rgb',
    'rgbw',
    'rgbww',
    'white',
  };
  static const _color = {'hs', 'xy', 'rgb', 'rgbw', 'rgbww'};

  bool get brightness =>
      !restricted && !modes.contains('onoff') && modes.any(_dimmable.contains);
  bool get color => brightness && modes.any(_color.contains);
  bool get temperature => brightness && (modes.contains('color_temp') || color);

  bool allowsPreset(HaState? state, CardConfig preset) {
    if (!available) return false;
    if (preset['scene'] != null) return true;
    // This is the existing explicit off preset; no other fields are sent.
    if (preset['brightness_pct'] == 0) return true;
    if (preset.containsKey('brightness_pct') && !brightness) return false;
    if (preset.containsKey('rgb_color') && !color) return false;
    if (preset.containsKey('color_temp_kelvin') && !temperature) return false;
    if (preset.containsKey('effect')) {
      final effects = state?.attributes['effect_list'];
      if (state?.supports(4) != true ||
          effects is! List ||
          !effects.contains(preset['effect'])) {
        return false;
      }
    }
    return true;
  }
}
