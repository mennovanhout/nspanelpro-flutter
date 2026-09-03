import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';

import '../config/dashboard.dart';
import '../ha/states.dart';
import '../ui/info_shell.dart';
import '../ui/keypad.dart';
import '../ui/theme.dart';
import '../util/color.dart';
import '../util/icons.dart';
import 'env.dart';

/// An arm mode: its button label, the service, the supported_features bit
/// the entity has to set for it to show, and its icon.
class AlarmMode {
  const AlarmMode(this.key, this.label, this.service, this.bit, this.icon);
  final String key, label, service, icon;
  final int bit;
}

const alarmModes = [
  AlarmMode('home', 'Home', 'alarm_arm_home', 1, 'mdi:shield-home'),
  AlarmMode('away', 'Away', 'alarm_arm_away', 2, 'mdi:shield-lock'),
  AlarmMode('night', 'Night', 'alarm_arm_night', 4, 'mdi:shield-moon'),
  AlarmMode('custom_bypass', 'Bypass', 'alarm_arm_custom_bypass', 16, 'mdi:shield-half-full'),
  AlarmMode('vacation', 'Vacation', 'alarm_arm_vacation', 32, 'mdi:shield-airplane'),
];

/// The modes to show: the config's list (default home, away), in its order,
/// minus anything the entity says it cannot do. An entity that reports no
/// supported_features at all is taken at its word for everything.
List<AlarmMode> alarmModesFor(List<dynamic> wanted, int? supported) {
  final keys = wanted.isEmpty ? const ['home', 'away'] : wanted.map((w) => w.toString()).toList();
  return [
    for (final k in keys)
      for (final m in alarmModes)
        if (m.key == k && (supported == null || supported & m.bit != 0)) m,
  ];
}

/// Whether HA will want a code for this action: never without a code_format;
/// always to disarm; to arm only when code_arm_required (default true).
bool alarmNeedsCode({required String? codeFormat, required bool? codeArmRequired, required bool arming}) {
  if (codeFormat == null || codeFormat.isEmpty) return false;
  return arming ? (codeArmRequired ?? true) : true;
}

class AlarmLook {
  const AlarmLook(this.label, this.color, this.icon);
  final String label;
  final Color color;
  final String icon;
}

AlarmLook alarmLook(String? state, Color accent) => switch (state) {
      'disarmed' => AlarmLook('Disarmed', accent, 'mdi:shield-off-outline'),
      'armed_home' => const AlarmLook('Armed home', Ns.danger, 'mdi:shield-home'),
      'armed_away' => const AlarmLook('Armed away', Ns.danger, 'mdi:shield-lock'),
      'armed_night' => const AlarmLook('Armed night', Ns.danger, 'mdi:shield-moon'),
      'armed_vacation' => const AlarmLook('Armed vacation', Ns.danger, 'mdi:shield-airplane'),
      'armed_custom_bypass' => const AlarmLook('Armed (bypass)', Ns.danger, 'mdi:shield-half-full'),
      'arming' => const AlarmLook('Arming…', Ns.amber, 'mdi:shield-sync'),
      'pending' => const AlarmLook('Pending…', Ns.amber, 'mdi:shield-alert'),
      'triggered' => const AlarmLook('TRIGGERED', Ns.danger, 'mdi:bell-ring'),
      _ => const AlarmLook('Unavailable', Ns.muted, 'mdi:alert-circle-outline'),
    };

/// Arm and disarm an alarm_control_panel, with the keypad when HA wants a
/// code. Disarmed shows one button per mode; anything else shows Disarm.
/// State changes ring the built-in armed/disarmed/alarm sounds on the panel.
class AlarmCard extends StatefulWidget {
  const AlarmCard({super.key, required this.config, required this.env});
  final CardConfig config;
  final PanelEnv env;

  @override
  State<AlarmCard> createState() => _AlarmCardState();
}

class _AlarmCardState extends State<AlarmCard> {
  CardConfig get c => widget.config;
  String get _id => c.str('entity') ?? '';
  late final Listenable _entity = widget.env.states.listen(_id);
  String? _last;
  String? _pendingLabel; // optimistic, until the state moves or echo_ms passes
  Timer? _pending;

  @override
  void initState() {
    super.initState();
    _last = widget.env.states.get(_id)?.state;
    _entity.addListener(_onState);
  }

  @override
  void dispose() {
    _entity.removeListener(_onState);
    _pending?.cancel();
    super.dispose();
  }

