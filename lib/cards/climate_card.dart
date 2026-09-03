import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';

import '../config/dashboard.dart';
import '../ha/states.dart';
import '../ui/fill_card.dart';
import '../ui/sheet.dart';
import '../ui/theme.dart';
import '../util/color.dart';
import '../util/fmt.dart';
import '../util/icons.dart';
import 'echo.dart';
import 'env.dart';

const _hvacIcons = {
  'off': 'mdi:power',
  'heat': 'mdi:fire',
  'cool': 'mdi:snowflake',
  'heat_cool': 'mdi:sun-snowflake-variant',
  'auto': 'mdi:thermostat-auto',
  'dry': 'mdi:water-percent',
  'fan_only': 'mdi:fan',
};
const _hvacLabels = {
  'off': 'Off',
  'heat': 'Heat',
  'cool': 'Cool',
  'heat_cool': 'Auto',
  'auto': 'Auto',
  'dry': 'Dry',
  'fan_only': 'Fan',
};

/// The setpoint under the same thumb as everything else. Tap opens the sheet
/// rather than toggling - switching heating off by brushing past the panel is
/// a bad afternoon.
class ClimateCard extends StatefulWidget {
  const ClimateCard({super.key, required this.config, required this.env});
  final CardConfig config;
  final PanelEnv env;

  @override
  State<ClimateCard> createState() => _ClimateCardState();
}

class _ClimateCardState extends State<ClimateCard> with EchoMixin {
  CardConfig get c => widget.config;
  String get entity => c.str('entity') ?? '';
  int get echoMs => c.intOr('echo_ms', 1500);
  double get step => c.numOr('step', 0.5);

  List<CardConfig> get presets => c['presets'] is List
      ? c.maps('presets')
      : const [
          {'name': 'Eco', 'temperature': 17},
          {'name': 'Day', 'temperature': 20.5},
          {'name': 'Warm', 'temperature': 22},
        ];

  /// The thermostat's own limits unless the config narrows them - worth
  /// doing: 7-35 makes every drag a wild one.
  ({double min, double max}) _range(HaState? s) {
    final min = c['min'] is num ? c.numOr('min', 7) : (s?.numAttr('min_temp') ?? 7);
    var max = c['max'] is num ? c.numOr('max', 35) : (s?.numAttr('max_temp') ?? 35);
    if (max <= min) max = min + 1;
    return (min: min, max: max);
  }

  double _target(HaState? s) {
    final t = s?.numAttr('temperature');
    if (t != null) return t;
    final lo = s?.numAttr('target_temp_low');
    final hi = s?.numAttr('target_temp_high');
    if (lo != null && hi != null) return (lo + hi) / 2;
    return _range(s).min;
  }

  double _entityValue(HaState? s) {
    final r = _range(s);
    return ((_target(s) - r.min) / (r.max - r.min)).clamp(0.0, 1.0);
  }

  /// 0..1 back to degrees, rounded to the step so the panel never sends
  /// 20.4999 to a thermostat that shows whole halves.
  double _degrees(double v, HaState? s) {
    final r = _range(s);
    final raw = r.min + v * (r.max - r.min);
    return ((raw / step).round() * step).clamp(r.min, r.max);
  }

  Future<void> _call(String service, [Map<String, dynamic>? data]) =>
      widget.env.conn.callService('climate', service, {'entity_id': entity, ...?data});

  void _commit(double v, HaState? s) => _call('set_temperature', {'temperature': _degrees(v, s)});

  void _applyPreset(CardConfig p, HaState? s) {
    if (p['hvac_mode'] != null) _call('set_hvac_mode', {'hvac_mode': p['hvac_mode']});
    if (p['preset_mode'] != null) _call('set_preset_mode', {'preset_mode': p['preset_mode']});
    final t = (p['temperature'] as num?)?.toDouble();
    if (t != null) {
      _call('set_temperature', {'temperature': t});
      final r = _range(s);
      holdLocal(((t - r.min) / (r.max - r.min)).clamp(0.0, 1.0), echoMs);
    }
  }

  String _stateText(HaState? s) {
    if (s == null) return '';
    final now = s.numAttr('current_temperature');
    final action = s.attr<String>('hvac_action');
    final label = action != null ? capitalise(action) : (_hvacLabels[s.state] ?? s.state);
    return now != null ? 'Now ${fmt(now, 1)}° · $label' : label;
  }

  void _openSheet(HaState? s) {
    final modes = (s?.attributes['hvac_modes'] as List? ?? const [])
        .whereType<String>()
        .where(_hvacLabels.containsKey)
        .take(4)
        .toList();
    final r = _range(s);
    showControlSheet(
      context,
      title: c.titleOr(friendlyName(s, entity)),
      state: _stateText(s),
      value: display(_entityValue(s)),
      accent: parseHex(c.str('accent')) ?? Ns.ember,
      step: step / (r.max - r.min) * 100,
      actions: [
        for (final m in modes)
          SheetAction(
            label: _hvacLabels[m]!,
            icon: mdi(_hvacIcons[m]),
            primary: s?.state == m,
            run: () => _call('set_hvac_mode', {'hvac_mode': m}),
          ),
      ],
      onInput: (v) => holdLocal(v, echoMs),
      onCommit: (v) {
        holdLocal(v, echoMs);
        _commit(v, s);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<HaState?>(
      valueListenable: widget.env.states.listen(entity),
      builder: (context, s, _) {
        final broken = s == null || s.isBroken;
        final off = s == null || s.state == 'off';
        final v = display(_entityValue(s));
        final target = _degrees(v, s);
        final showPresets = c.boolOr('show_presets', true) && presets.isNotEmpty;

        return FillCard(
          height: c.numOr('height', 200),
          accent: parseHex(c.str('accent')) ?? Ns.ember,
          fill: broken ? 0 : v,
          fillOpacity: off || broken ? 0 : 1,
          on: !off && !broken,
          broken: broken,
          leading: IconBox(
            mdi(c.str('icon') ?? s?.attr<String>('icon') ?? _hvacIcons[s?.state ?? 'off'], MdiIcons.thermostat),
            on: !off && !broken,
          ),
          value: broken || off ? null : ValueText(fmt(target, 1), unit: '°'),
          title: c.titleOr(friendlyName(s, entity)),
          sub: broken ? 'Unavailable' : _stateText(s),
          chips: showPresets
              ? [
                  for (final p in presets.take(4))
                    ChipSpec(label: p.str('name') ?? '${p['temperature']}°', onTap: () => _applyPreset(p, s)),
                ]
              : const [],
          onTap: () => _openSheet(s),
          onLongPress: () => _openSheet(s),
          onDragValue: (nv) {
            dragging = true;
            setLocal(nv);
          },
          onDragEnd: (nv) {
            dragging = false;
            holdLocal(nv, echoMs);
            _commit(nv, s);
          },
        );
      },
    );
  }
}
