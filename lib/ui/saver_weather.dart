import 'package:flutter/material.dart';

import '../cards/env.dart';
import '../ha/connection.dart';
import '../ha/states.dart';
import '../util/fmt.dart';
import '../util/icons.dart';
import '../util/weather.dart';

/// The weather under the screensaver clock: the condition and the
/// temperature now, and - when [forecast] - today's high and low and the
/// chance of rain from the daily forecast.
///
/// The screensaver can stand for hours, so the current conditions follow the
/// entity like any card, and the forecast is one websocket subscription for
/// as long as the screensaver is up, dropped when it goes.
class SaverWeather extends StatefulWidget {
  const SaverWeather({
    super.key,
    required this.entity,
    required this.env,
    this.forecast = true,
    this.size = 64,
  });
  final String entity;
  final PanelEnv env;
  final bool forecast;

  /// The clock's digit height, so the weather scales with the clock.
  final double size;

  @override
  State<SaverWeather> createState() => _SaverWeatherState();
}

class _SaverWeatherState extends State<SaverWeather> {
  Map<dynamic, dynamic>? _today;
  Future<void> Function()? _unsub;
  bool _subscribing = false;

  @override
  void initState() {
    super.initState();
    widget.env.conn.status.addListener(_maybeSubscribe);
    _maybeSubscribe();
  }

  @override
  void dispose() {
    widget.env.conn.status.removeListener(_maybeSubscribe);
    _unsub?.call();
    super.dispose();
  }

  Future<void> _maybeSubscribe() async {
    if (!widget.forecast || _unsub != null || _subscribing) return;
    if (widget.env.conn.status.value != HaStatus.online) return;
    _subscribing = true;
    try {
      _unsub = await widget.env.conn.subscribe(
        {
          'type': 'weather/subscribe_forecast',
          'forecast_type': 'daily',
          'entity_id': widget.entity,
        },
        (ev) {
          final list = (ev as Map?)?['forecast'] as List?;
          if (!mounted || list == null || list.isEmpty || list.first is! Map) {
            return;
          }
          setState(() => _today = list.first as Map);
        },
      );
    } catch (_) {
      // an old core, or a provider without a daily forecast: the attribute,
      // or just the current conditions
    } finally {
      _subscribing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final k = widget.size / 64;
    const shadow = [
      Shadow(offset: Offset(0, 1), blurRadius: 4, color: Color(0x80000000)),
    ];
    return ValueListenableBuilder<HaState?>(
      valueListenable: widget.env.states.listen(widget.entity),
      builder: (context, s, _) {
        if (s == null || s.isBroken) return const SizedBox.shrink();
        final temp = s.numAttr('temperature');
        final unit = s.attr<String>('temperature_unit') ?? '°';
        final rainUnit = s.attr<String>('precipitation_unit') ?? 'mm';
        final fallback = s.attributes['forecast'];
        final today =
            _today ??
            (widget.forecast &&
                    fallback is List &&
                    fallback.isNotEmpty &&
                    fallback.first is Map
                ? fallback.first as Map
                : null);

        final second = <String>[];
        if (today != null) {
          final hi = today['temperature'];
          final lo = today['templow'];
          if (hi is num && lo is num) {
            second.add('${fmt(hi, 0)}° / ${fmt(lo, 0)}°');
          } else if (hi is num) {
            second.add('${fmt(hi, 0)}°');
          }
          final rain = rainOf(today, unit: rainUnit);
          if (rain != null && rain.wet) second.add('${rain.text} rain');
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  mdi(weatherIcons[s.state] ?? 'mdi:weather-cloudy'),
                  size: 22 * k,
                  color: Colors.white,
                  shadows: shadow,
                ),
                SizedBox(width: 8 * k),
                Flexible(
                  child: Text(
                    [
                      if (temp != null)
                        '${fmt(temp, 0)}${unit.startsWith('°') ? '°' : ' $unit'}',
                      conditionLabel(s.state),
                    ].join('  '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17 * k,
                      fontWeight: FontWeight.w600,
                      shadows: shadow,
                    ),
                  ),
                ),
              ],
            ),
            if (second.isNotEmpty) ...[
              SizedBox(height: 2 * k),
              Text(
                second.join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .8),
                  fontSize: 14 * k,
                  fontWeight: FontWeight.w500,
                  shadows: shadow,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