  void _onState() {
    final now = widget.env.states.get(_id)?.state;
    if (now == _last) return;
    final was = _last;
    _last = now;
    if (_pendingLabel != null) {
      _pending?.cancel();
      _pendingLabel = null;
    }
    // Not on the first state after a reconnect (was == null): that is the
    // house as it is, not something that just happened.
    if (was != null && c.boolOr('sounds', true) && widget.env.play != null) {
      if (now == 'triggered') {
        widget.env.play!('sound:alarm');
      } else if (now == 'disarmed') {
        widget.env.play!('sound:disarmed');
      } else if (now != null && now.startsWith('armed_')) {
        widget.env.play!('sound:armed');
      }
    }
  }

  /// Optimistic from the tap: HA sends the state_changed before it answers
  /// the call, so a label set after the answer would outlive the state.
  /// The state clears it; so does a refusal, or twice echo_ms without either.
  Future<bool> _call(String service, String? code) async {
    setState(() => _pendingLabel = service == 'alarm_disarm' ? 'Disarming…' : 'Arming…');
    _pending?.cancel();
    _pending = Timer(Duration(milliseconds: c.intOr('echo_ms', 1500) * 2), () {
      if (mounted) setState(() => _pendingLabel = null);
    });
    final ok = await widget.env.conn.callService('alarm_control_panel', service, {
      'entity_id': _id,
      'code': ?code,
    });
    if (!ok && mounted) {
      _pending?.cancel();
      setState(() => _pendingLabel = null);
    }
    return ok;
  }

  void _act(BuildContext context, {required String service, required String label, required bool arming}) {
    if (c.boolOr('haptics', true)) HapticFeedback.lightImpact();
    final s = widget.env.states.get(_id);
    final fmt = s?.attr<String>('code_format');
    final needs = alarmNeedsCode(codeFormat: fmt, codeArmRequired: s?.attr<bool>('code_arm_required'), arming: arming);
    if (!needs) {
      _call(service, null);
      return;
    }
    showKeypadSheet(
      context,
      title: label,
      accent: parseHex(c.str('accent')) ?? Ns.mint,
      text: fmt == 'text',
      onSubmit: (code) => _call(service, code),
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _entity,
        builder: (context, _) {
          final s = widget.env.states.get(_id);
          final accent = parseHex(c.str('accent')) ?? Ns.mint;
          final broken = s == null || s.state == 'unavailable' || s.state == 'unknown';
          final look = alarmLook(broken ? null : s.state, accent);
          final triggered = s?.state == 'triggered';
          final disarmed = s?.state == 'disarmed';
          final modes = alarmModesFor(c.listOr('modes'), s?.attr<num>('supported_features')?.toInt());
          final changedBy = s?.attr<String>('changed_by');
          final compact = modes.length > 2;

          return InfoShell(
            height: c.numOr('height', 200),
            accent: look.color,
            fill: triggered ? 1 : null,
            broken: broken,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      // `icon` is the resting (disarmed) icon; armed and alarm states keep their own
                      Icon(mdi(disarmed ? (c.str('icon') ?? look.icon) : look.icon, MdiIcons.shieldOutline),
                          size: 46, color: look.color),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(_pendingLabel ?? look.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    color: look.color, fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: -.3)),
                            Text(
                              changedBy != null && changedBy.isNotEmpty
                                  ? '${c.titleOr(friendlyName(s, _id))} · by $changedBy'
                                  : c.titleOr(friendlyName(s, _id)),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Ns.muted, fontSize: 14, fontWeight: FontWeight.w500),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 60,
                  child: broken
                      ? const SizedBox()
                      : disarmed
                          ? Row(
                              children: [
                                for (final m in modes) ...[
                                  if (m != modes.first) const SizedBox(width: 10),
                                  Expanded(
                                    child: _Btn(
                                      icon: mdi(m.icon, MdiIcons.shield),
                                      label: m.label,
                                      color: accent,
                                      compact: compact,
                                      onTap: () => _act(context, service: m.service, label: 'Arm ${m.label.toLowerCase()}', arming: true),
                                    ),
                                  ),
                                ],
                              ],
                            )
                          : _Btn(
                              icon: MdiIcons.shieldOffOutline,
                              label: 'Disarm',
                              color: triggered ? Ns.text : accent,
                              compact: false,
                              onTap: () => _act(context, service: 'alarm_disarm', label: 'Disarm', arming: false),
                            ),
                ),
              ],
            ),
          );
        },
      );
}

class _Btn extends StatelessWidget {
  const _Btn({required this.icon, required this.label, required this.color, required this.compact, required this.onTap});
  final IconData icon;
  final String label;
  final Color color;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(color: Ns.surface2, borderRadius: BorderRadius.circular(16)),
          padding: EdgeInsets.symmetric(horizontal: compact ? 6 : 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: compact ? 20 : 24, color: color),
              SizedBox(width: compact ? 6 : 10),
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Ns.text, fontSize: compact ? 15 : 17, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      );
}
