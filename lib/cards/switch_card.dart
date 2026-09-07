import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';

import '../config/dashboard.dart';
import '../ha/states.dart';
import '../ui/info_shell.dart';
import '../ui/theme.dart';
import '../util/color.dart';
import '../util/icons.dart';
import 'env.dart';

/// [on, off] icons by domain, for entities that carry none of their own.
const _icons = {
  'switch': ('mdi:toggle-switch-variant', 'mdi:toggle-switch-variant-off'),
  'input_boolean': ('mdi:toggle-switch-variant', 'mdi:toggle-switch-variant-off'),
  'fan': ('mdi:fan', 'mdi:fan-off'),
  'automation': ('mdi:robot', 'mdi:robot-off'),
  'humidifier': ('mdi:air-humidifier', 'mdi:air-humidifier-off'),
  'siren': ('mdi:bullhorn', 'mdi:bullhorn-outline'),
  'remote': ('mdi:remote', 'mdi:remote-off'),
};

/// Things that are on or off: switches, input booleans, fans. The button
/// card's grid, but each tile reflects its entity - lit while on - and a tap
/// turns it the other way. The tap is echoed for `echo_ms` before HA answers,
/// so a slow round-trip never shows the old state under a finger, and the
/// card calls turn_on / turn_off for what it wants rather than toggle, so two
/// quick taps cannot race each other into the wrong state.
class SwitchCard extends StatefulWidget {
  const SwitchCard({super.key, required this.config, required this.env});
  final CardConfig config;
  final PanelEnv env;

  @override
  State<SwitchCard> createState() => _SwitchCardState();
}

class _Sw {
  _Sw(this.item);
  final CardConfig item;
  String get entity => item['entity'].toString();
  bool? local;
  DateTime localUntil = DateTime.fromMillisecondsSinceEpoch(0);
}

class _SwitchCardState extends State<SwitchCard> {
  CardConfig get c => widget.config;
  late final List<_Sw> _sws = _items().map(_Sw.new).toList();
  final _timers = <Timer>[];

  List<CardConfig> _items() {
    final raw = c['switches'] is List && c.listOr('switches').isNotEmpty
        ? c.listOr('switches')
        : (c['entity'] != null
            ? [
                {'entity': c['entity'], 'name': c.str('title') ?? c.str('name'), 'icon': c['icon']}
              ]
            : const []);
    // a bare `- switch.x` is the short form of `- entity: switch.x`
    final list = [
      for (final it in raw)
        if (it is String) <String, dynamic>{'entity': it} else if (it is Map) it.cast<String, dynamic>(),
    ];
    return list.where((i) => i['entity'] != null).take(6).toList();
  }

  int get _columns {
    if (_sws.isEmpty) return 1;
    return c.intOr('columns', 2).clamp(1, 3).clamp(1, _sws.length);
  }

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    super.dispose();
  }

  /// The state as shown: the tap's for echo_ms after it, then HA's.
  bool _isOn(_Sw s) {
    if (s.local != null && DateTime.now().isBefore(s.localUntil)) return s.local!;
    s.local = null;
    return widget.env.states.get(s.entity)?.state == 'on';
  }

  void _press(_Sw s) {
    if (c.boolOr('haptics', true)) HapticFeedback.lightImpact();
    final on = !_isOn(s);
    final echo = c.intOr('echo_ms', 1500);
    setState(() {
      s.local = on;
      s.localUntil = DateTime.now().add(Duration(milliseconds: echo));
    });
    widget.env.conn.callService('homeassistant', on ? 'turn_on' : 'turn_off', {'entity_id': s.entity});
    _timers.add(Timer(Duration(milliseconds: echo + 20), () {
      if (mounted) setState(() {});
    }));
  }

  @override
  Widget build(BuildContext context) {
    final accent = parseHex(c.str('accent')) ?? Ns.amber;
    return AnimatedBuilder(
      animation: Listenable.merge([for (final s in _sws) widget.env.states.listen(s.entity)]),
      builder: (context, _) => InfoShell(
        height: c.numOr('height', 200),
        accent: accent,
        padding: const EdgeInsets.all(12),
        child: TileGrid(
          columns: _columns,
          stretch: true,
          children: [for (final s in _sws) _tile(s, accent)],
        ),
      ),
    );
  }

  Widget _tile(_Sw sw, Color accent) {
    final s = widget.env.states.get(sw.entity);
    final broken = s == null || s.state == 'unavailable';
    final on = !broken && _isOn(sw);
    final compact = _columns == 3;
    final pair = _icons[sw.entity.split('.').first] ?? _icons['switch']!;
    final icon = broken
        ? MdiIcons.alertCircleOutline
        : mdi(sw.item.str('icon') ?? s.attr<String>('icon') ?? (on ? pair.$1 : pair.$2), MdiIcons.toggleSwitchVariant);
    final label = sw.item.str('name') ?? friendlyName(s, sw.entity);
    final state = broken ? 'Unavailable' : (on ? c.str('on_text') ?? 'On' : c.str('off_text') ?? 'Off');

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: broken ? null : () => _press(sw),
      child: Opacity(
        opacity: broken ? .45 : 1,
        child: Container(
          decoration: BoxDecoration(
            color: on ? accent.withValues(alpha: .16) : Ns.surface2,
            borderRadius: BorderRadius.circular(18),
          ),
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: compact ? 32 : 40, color: on ? accent : Ns.muted),
              const SizedBox(height: 8),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: on ? accent : Ns.text,
                      fontSize: compact ? 15 : 18,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -.2)),
              Text(state,
                  maxLines: 1,
                  style: TextStyle(color: Ns.muted, fontSize: compact ? 13 : 14, height: 1.3)),
            ],
          ),
        ),
      ),
    );
  }
}
