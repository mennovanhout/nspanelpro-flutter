import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';

import '../config/dashboard.dart';
import '../ha/states.dart';
import '../ui/info_shell.dart';
import '../ui/theme.dart';
import '../util/color.dart';
import '../util/icons.dart';
import 'env.dart';
import '../l10n/strings.dart';

/// What counts as "not normal", by domain. Anything not listed is never a
/// problem unless the config says so with problem_when.
const _problemWhen = {
  'lock': ['unlocked', 'open', 'opening', 'jammed'],
  'cover': ['open', 'opening'],
  'binary_sensor': ['on'],
  'input_boolean': ['on'],
  'switch': ['on'],
  'person': ['not_home'],
  'device_tracker': ['not_home'],
};

/// Is the house alright? Quiet when everything is normal, loud when not.
class StatusCard extends StatelessWidget {
  const StatusCard({super.key, required this.config, required this.env});
  final CardConfig config;
  final PanelEnv env;

  List<CardConfig> get items => config.maps('entities');

  bool _isProblem(CardConfig item, HaState? s) {
    if (s == null) return true; // a missing entity is itself a problem
    if (s.isBroken) return true;
    if (item['problem_when'] is List) {
      return item.listOr('problem_when').contains(s.state);
    }
    final list = _problemWhen[item.str('entity')!.split('.').first];
    return list?.contains(s.state) ?? false;
  }

  String _label(Strings t, CardConfig item, HaState? s) {
    if (s == null) return t.missing;
    if (s.state == 'unavailable') return t.unavailable;
    if (s.state == 'unknown') return t.unknown;
    if (s.domain == 'binary_sensor') {
      final on = s.isOn;
      switch (s.deviceClass) {
        case 'door':
        case 'window':
        case 'garage_door':
        case 'opening':
          return on ? t.stateOpen : t.stateClosed;
        case 'motion':
        case 'occupancy':
          return on ? t.detected : t.clear;
        case 'moisture':
          return on ? t.wet : t.dry;
        case 'problem':
          return on ? t.problem : t.ok;
        default:
          return on ? t.on : t.off;
      }
    }
    return t.state(s.state);
  }

  @override
  Widget build(BuildContext context) {
    final t = L.of(context);
    final ids = [for (final i in items) i.str('entity')]
        .whereType<String>()
        .toList();
    final accent = parseHex(config.str('accent')) ?? Ns.gold;
    final onlyProblems = config.boolOr('only_problems', false);
    final columns = config.intOr('columns', 2).clamp(1, 3);

    return AnimatedBuilder(
      animation: Listenable.merge([
        for (final id in ids) env.states.listen(id),
      ]),
      builder: (context, _) {
        final tiles = <Widget>[];
        var problems = 0;
        for (final item in items) {
          final id = item.str('entity');
          if (id == null) continue;
          final s = env.states.get(id);
          final bad = _isProblem(item, s);
          if (bad) problems++;
          if (onlyProblems && !bad) continue;
          tiles.add(
            Tile(
              icon: mdi(
                item.str('icon') ?? s?.attr<String>('icon') ?? classIcon(s, id),
              ),
              name: item.str('name') ?? friendlyName(s, id),
              sub: _label(t, item, s),
              alert: bad,
              // to tell a leak from a window left open; only while it is a
              // problem, so a normal tile stays quiet
              accent: parseHex(item.str('color')) ?? accent,
              background: parseHex(item.str('background')),
              colorName: parseHex(item.str('color')) != null,
              compact: columns == 3,
            ),
          );
        }
        final allClear = onlyProblems && problems == 0;
        return InfoShell(
          height: config.numOr('height', 200),
          accent: accent,
          padding: const EdgeInsets.all(12),
          child: allClear
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(MdiIcons.checkCircleOutline, size: 44, color: accent),
                    const SizedBox(height: 10),
                    Text(
                      config.str('all_clear') ?? t.allClear,
                      style: const TextStyle(
                        color: Ns.muted,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                )
              // More tiles than fit are cut off at the card's edge, as in the
              // browser, rather than overflowing: the scroll view only gives
              // the grid room to lay out, it never scrolls.
              : ClipRect(
                  child: SingleChildScrollView(
                    physics: const NeverScrollableScrollPhysics(),
                    child: TileGrid(columns: columns, children: tiles),
                  ),
                ),
        );
      },
    );
  }
}
