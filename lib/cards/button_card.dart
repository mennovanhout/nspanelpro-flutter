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

/// What to call for a bare entity, by domain. Anything not listed toggles.
const _service = {
  'script': ('script', 'turn_on'),
  'scene': ('scene', 'turn_on'),
  'automation': ('automation', 'trigger'),
  'button': ('button', 'press'),
  'input_button': ('input_button', 'press'),
  'vacuum': ('vacuum', 'start'),
};

const _domainIcons = {
  'script': 'mdi:script-text-outline',
  'scene': 'mdi:palette-outline',
  'automation': 'mdi:robot-outline',
};

/// Scenes, scripts, automations. A script has no state to reflect, so the
/// button supplies the acknowledgement itself: a haptic, and a tick held for
/// feedback_ms. `confirm` asks for a second tap, because a wall panel is
/// exactly the thing people brush past.
class ButtonCard extends StatefulWidget {
  const ButtonCard({super.key, required this.config, required this.env});
  final CardConfig config;
  final PanelEnv env;

  @override
  State<ButtonCard> createState() => _ButtonCardState();
}

class _Btn {
  _Btn(this.item);
  final CardConfig item;
  bool armed = false;
  bool fired = false;
}

class _ButtonCardState extends State<ButtonCard> {
  CardConfig get c => widget.config;
  late final List<_Btn> _btns = _items().map(_Btn.new).toList();
  final _timers = <Timer>[];

  List<CardConfig> _items() {
    final list = c['buttons'] is List && c.listOr('buttons').isNotEmpty
        ? c.maps('buttons')
        : (c['entity'] != null
            ? [
                {'entity': c['entity'], 'name': c.str('title') ?? c.str('name'), 'icon': c['icon']}
              ]
            : <CardConfig>[]);
    return list.where((i) => i['entity'] != null || i['service'] != null).take(6).toList();
  }

  int get _columns {
    if (_btns.length == 1) return 1;
    return c.intOr('columns', 2).clamp(1, 3);
  }

  void _later(VoidCallback fn, int ms) => _timers.add(Timer(Duration(milliseconds: ms), fn));

  @override
  void dispose() {
    for (final t in _timers) {
      t.cancel();
    }
    super.dispose();
  }

  void _fire(CardConfig item) {
    final explicit = item.str('service');
    final entity = item.str('entity');
    String domain, service;
    if (explicit != null && explicit.contains('.')) {
      final parts = explicit.split('.');
      domain = parts[0];
      service = parts[1];
    } else {
      final by = entity == null ? null : _service[entity.split('.').first];
      domain = by?.$1 ?? 'homeassistant';
      service = by?.$2 ?? 'toggle';
    }
    final data = <String, dynamic>{...?(item['data'] as Map?)?.cast<String, dynamic>()};
    if (entity != null && !data.containsKey('entity_id')) data['entity_id'] = entity;
    widget.env.conn.callService(domain, service, data);
  }

  void _press(_Btn b) {
    if (c.boolOr('haptics', true)) HapticFeedback.lightImpact();
    final wantsConfirm = b.item['confirm'] is bool ? b.item['confirm'] as bool : c.boolOr('confirm', false);
    if (wantsConfirm && !b.armed) {
      setState(() => b.armed = true);
      _later(() {
        if (mounted) setState(() => b.armed = false);
      }, 3000);
      return;
    }
    b.armed = false;
    _fire(b.item);
    setState(() => b.fired = true);
    _later(() {
      if (mounted) setState(() => b.fired = false);
    }, c.intOr('feedback_ms', 1200));
  }

  @override
  Widget build(BuildContext context) {
    final ids = [for (final b in _btns) b.item.str('entity')].whereType<String>().toList();
    final accent = parseHex(c.str('accent')) ?? Ns.mint;
    return AnimatedBuilder(
      animation: Listenable.merge([for (final id in ids) widget.env.states.listen(id)]),
      builder: (context, _) => InfoShell(
        height: c.numOr('height', 200),
        accent: accent,
        padding: const EdgeInsets.all(12),
        child: TileGrid(
          columns: _columns,
          stretch: true,
          children: [for (final b in _btns) _tile(b, accent)],
        ),
      ),
    );
  }

  Widget _tile(_Btn b, Color accent) {
    final entity = b.item.str('entity');
    final s = entity == null ? null : widget.env.states.get(entity);
    // Not isBroken(): `unknown` is the normal resting state of a scene that has
    // never been fired. Only a missing or unavailable entity is a dead button.
    final broken = entity != null && (s == null || s.state == 'unavailable');
    final running = s != null && s.state == 'on' && entity!.startsWith('script.');
    final hot = b.fired || running;
    final compact = _columns == 3;

    final label = b.armed
        ? (b.item.str('confirm_text') ?? c.str('confirm_text') ?? 'Tap again')
        : (b.item.str('name') ?? (entity != null ? friendlyName(s, entity) : 'Run'));
    final icon = broken
        ? MdiIcons.alertCircleOutline
        : b.fired
            ? MdiIcons.check
            : mdi(b.item.str('icon') ?? s?.attr<String>('icon') ?? _domainIcons[entity?.split('.').first],
                MdiIcons.gestureTapButton);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: broken ? null : () => _press(b),
      child: Opacity(
        opacity: broken ? .45 : 1,
        child: Container(
          decoration: BoxDecoration(
            color: hot ? accent.withValues(alpha: .16) : Ns.surface2,
            borderRadius: BorderRadius.circular(18),
          ),
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: compact ? 32 : 40, color: hot ? accent : Ns.muted),
              const SizedBox(height: 8),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: hot || b.armed ? accent : Ns.text,
                      fontSize: compact ? 15 : 18,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -.2)),
            ],
          ),
        ),
      ),
    );
  }
}
