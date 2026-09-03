import 'dart:async';

import 'package:flutter/material.dart';

import '../config/dashboard.dart';
import '../ha/states.dart';
import '../ui/fill_card.dart';
import '../ui/info_shell.dart';
import '../ui/theme.dart';
import '../util/color.dart';
import 'env.dart';

const _months = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];
const _days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

/// Time, date, and an optional line from any entity. One timer, re-armed
/// against the wall clock each tick so it cannot drift.
class ClockCard extends StatefulWidget {
  const ClockCard({super.key, required this.config, required this.env});
  final CardConfig config;
  final PanelEnv env;

  @override
  State<ClockCard> createState() => _ClockCardState();
}

class _ClockCardState extends State<ClockCard> {
  CardConfig get c => widget.config;
  Timer? _timer;
  DateTime _now = DateTime.now();

  @override
  void initState() {
    super.initState();
    _arm();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _arm() {
    _now = DateTime.now();
    final period = c.boolOr('show_seconds', false) ? 1000 : 60000;
    final wait = period - (_now.millisecondsSinceEpoch % period) + 20;
    _timer = Timer(Duration(milliseconds: wait), () {
      if (!mounted) return;
      setState(_arm);
    });
  }

  @override
  Widget build(BuildContext context) {
    final entity = c.str('entity');
    final h24 = c.boolOr('hour_24', true);
    var h = _now.hour;
    var suffix = '';
    if (!h24) {
      suffix = h < 12 ? 'am' : 'pm';
      h = h % 12 == 0 ? 12 : h % 12;
    }
    final hh = h24 ? h.toString().padLeft(2, '0') : h.toString();
    final mm = _now.minute.toString().padLeft(2, '0');
    final ss = c.boolOr('show_seconds', false) ? ':${_now.second.toString().padLeft(2, '0')}' : '';

    Widget body(HaState? s) {
      final line = s == null
          ? ''
          : (c.str('title') != null ? '${c.str('title')}: ' : '') + (s.attr<String>('message') ?? s.state);
      return InfoShell(
        height: c.numOr('height', 200),
        accent: parseHex(c.str('accent')) ?? Ns.sky,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(
              TextSpan(children: [
                TextSpan(text: '$hh:$mm$ss'),
                if (suffix.isNotEmpty)
                  TextSpan(
                      text: ' $suffix',
                      style: TextStyle(fontSize: 34, fontWeight: FontWeight.w600, color: Ns.text.withValues(alpha: .55))),
              ]),
              style: const TextStyle(
                  color: Ns.text,
                  fontSize: 88,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -3.5,
                  height: 1,
                  fontFeatures: Ns.tabular),
            ),
            if (c.boolOr('show_date', true)) ...[
              const SizedBox(height: 10),
              Text('${_days[_now.weekday - 1]} ${_now.day} ${_months[_now.month - 1]}',
                  style: const TextStyle(color: Ns.muted, fontSize: 20, fontWeight: FontWeight.w600)),
            ],
            if (line.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(line, maxLines: 1, overflow: TextOverflow.ellipsis, style: subStyle),
            ],
          ],
        ),
      );
    }

    if (entity == null) return body(null);
    return ValueListenableBuilder<HaState?>(
      valueListenable: widget.env.states.listen(entity),
      builder: (context, s, _) => body(s),
    );
  }
}
