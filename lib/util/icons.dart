import 'package:flutter/widgets.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';

import '../ha/states.dart';

/// `mdi:lightbulb-on` -> the glyph. Unknown names fall back rather than
/// throwing, because an icon typo in a config should never blank a card.
IconData mdi(String? name, [IconData? fallback]) {
  if (name != null && name.isNotEmpty) {
    final key = name.startsWith('mdi:') ? name.substring(4) : name;
    final found = MdiIcons.fromString(key);
    if (found != null) return found;
  }
  return fallback ?? MdiIcons.eyeOutline;
}

const _classIcons = {
  'temperature': 'mdi:thermometer',
  'humidity': 'mdi:water-percent',
  'pressure': 'mdi:gauge',
  'power': 'mdi:flash',
  'energy': 'mdi:lightning-bolt',
  'battery': 'mdi:battery',
  'illuminance': 'mdi:brightness-5',
  'carbon_dioxide': 'mdi:molecule-co2',
  'wind_speed': 'mdi:weather-windy',
  'moisture': 'mdi:water-alert',
  'smoke': 'mdi:smoke-detector',
  'problem': 'mdi:alert',
  'occupancy': 'mdi:account',
};

/// Openable things get an icon per state - a door-open glyph next to the
/// word "Closed" is the kind of detail that makes a panel feel wrong.
const _stateIcons = {
  'door': ['mdi:door-closed', 'mdi:door-open'],
  'window': ['mdi:window-closed', 'mdi:window-open'],
  'garage_door': ['mdi:garage', 'mdi:garage-open'],
  'opening': ['mdi:door-closed', 'mdi:door-open'],
  'motion': ['mdi:motion-sensor-off', 'mdi:motion-sensor'],
};

/// The icon a sensor or status tile chooses for itself.
String classIcon(HaState? s, String entityId) {
  final c = s?.deviceClass;
  final state = s?.state ?? '';
  final open = state == 'on' || state == 'open' || state == 'opening';
  if (c != null && _stateIcons.containsKey(c)) return _stateIcons[c]![open ? 1 : 0];
  if (c != null && _classIcons.containsKey(c)) return _classIcons[c]!;
  final domain = entityId.split('.').first;
  if (domain == 'lock') return state == 'locked' ? 'mdi:lock' : 'mdi:lock-open';
  if (domain == 'cover') {
    return (c == 'garage' || c == 'garage_door')
        ? (open ? 'mdi:garage-open' : 'mdi:garage')
        : 'mdi:window-shutter';
  }
  if (domain == 'person' || domain == 'device_tracker') return 'mdi:account';
  return 'mdi:eye-outline';
}

const weatherIcons = {
  'clear-night': 'mdi:weather-night',
  'cloudy': 'mdi:weather-cloudy',
  'fog': 'mdi:weather-fog',
  'hail': 'mdi:weather-hail',
  'lightning': 'mdi:weather-lightning',
  'lightning-rainy': 'mdi:weather-lightning-rainy',
  'partlycloudy': 'mdi:weather-partly-cloudy',
  'pouring': 'mdi:weather-pouring',
  'rainy': 'mdi:weather-rainy',
  'snowy': 'mdi:weather-snowy',
  'snowy-rainy': 'mdi:weather-snowy-rainy',
  'sunny': 'mdi:weather-sunny',
  'windy': 'mdi:weather-windy',
  'windy-variant': 'mdi:weather-windy',
  'exceptional': 'mdi:alert-circle-outline',
};
