import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';

import '../config/dashboard.dart';
import '../ha/states.dart';
import '../ui/fill_card.dart';
import '../ui/sheet.dart';
import '../util/icons.dart';
import 'echo.dart';
import 'env.dart';
import 'light_capabilities.dart';
import 'light_controls.dart';
import 'light_sheet.dart';

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

  LightControls get controls => LightControls(c, widget.env);
  HaState? get current => controls.current;
  LightCapabilities get capabilities => controls.capabilities;
  List<CardConfig> get presets => controls.presets;

  void _applyPreset(CardConfig p) {
    if (!capabilities.allowsPreset(current, p)) return;
    controls.applyPreset(p);
    final pct = p['brightness_pct'];
    if (pct is num && p['scene'] == null) holdLocal(pct / 100, echoMs);
  }

  void _openSheet() {
    if (!capabilities.available) return;
    showControlSheetBuilder(
      context,
      (_) => LightSheet(
        config: c,
        env: widget.env,
        resolveValue: display,
        onLevelChanged: (v) {
          if (mounted) holdLocal(v, echoMs);
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
        final v = display(controls.entityValue(s));
        final pct = (v * 100).round();
        final showPresets =
            c.boolOr('show_presets', true) && presets.isNotEmpty;

        return FillCard(
          height: c.numOr('height', 200),
          accent: controls.accent(s),
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
          onTap: () => controls.call('toggle'),
          onLongPress: c.str('long_press') == 'none' ? () {} : _openSheet,
          onDragValue: !caps.brightness
              ? null
              : (nv) {
                  dragging = true;
                  setLocal(nv);
                },
          onDragCancel: () {
            dragging = false;
            setLocal(controls.entityValue(current));
          },
          onDragEnd: !caps.brightness
              ? null
              : (nv) {
                  dragging = false;
                  holdLocal(nv, echoMs);
                  controls.commit(nv);
                },
        );
      },
    );
  }
}
