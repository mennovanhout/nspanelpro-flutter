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

const _setPosition = 4;

class CoverCard extends StatefulWidget {
  const CoverCard({super.key, required this.config, required this.env});
  final CardConfig config;
  final PanelEnv env;

  @override
  State<CoverCard> createState() => _CoverCardState();
}

class _CoverCardState extends State<CoverCard> with EchoMixin {
  CardConfig get c => widget.config;
  String get entity => c.str('entity') ?? '';
  int get echoMs => c.intOr('echo_ms', 1500);

  List<CardConfig> get presets => c['presets'] is List
      ? c.maps('presets')
      : const [
          {'name': 'Open', 'position': 100},
          {'name': 'Half', 'position': 50},
          {'name': 'Shut', 'position': 0},
        ];

  /// value = how OPEN it is, 0..1
  double _entityValue(HaState? s) {
    if (s == null) return 0;
    final p = s.numAttr('current_position');
    if (p != null) return (p / 100).clamp(0.0, 1.0);
    return s.state == 'open' ? 1 : 0;
  }

  bool _moving(HaState? s) => s != null && (s.state == 'opening' || s.state == 'closing');

  Future<void> _call(String service, [Map<String, dynamic>? data]) =>
      widget.env.conn.callService('cover', service, {'entity_id': entity, ...?data});

  void _commit(double v, HaState? s) {
    final pct = (v * 100).round();
    if (s != null && s.supports(_setPosition)) {
      _call('set_cover_position', {'position': pct});
    } else {
      _call(pct > 50 ? 'open_cover' : 'close_cover');
    }
  }

  void _applyPreset(CardConfig p, HaState? s) {
    final pos = (p['position'] as num?)?.toDouble();
    if (pos == null) return;
    holdLocal(pos / 100, echoMs);
    _commit(pos / 100, s);
  }

  String _stateText(HaState? s, int pct) {
    if (s == null) return '';
    if (s.state == 'opening') return 'Opening';
    if (s.state == 'closing') return 'Closing';
    if (s.numAttr('current_position') != null) {
      return pct >= 99 ? 'Open' : (pct <= 0 ? 'Closed' : '$pct% open');
    }
    return s.state == 'open' ? 'Open' : 'Closed';
  }

  void _openSheet(HaState? s) {
    final v = display(_entityValue(s));
    showControlSheet(
      context,
      title: c.titleOr(friendlyName(s, entity)),
      state: _stateText(s, (v * 100).round()),
      value: v,
      fromTop: true,
      accent: parseHex(c.str('accent')) ?? Ns.sky,
      step: c.numOr('step', 5),
      actions: [
        SheetAction(label: 'Open', icon: MdiIcons.arrowUp, run: () => _call('open_cover')),
        SheetAction(label: 'Stop', icon: MdiIcons.stop, primary: true, close: false, run: () => _call('stop_cover')),
        SheetAction(label: 'Close', icon: MdiIcons.arrowDown, run: () => _call('close_cover')),
      ],
      onInput: (nv) => holdLocal(nv, echoMs),
      onCommit: (nv) {
        holdLocal(nv, echoMs);
        _commit(nv, s);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<HaState?>(
      valueListenable: widget.env.states.listen(entity),
      builder: (context, s, _) {
        final broken = s == null || s.isBroken;
        final v = display(_entityValue(s));
        final pct = (v * 100).round();
        final showPresets = c.boolOr('show_presets', true) && presets.isNotEmpty;
        final icon = c.str('icon') ??
            s?.attr<String>('icon') ??
            (pct >= 99 ? 'mdi:blinds-open' : (pct <= 0 ? 'mdi:blinds' : 'mdi:blinds-horizontal'));

        return FillCard(
          height: c.numOr('height', 200),
          accent: parseHex(c.str('accent')) ?? Ns.sky,
          // the fill descends from the top, the way a blind actually does
          fill: broken ? 1 : v,
          fillOpacity: broken ? 0 : 1,
          fromTop: true,
          on: !broken && pct < 55,
          broken: broken,
          leading: IconBox(mdi(icon), on: !broken && pct < 55),
          value: ValueText(broken ? '—' : '$pct', unit: broken ? '' : '%'),
          title: c.titleOr(friendlyName(s, entity)),
          sub: broken ? 'Unavailable' : _stateText(s, pct),
          chips: showPresets
              ? [
                  for (final p in presets.take(4))
                    ChipSpec(label: p.str('name') ?? '${p['position']}%', onTap: () => _applyPreset(p, s)),
                ]
              : const [],
          // a tap while it is moving stops it; otherwise it toggles
          onTap: () => _call(_moving(s) ? 'stop_cover' : 'toggle'),
          onLongPress: c.str('long_press') == 'none' ? null : () => _openSheet(s),
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
