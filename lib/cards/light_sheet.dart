import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';

import '../config/dashboard.dart';
import '../ha/states.dart';
import '../ui/sheet.dart';
import '../util/icons.dart';
import 'echo.dart';
import 'env.dart';
import 'light_capabilities.dart';
import 'light_controls.dart';

/// The same capability-aware light dialog from either a light or switch card.
class LightSheet extends StatefulWidget {
  const LightSheet({
    super.key,
    required this.config,
    required this.env,
    this.onLevelChanged,
    this.resolveValue,
  });
  final CardConfig config;
  final PanelEnv env;
  final ValueChanged<double>? onLevelChanged;

  /// A light card retains its existing echo when opening its own dialog.
  final double Function(double)? resolveValue;

  @override
  State<LightSheet> createState() => _LightSheetState();
}

class _LightSheetState extends State<LightSheet> with EchoMixin {
  LightControls get controls => LightControls(widget.config, widget.env);
  void _hold(double v) {
    holdLocal(v, widget.config.intOr('echo_ms', 1500));
    widget.onLevelChanged?.call(v);
  }

  void _preset(CardConfig p) {
    if (!controls.capabilities.allowsPreset(controls.current, p)) return;
    controls.applyPreset(p);
    final pct = p['brightness_pct'];
    if (pct is num && p['scene'] == null) _hold(pct / 100);
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<HaState?>(
    valueListenable: widget.env.states.listen(controls.entity),
    builder: (_, s, _) {
      final caps = LightCapabilities(s);
      final on = s?.isOn ?? false;
      return ControlSheet(
        title: widget.config.titleOr(friendlyName(s, controls.entity)),
        state: !caps.available ? 'Unavailable' : (on ? 'On' : 'Off'),
        value: (widget.resolveValue ?? display)(controls.entityValue(s)),
        accent: controls.accent(s),
        fromTop: false,
        showLevel: caps.brightness,
        enabled: caps.available,
        step: widget.config.numOr('step', 5),
        actions: [
          for (final p in controls.presets.take(3))
            SheetAction(
              label: p.str('name') ?? '${p['brightness_pct']}%',
              icon: mdi(p.str('icon'), MdiIcons.lightbulbOnOutline),
              enabled: caps.allowsPreset(s, p),
              run: () => _preset(p),
            ),
          SheetAction(
            label: on ? 'Turn off' : 'Turn on',
            icon: on ? MdiIcons.lightbulbOff : MdiIcons.lightbulbOn,
            primary: true,
            run: () => controls.call(on ? 'turn_off' : 'turn_on'),
          ),
        ],
        onInput: (v) {
          if (mounted) _hold(v);
        },
        onCommit: (v) {
          if (!mounted) return;
          _hold(v);
          controls.commit(v);
        },
      );
    },
  );
}
