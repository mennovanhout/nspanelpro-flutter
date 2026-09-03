import 'package:flutter/material.dart';

import '../config/dashboard.dart';
import '../ui/theme.dart';
import 'button_card.dart';
import 'climate_card.dart';
import 'clock_card.dart';
import 'cover_card.dart';
import 'env.dart';
import 'light_card.dart';
import 'media_card.dart';
import 'sensor_card.dart';
import 'sensors_card.dart';
import 'status_card.dart';
import 'weather_card.dart';

/// `custom:nspanel-*` -> a widget. Anything else says so rather than
/// vanishing, so a dashboard that mixes in an unsupported card still shows
/// where it was.
Widget buildCard(CardConfig c, PanelEnv env) {
  switch (cardType(c)) {
    case 'nspanel-light-card':
      return LightCard(config: c, env: env);
    case 'nspanel-cover-card':
      return CoverCard(config: c, env: env);
    case 'nspanel-climate-card':
      return ClimateCard(config: c, env: env);
    case 'nspanel-media-card':
      return MediaCard(config: c, env: env);
    case 'nspanel-button-card':
      return ButtonCard(config: c, env: env);
    case 'nspanel-sensor-card':
      return SensorCard(config: c, env: env);
    case 'nspanel-sensors-card':
      return SensorsCard(config: c, env: env);
    case 'nspanel-status-card':
      return StatusCard(config: c, env: env);
    case 'nspanel-weather-card':
      return WeatherCard(config: c, env: env);
    case 'nspanel-clock-card':
      return ClockCard(config: c, env: env);
    default:
      return UnsupportedCard(type: c['type']?.toString() ?? '(no type)');
  }
}

class UnsupportedCard extends StatelessWidget {
  const UnsupportedCard({super.key, required this.type});
  final String type;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: Ns.surface,
          borderRadius: BorderRadius.circular(Ns.radius),
          border: Border.all(color: Ns.danger.withValues(alpha: .5)),
        ),
        child: Text('Not rendered here: $type',
            style: const TextStyle(color: Ns.danger, fontSize: 14, height: 1.4)),
      );
}
