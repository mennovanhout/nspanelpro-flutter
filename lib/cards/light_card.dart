import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';

import '../config/dashboard.dart';
import '../ha/states.dart';
import '../ui/fill_card.dart';
import '../ui/sheet.dart';
import '../ui/theme.dart';
import '../util/color.dart';
import '../util/icons.dart';
import 'echo.dart';
import 'env.dart';
import 'light_capabilities.dart';

class LightCard extends StatefulWidget {
  const LightCard({super.key, required this.config, required this.env});
  final CardConfig config;
  final PanelEnv env;

  @override
  State<LightCard> createState() => _LightCardState();
}

class _LightCardState extends State<LightCard> with EchoMixin {
  CardConfig get c => widget.config;
  String get entity => c.str('entity') ?? '';
  int get echoMs => c.intOr('echo_ms', 1500);

  HaState? get current => widget.env.states.get(entity);
  LightCapabilities get capabilities => LightCapabilities(current);

  List<CardConfig> get presets => c['presets'] is List
      ? c.maps('presets')
      : !capabilities.brightness
      ? const []
      : const [
          {'name': 'Low', 'brightness_pct': 15},
          {'name': 'Mid', 'brightness_pct': 50},
          {'name': 'Full', 'brightness_pct': 100},
        ];

  double _entityValue(HaState? s) {
    if (s == null || !s.isOn) return 0;
    final b = s.numAttr('brightness');
    return b == null ? 1 : (b / 255).clamp(0.0, 1.0);
  }

  /// The colour to paint the card in: the bulb's own when it has one and is
  /// on, otherwise the configured accent. An explicit accent always wins.
  Color _accent(HaState? s) {
    final explicit = parseHex(c.str('accent'));
    if (explicit != null) return explicit;
    if (c.boolOr('follow_color', true) && s != null && s.isOn) {
      final rgb = s.attributes['rgb_color'];
      if (rgb is List && rgb.length >= 3 && rgb.every((x) => x is num)) {
        return readableTint(rgb.cast<num>());
      }
    }
    return Ns.amber;
  }

  Future<void> _call(String service, [Map<String, dynamic>? data]) async {
    if (!capabilities.available) return;
    await widget.env.conn.callService('light', service, {
      'entity_id': entity,
      ...?data,
    });
  }

  void _commit(double v) {
    if (!capabilities.available || !capabilities.brightness) return;
    final pct = (v * 100).round();
    if (pct == 0) {
      _call('turn_off');
    } else {
      _call('turn_on', {'brightness_pct': pct});
    }
  }

  void _applyPreset(CardConfig p) {
    if (!capabilities.allowsPreset(current, p)) return;
    if (p['scene'] != null) {
      widget.env.conn.callService('scene', 'turn_on', {
        'entity_id': p['scene'],
      });
      return;
    }
    final pct = (p['brightness_pct'] as num?)?.toInt();
    if (pct == 0) {
      _call('turn_off');
      holdLocal(0, echoMs);
      return;
    }
    final data = <String, dynamic>{};
    if (pct != null) data['brightness_pct'] = pct;
    for (final k in ['color_temp_kelvin', 'rgb_color', 'effect']) {
      if (p[k] != null) data[k] = p[k];
    }
    _call('turn_on', data);
    if (pct != null) holdLocal(pct / 100, echoMs);
  }

  void _openSheet() {
    if (!capabilities.available) return;
    showControlSheetBuilder(
      context,
      (_) => ValueListenableBuilder<HaState?>(
        valueListenable: widget.env.states.listen(entity),
        builder: (_, s, _) {
          final caps = LightCapabilities(s);
          final on = s?.isOn ?? false;
          return ControlSheet(
            title: c.titleOr(friendlyName(s, entity)),
            state: !caps.available ? 'Unavailable' : (on ? 'On' : 'Off'),
            value: display(_entityValue(s)),
            accent: _accent(s),
            fromTop: false,
            showLevel: caps.brightness,
            enabled: caps.available,
            step: c.numOr('step', 5),
            actions: [
              for (final p in presets.take(3))
                SheetAction(
                  label: p.str('name') ?? '${p['brightness_pct']}%',
                  icon: mdi(p.str('icon'), MdiIcons.lightbulbOnOutline),
                  enabled: caps.allowsPreset(s, p),
                  run: () => _applyPreset(p),
                ),
              SheetAction(
                label: on ? 'Turn off' : 'Turn on',
                icon: on ? MdiIcons.lightbulbOff : MdiIcons.lightbulbOn,
                primary: true,
                run: () => _call(on ? 'turn_off' : 'turn_on'),
              ),
            ],
            onInput: (v) {
              if (mounted) holdLocal(v, echoMs);
            },
            onCommit: (v) {
              if (!mounted) return;
              holdLocal(v, echoMs);
              _commit(v);
            },
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<HaState?>(
      valueListenable: widget.env.states.listen(entity),
      builder: (context, s, _) {
        final caps = LightCapabilities(s);
        final broken = !caps.available;
        final on = s?.isOn ?? false;
        final v = display(_entityValue(s));
        final pct = (v * 100).round();
        final showPresets =
            c.boolOr('show_presets', true) && presets.isNotEmpty;

        return FillCard(
          height: c.numOr('height', 200),
          accent: _accent(s),
          fill: on && !broken ? (caps.brightness ? v : 1) : 0,
          fillOpacity: on && !broken ? 1 : 0,
          on: on && !broken,
          broken: broken,
          dragTravel: c['drag_travel'] is num && c.numOr('drag_travel', 0) > 0
              ? c.numOr('drag_travel', 0)
              : null,
          leading: IconBox(
            mdi(
              c.str('icon') ?? s?.attr<String>('icon'),
              on ? MdiIcons.lightbulbOn : MdiIcons.lightbulbOutline,
            ),
            on: on,
          ),
          value: on && caps.brightness ? ValueText('$pct', unit: '%') : null,
          title: c.titleOr(friendlyName(s, entity)),
          sub: broken
              ? 'Unavailable'
              : (on ? (caps.brightness ? 'On · $pct%' : 'On') : 'Off'),
          chips: showPresets
              ? [
                  for (final p in presets.take(4))
                    ChipSpec(
                      label: p.str('name') ?? '${p['brightness_pct']}%',
                      disabled: !caps.allowsPreset(s, p),
                      onTap: () => _applyPreset(p),
                    ),
                ]
              : const [],
          onTap: () => _call('toggle'),
          onLongPress: c.str('long_press') == 'none' ? () {} : _openSheet,
          onDragValue: !caps.brightness
              ? null
              : (nv) {
                  dragging = true;
                  setLocal(nv);
                },
          onDragCancel: () {
            dragging = false;
            setLocal(_entityValue(current));
          },
          onDragEnd: !caps.brightness
              ? null
              : (nv) {
                  dragging = false;
                  holdLocal(nv, echoMs);
                  _commit(nv);
                },
        );
      },
    );
  }
}
