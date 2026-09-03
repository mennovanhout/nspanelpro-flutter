import 'package:flutter/material.dart';

import '../config/dashboard.dart';
import '../ha/states.dart';
import '../ui/info_shell.dart';
import '../ui/theme.dart';
import '../util/color.dart';
import '../util/fmt.dart';
import '../util/icons.dart';
import 'env.dart';

/// Two to four readings side by side. The density card.
class SensorsCard extends StatelessWidget {
  const SensorsCard({super.key, required this.config, required this.env});
  final CardConfig config;
  final PanelEnv env;

  List<CardConfig> get items => config.maps('entities').take(4).toList();

  @override
  Widget build(BuildContext context) {
    final ids = [for (final i in items) i.str('entity')].whereType<String>().toList();
    final showIcons = config.boolOr('show_icons', true);
    return AnimatedBuilder(
      animation: Listenable.merge([for (final id in ids) env.states.listen(id)]),
      builder: (context, _) => InfoShell(
        height: config.numOr('height', 130),
        accent: parseHex(config.str('accent')) ?? Ns.sky,
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(width: 10),
              Expanded(child: _cell(items[i], showIcons)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _cell(CardConfig item, bool showIcons) {
    final id = item.str('entity') ?? '';
    final s = env.states.get(id);
    final broken = s == null || s.isBroken;
    final n = s?.numeric;
    final unit = item['unit'] != null ? item.str('unit')! : (s?.unit ?? '');
    final text = broken ? '—' : (n == null ? s.state : fmt(n, item['decimals'] as int?));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showIcons) ...[
            Icon(mdi(item.str('icon') ?? s?.attr<String>('icon') ?? classIcon(s, id)), size: 22, color: Ns.muted),
            const SizedBox(height: 6),
          ],
          BigValue(text, unit: broken ? '' : unit, size: 30),
          const SizedBox(height: 6),
          Text(item.str('name') ?? friendlyName(s, id),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Ns.muted, fontSize: 13)),
        ],
      ),
    );
  }
}
