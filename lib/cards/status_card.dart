import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';

import '../config/dashboard.dart';
import '../ha/states.dart';
import '../ui/info_shell.dart';
import '../ui/theme.dart';
import '../util/color.dart';
import '../util/fmt.dart';
import '../util/icons.dart';
import 'env.dart';

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
    if (item['problem_when'] is List) return item.listOr('problem_when').contains(s.state);
    final list = _problemWhen[item.str('entity')!.split('.').first];
    return list?.contains(s.state) ?? false;
  }

  String _label(CardConfig item, HaState? s) {
    if (s == null) return 'Missing';
    if (s.state == 'unavailable') return 'Unavailable';
    if (s.state == 'unknown') return 'Unknown';
    if (s.domain == 'binary_sensor') {
      final on = s.isOn;
      switch (s.deviceClass) {
        case 'door':
        case 'window':
        case 'garage_door':
        case 'opening':
          return on ? 'Open' : 'Closed';
        case 'motion':
        case 'occupancy':
          return on ? 'Detected' : 'Clear';
        case 'moisture':
          return on ? 'Wet' : 'Dry';
        case 'problem':
          return on ? 'Problem' : 'OK';
        default:
          return on ? 'On' : 'Off';
      }
    }
    return capitalise(s.state);
  }

  @override
  Widget build(BuildContext context) {
    final ids = [for (final i in items) i.str('entity')].whereType<String>().toList();
    final accent = parseHex(config.str('accent')) ?? Ns.gold;
    final onlyProblems = config.boolOr('only_problems', false);
    final columns = config.intOr('columns', 2).clamp(1, 3);

    return AnimatedBuilder(
      animation: Listenable.merge([for (final id in ids) env.states.listen(id)]),
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
          tiles.add(Tile(
            icon: mdi(item.str('icon') ?? s?.attr<String>('icon') ?? classIcon(s, id)),
            name: item.str('name') ?? friendlyName(s, id),
            sub: _label(item, s),
            alert: bad,
            accent: accent,
            compact: columns == 3,
          ));
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
                    Text(config.str('all_clear') ?? 'All clear',
                        style: const TextStyle(color: Ns.muted, fontSize: 18, fontWeight: FontWeight.w600)),
                  ],
                )
              : ClipRect(child: TileGrid(columns: columns, children: tiles)),
        );
      },
    );
  }
}
