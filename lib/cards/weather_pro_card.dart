import 'package:flutter/material.dart';

import '../config/dashboard.dart';
import '../ha/connection.dart';
import '../ha/states.dart';
import '../util/fmt.dart';
import '../util/icons.dart';
import 'env.dart';

const _days = ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'];

/// Sonoff NSPanel Pro style weather screen.
///
/// The background is one of the original Sonoff 1440x1440 weather images,
/// served by Home Assistant. The image is decoded at approximately the panel
/// display size rather than at its native 1440x1440 resolution.
class WeatherProCard extends StatefulWidget {
  const WeatherProCard({
    super.key,
    required this.config,
    required this.env,
  });

  final CardConfig config;
  final PanelEnv env;

  @override
  State<WeatherProCard> createState() => _WeatherProCardState();
}

class _WeatherProCardState extends State<WeatherProCard> {
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
      return;
    }

    _subscribing = true;

    try {
      _unsub = await widget.env.conn.subscribe(
        {
          'type': 'weather/subscribe_forecast',
          'forecast_type': c.str('forecast_type') ?? 'daily',
          'entity_id': entity,
        },
        (ev) {
          if (!mounted) return;

          setState(() {
            _forecast =
                (ev as Map?)?['forecast'] as List? ?? const [];
          });
        },
      );
    } catch (_) {
      // Older Home Assistant versions can fall back to the entity attribute.
    } finally {
      _subscribing = false;
    }
  }

  String _condition(HaState? s) {
    return s?.state.toLowerCase() ?? '';
  }

  bool _night(HaState? s) {
    return _condition(s) == 'clear-night';
  }

  String _background(HaState? s) {
    final condition = _condition(s);

    switch (condition) {
      case 'clear-night':
        return 'Star.png';

      case 'sunny':
      case 'clear':
        return 'Sunny.png';

      case 'partlycloudy':
        return 'Cloud.png';

      case 'cloudy':
      case 'fog':
      case 'windy':
      case 'windy-variant':
        return 'Cloud.png';

      case 'rainy':
      case 'pouring':
      case 'hail':
        return 'Rain.png';

      case 'snowy':
        return 'Snow.png';

      case 'snowy-rainy':
        return 'Snow.png';

      case 'lightning':
      case 'lightning-rainy':
        return 'Thunder.png';

      default:
        return 'Cloud.png';
    }
  }

  String _backgroundUrl(HaState? s) {
    final base = c.str('background_url') ??
        '/local/nspanel-weather/NSPanel';

    final file = _background(s);

    final url = base.endsWith('/')
        ? '$base$file'
        : '$base/$file';

    return widget.env.settings.resolve(url);
  }

  ImageProvider _imageProvider(String url, BuildContext context) {
    final size = MediaQuery.sizeOf(context) *
        MediaQuery.devicePixelRatioOf(context);

    return ResizeImage(
      NetworkImage(url),
      width: size.width.round(),
      height: size.height.round(),
      policy: ResizeImagePolicy.fit,
      allowUpscaling: false,
    );
  }

  String _conditionLabel(HaState? s) {
    final condition = _condition(s);

    const labels = {
      'sunny': 'Ensoleillé',
      'clear': 'Dégagé',
      'clear-night': 'Ciel dégagé',
      'partlycloudy': 'Partiellement nuageux',
      'cloudy': 'Nuageux',
      'rainy': 'Pluie',
      'pouring': 'Forte pluie',
      'snowy': 'Neige',
      'snowy-rainy': 'Neige et pluie',
      'lightning': 'Orage',
      'lightning-rainy': 'Orage et pluie',
      'hail': 'Grêle',
      'fog': 'Brouillard',
      'windy': 'Venteux',
      'windy-variant': 'Venteux',
    };

    return labels[condition] ??
        capitalise(condition.replaceAll('-', ' '));
  }

  List<dynamic> _forecastList(HaState? s) {
    if (!c.boolOr('show_forecast', true)) {
      return const [];
    }

    final source =
        _forecast ?? (s?.attributes['forecast'] as List?) ?? const [];

    return source
        .take(c.intOr('forecast_count', 4).clamp(1, 5))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<HaState?>(
      valueListenable: widget.env.states.listen(entity),
      builder: (context, s, _) {
        final broken = s == null || s.isBroken;

        final temperature = s?.numAttr('temperature');
        final unit =
            s?.attr<String>('temperature_unit') ?? '°';

        final humidity = s?.numAttr('humidity');
        final wind = s?.numAttr('wind_speed');
        final windUnit =
            s?.attr<String>('wind_speed_unit') ?? '';

        final condition = _conditionLabel(s);
        final night = _night(s);
        final forecast = _forecastList(s);
        final background = _backgroundUrl(s);

        return Container(
          height: c.numOr('height', 480),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius:
                BorderRadius.circular(c.numOr('radius', 0)),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // ----------------------------------------------------------------
              // Sonoff original weather background
              // ----------------------------------------------------------------
              Image(
                image: _imageProvider(background, context),
                fit: BoxFit.cover,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) =>
                    const ColoredBox(color: Colors.black),
              ),

              // ----------------------------------------------------------------
              // Slight darkening at the top and bottom to keep text readable.
              // ----------------------------------------------------------------
              const DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0.0, 0.22, 0.72, 1.0],
                    colors: [
                      Color(0x66000000),
                      Color(0x12000000),
                      Color(0x12000000),
                      Color(0x88000000),
                    ],
                  ),
                ),
              ),

              if (broken)
                const Positioned.fill(
                  child: ColoredBox(
                    color: Color(0x66000000),
                  ),
                ),

              // ----------------------------------------------------------------
              // Main weather information
              // ----------------------------------------------------------------
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 22, 24, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                              Text(
                                c.titleOr(
                                  friendlyName(s, entity),
                                ),
                                maxLines: 1,
                                overflow:
                                    TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w600,
                                  shadows: [
                                    Shadow(
                                      blurRadius: 5,
                                      color: Colors.black87,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                condition,
                                maxLines: 1,
                                overflow:
                                    TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Color(0xE6FFFFFF),
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                  shadows: [
                                    Shadow(
                                      blurRadius: 4,
                                      color: Colors.black87,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (!broken)
                          Icon(
                            mdi(
                              c.str('icon') ??
                                  weatherIcons[
                                      s?.state] ??
                                  'mdi:weather-cloudy',
                            ),
                            color: Colors.white,
                            size: 42,
                            shadows: const [
                              Shadow(
                                blurRadius: 6,
                                color: Colors.black87,
                              ),
                            ],
                          ),
                      ],
                    ),

                    const Spacer(),

                    // Temperature
                    Row(
                      crossAxisAlignment:
                          CrossAxisAlignment.end,
                      children: [
                        Text(
                          broken || temperature == null
                              ? '—'
                              : fmt(temperature, 0),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 78,
                            height: .9,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -3,
                            shadows: [
                              Shadow(
                                blurRadius: 8,
                                color: Colors.black87,
                              ),
                            ],
                          ),
                        ),
                        if (!broken &&
                            temperature != null)
                          Padding(
                            padding:
                                const EdgeInsets.only(
                              left: 5,
                              bottom: 7,
                            ),
                            child: Text(
                              unit,
                              style: const TextStyle(
                                color: Color(0xEEFFFFFF),
                                fontSize: 29,
                                fontWeight: FontWeight.w600,
                                shadows: [
                                  Shadow(
                                    blurRadius: 5,
                                    color: Colors.black87,
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),

                    const SizedBox(height: 8),

                    if (!broken)
                      Row(
                        children: [
                          if (humidity != null)
                            _info(
                              Icons.water_drop_outlined,
                              '${fmt(humidity, 0)} %',
                            ),
                          if (humidity != null &&
                              wind != null)
                            const SizedBox(width: 18),
                          if (wind != null)
                            _info(
                              Icons.air,
                              '${fmt(wind, 0)} $windUnit'
                                  .trim(),
                            ),
                          if (night)
                            ...[
                              const SizedBox(width: 18),
                              _info(
                                Icons.nightlight_round,
                                'Nuit',
                              ),
                            ],
                        ],
                      ),

                    if (forecast.isNotEmpty) ...[
                      const SizedBox(height: 16),

                      SizedBox(
                        height: 83,
                        child: Row(
                          children: [
                            for (var i = 0;
                                i < forecast.length;
                                i++) ...[
                              if (i > 0)
                                const SizedBox(width: 8),
                              Expanded(
                                child:
                                    _forecastDay(
                                  forecast[i],
                                  unit,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              if (broken)
                const Positioned(
                  right: 18,
                  top: 18,
                  child: Text(
                    'HORS LIGNE',
                    style: TextStyle(
                      color: Color(0xFFFF7777),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                      shadows: [
                        Shadow(
                          blurRadius: 4,
                          color: Colors.black,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _info(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 18,
          color: Colors.white,
          shadows: const [
            Shadow(
              blurRadius: 4,
              color: Colors.black87,
            ),
          ],
        ),
        const SizedBox(width: 5),
        Text(
          text,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            shadows: [
              Shadow(
                blurRadius: 4,
                color: Colors.black87,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _forecastDay(dynamic forecast, String unit) {
    final m = forecast is Map ? forecast : const {};

    final when = DateTime.tryParse(
      m['datetime']?.toString() ?? '',
    )?.toLocal();

    final condition =
        m['condition']?.toString() ?? 'cloudy';

    final high = m['temperature'] as num?;
    final low = m['templow'] as num?;

    final label = when == null
        ? ''
        : _days[when.weekday - 1];

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 5,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: .28),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: .18),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xE6FFFFFF),
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Icon(
            mdi(
              weatherIcons[condition] ??
                  'mdi:weather-cloudy',
            ),
            size: 21,
            color: Colors.white,
          ),
          const SizedBox(height: 1),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: fmt(high, 0),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (low != null)
                  TextSpan(
                    text: ' ${fmt(low, 0)}',
                    style: const TextStyle(
                      color: Color(0xB8FFFFFF),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
