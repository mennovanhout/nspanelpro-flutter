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
    case 'nspanel-screensaver':
      // config for the app, read elsewhere; nothing to draw
      return const SizedBox.shrink();
    case 'vertical-stack':
      return VStack(children: [for (final x in c.maps('cards')) buildCard(x, env)]);
    case 'horizontal-stack':
      return HStack(children: [for (final x in c.maps('cards')) buildCard(x, env)]);
    case 'grid':
      return GridStack(
        columns: c.intOr('columns', 3).clamp(1, 4),
        children: [for (final x in c.maps('cards')) buildCard(x, env)],
      );
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

/// Lovelace's vertical-stack: cards one above the other with the panel gap.
class VStack extends StatelessWidget {
  const VStack({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: Ns.gap),
            children[i],
          ],
        ],
      );
}

/// Lovelace's horizontal-stack: equal columns. Each card keeps its own
/// configured height, so give the children the same one or the row is as
/// tall as the tallest and the rest sit at the top.
class HStack extends StatelessWidget {
  const HStack({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: Ns.gap),
            Expanded(child: children[i]),
          ],
        ],
      );
}

/// Lovelace's grid card: `columns` across, wrapping. `square` is ignored;
/// the cards have heights of their own.
class GridStack extends StatelessWidget {
  const GridStack({super.key, required this.children, required this.columns});
  final List<Widget> children;
  final int columns;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += columns) {
      rows.add(HStack(children: [
        for (var j = 0; j < columns; j++) i + j < children.length ? children[i + j] : const SizedBox(),
      ]));
    }
    return VStack(children: rows);
  }
}
