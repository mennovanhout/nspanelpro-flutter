import 'package:flutter/material.dart';

import '../config/dashboard.dart';
import '../ha/connection.dart';
import '../ha/states.dart';
import '../ui/fill_card.dart';
import '../ui/info_shell.dart';
import '../ui/theme.dart';
import '../util/color.dart';
import '../util/fmt.dart';
import '../util/icons.dart';
import 'env.dart';

const _conditionLabels = {
  'partlycloudy': 'Partly cloudy',
  'clear-night': 'Clear',
  'lightning-rainy': 'Thunder, rain',
  'snowy-rainy': 'Sleet',
  'windy-variant': 'Windy',
  'pouring': 'Heavy rain',
  'exceptional': 'Severe',
};
const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

/// Current conditions off the entity; the forecast over its own websocket
/// subscription (HA 2024.4+), with the old attribute as a fallback. The
/// subscription is released in dispose, because pages get rebuilt on every
/// swipe and a leaked one per swipe is a slow bleed.
class WeatherCard extends StatefulWidget {
  const WeatherCard({super.key, required this.config, required this.env});
  final CardConfig config;
  final PanelEnv env;

  @override
  State<WeatherCard> createState() => _WeatherCardState();
}

class _WeatherCardState extends State<WeatherCard> {
  CardConfig get c => widget.config;
  String get entity => c.str('entity') ?? '';

  List<dynamic>? _forecast;
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
    if (!c.boolOr('show_forecast', true)) return;
    if (_unsub != null || _subscribing) return;
    if (widget.env.conn.status.value != HaStatus.online) {
      _unsub = null;
      return;
    }
    _subscribing = true;
    try {
      _unsub = await widget.env.conn.subscribe({
        'type': 'weather/subscribe_forecast',
        'forecast_type': c.str('forecast_type') ?? 'daily',
        'entity_id': entity,
      }, (ev) {
        if (!mounted) return;
        setState(() => _forecast = (ev as Map?)?['forecast'] as List? ?? const []);
      });
    } catch (_) {
      // Older core: the attribute fallback below covers it.
    } finally {
      _subscribing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<HaState?>(
      valueListenable: widget.env.states.listen(entity),
      builder: (context, s, _) {
        final broken = s == null || s.isBroken;
        final temp = s?.numAttr('temperature');
        final unit = s?.attr<String>('temperature_unit') ?? '°';
        final bits = <String>[];
        if (s != null && s.state.isNotEmpty) {
          bits.add(_conditionLabels[s.state] ?? capitalise(s.state.replaceAll('-', ' ')));
        }
        final hum = s?.numAttr('humidity');
        if (hum != null) bits.add('${fmt(hum, 0)}%');
        final wind = s?.numAttr('wind_speed');
        if (wind != null) bits.add('${fmt(wind, 0)} ${s?.attr<String>('wind_speed_unit') ?? ''}'.trim());

        final list = (c.boolOr('show_forecast', true)
                ? (_forecast ?? (s?.attributes['forecast'] as List?) ?? const [])
                : const [])
            .take(c.intOr('forecast_count', 4).clamp(1, 5))
            .toList();

        return InfoShell(
          height: c.numOr('height', 240),
          accent: parseHex(c.str('accent')) ?? Ns.sky,
          broken: broken,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  IconBox(mdi(c.str('icon') ?? weatherIcons[s?.state] ?? 'mdi:weather-cloudy')),
                  const Spacer(),
                  BigValue(temp == null ? '—' : fmt(temp, 0), unit: temp == null ? '' : unit),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(c.titleOr(friendlyName(s, entity)), maxLines: 1, overflow: TextOverflow.ellipsis, style: nameStyle),
                  Text(broken ? 'Unavailable' : bits.join(' · '),
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: subStyle),
                  if (list.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    Row(children: [
                      for (var i = 0; i < list.length; i++) ...[
                        if (i > 0) const SizedBox(width: 8),
                        Expanded(child: _day(list[i], unit)),
                      ],
                    ]),
                  ],
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _day(dynamic f, String unit) {
    final m = f is Map ? f : const {};
    final when = DateTime.tryParse(m['datetime']?.toString() ?? '')?.toLocal();
    final hourly = c.str('forecast_type') == 'hourly';
    final label = when == null
        ? ''
        : (hourly ? when.hour.toString().padLeft(2, '0') : _days[when.weekday - 1]);
    final hi = m['temperature'] as num?;
    final lo = m['templow'] as num?;
    return Container(
      padding: const EdgeInsets.fromLTRB(2, 8, 2, 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(label, style: const TextStyle(color: Ns.muted, fontSize: 12)),
          const SizedBox(height: 2),
          Icon(mdi(weatherIcons[m['condition']] ?? 'mdi:weather-cloudy'), size: 22, color: Ns.text),
          const SizedBox(height: 2),
          Text.rich(
            TextSpan(children: [
              TextSpan(text: fmt(hi, 0), style: const TextStyle(color: Ns.text, fontWeight: FontWeight.w700)),
              if (lo != null)
                TextSpan(
                    text: ' ${fmt(lo, 0)}',
                    style: TextStyle(color: Ns.text.withValues(alpha: .55), fontWeight: FontWeight.w500)),
            ]),
            style: const TextStyle(fontSize: 15, fontFeatures: Ns.tabular),
          ),
        ],
      ),
    );
  }
}
