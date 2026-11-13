import 'package:flutter/material.dart';

import '../config/dashboard.dart';
import '../ha/states.dart';
import '../ui/sheet.dart';
import '../ui/theme.dart';
import '../util/color.dart';
import '../l10n/strings.dart';
import 'env.dart';

/// A deliberately small native counterpart to HA's more-info dialog.
/// Unknown domains are read-only; never guess which services they support.
class SwitchSheet extends StatefulWidget {
  const SwitchSheet({super.key, required this.config, required this.env});
  final CardConfig config;
  final PanelEnv env;

  @override
  State<SwitchSheet> createState() => _SwitchSheetState();
}

class _SwitchSheetState extends State<SwitchSheet> {
  Strings get tr => L.of(context);

  bool _busy = false;
  bool _failed = false;
  String get entity => widget.config.str('entity') ?? '';
  bool get _controllable => const {
    'switch',
    'input_boolean',
    'fan',
  }.contains(entity.split('.').first);

  Future<void> _set(bool on) async {
    final s = widget.env.states.get(entity);
    if (_busy || !_controllable || s == null || s.state == 'unavailable') return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    final ok = await widget.env.conn.callService(
      'homeassistant',
      on ? 'turn_on' : 'turn_off',
      {'entity_id': entity},
    );
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
    } else {
      setState(() {
        _busy = false;
        _failed = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<HaState?>(
    valueListenable: widget.env.states.listen(entity),
    builder: (_, s, _) {
      // `unknown` is the resting state of an assumed-state switch, not a fault
      final available = s != null && s.state != 'unavailable';
      final on = s?.isOn ?? false;
      final state = !available
          ? tr.unavailable
          : _controllable
          ? (on
                ? widget.config.str('on_text') ?? tr.on
                : widget.config.str('off_text') ?? tr.off)
          : tr.state(s.state);
      return ControlSheet(
        title: widget.config.titleOr(friendlyName(s, entity)),
        state: _failed ? '$state · ${tr.commandFailed}' : state,
        value: 0,
        accent: parseHex(widget.config.str('accent')) ?? Ns.amber,
        showLevel: false,
        enabled: available && !_busy,
        fromTop: false,
        step: 5,
        actions: [
          if (_controllable)
            SheetAction(
              label: on ? tr.turnOff : tr.turnOn,
              icon: Icons.power_settings_new,
              primary: true,
              close: false,
              run: () => _set(!on),
            ),
        ],
      );
    },
  );
}
