import 'dart:async';

import 'package:flutter/material.dart';

import '../config/dashboard.dart';
import '../ha/states.dart';
import '../ui/sheet.dart';
import '../ui/light_track.dart';
import '../ui/theme.dart';
import '../util/icons.dart';
import 'env.dart';
import 'light_color.dart';
import 'light_controls.dart';

/// Stateful light controller shared by light cards and explicit shortcut targets.
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
  final double Function(double)? resolveValue;
  @override
  State<LightSheet> createState() => _LightSheetState();
}

class _LightSheetState extends State<LightSheet> {
  LightControls get controls => LightControls(widget.config, widget.env);
  Map<String, dynamic> get displayAttributes =>
      widget.env.states.lightMemory.resolve(
        controls.entity,
        controls.current?.state,
        controls.current?.attributes ?? const {},
      );
  bool get hasLastValues =>
      policy.caps.brightness &&
      widget.env.states.lightMemory.hasLastValues(
        controls.entity,
        controls.current?.state,
        controls.current?.attributes ?? const {},
      );
  LightColor get policy => LightColor(
    controls.current,
    attributes: displayAttributes,
    lastValues: true,
  );
  String? _lastState;
  final Map<LightChannel, double> _echo = {}, _draft = {};
  final Map<LightChannel, Timer> _timers = {};
  LightChannel _active = LightChannel.brightness;
  LightChannel? _drag;
  bool _white = false, _busy = false;
  String? _chooser, _error;
  int _generation = 0;
  bool get _lastUsed => widget.config.str('step_target') == 'last_used';
  bool get _available => policy.caps.available && widget.env.conn.isOnline;
  List<CardConfig> get _favorites => widget.config
      .maps('effect_favorites')
      .where((p) => p.str('effect')?.isNotEmpty == true)
      .toList();

  @override
  void initState() {
    super.initState();
    _white =
        policy.white &&
        (displayAttributes['color_mode'] == 'color_temp' || !policy.color);
    final actual = policy.value(LightChannel.brightness);
    _lastState = controls.current?.state;
    final initial = controls.current?.isOn == true
        ? widget.resolveValue?.call(actual) ?? actual
        : actual;
    if (initial != actual) _hold(LightChannel.brightness, initial);
    widget.env.conn.status.addListener(_connectionChanged);
    widget.env.states.listen(controls.entity).addListener(_stateChanged);
  }

  void _connectionChanged() {
    if (!_available) {
      _generation++;
      _busy = false;
      _clearPreview();
    }
    if (mounted) setState(() {});
  }

  void _stateChanged() {
    if (_lastState != controls.current?.state) {
      _lastState = controls.current?.state;
      _clearPreview();
      _white =
          policy.white &&
          (displayAttributes['color_mode'] == 'color_temp' || !policy.color);
    }
    if (!_available && _busy) {
      _generation++;
      _busy = false;
    }
    if (!_available || (_drag != null && !policy.allows(_drag!))) {
      _clearPreview();
    }
    if (mounted) setState(() {});
  }

  void _clearPreview() {
    _draft.clear();
    _echo.clear();
    _drag = null;
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
  }

  @override
  void dispose() {
    widget.env.conn.status.removeListener(_connectionChanged);
    widget.env.states.listen(controls.entity).removeListener(_stateChanged);
    _generation++;
    _clearPreview();
    super.dispose();
  }

  void _hold(LightChannel ch, double v) {
    _echo[ch] = v;
    _timers[ch]?.cancel();
    _timers[ch] = Timer(
      Duration(
        milliseconds: widget.config.intOr('echo_ms', 1500).clamp(0, 10000),
      ),
      () {
        if (!mounted) return;
        if (!_busy) setState(() => _echo.remove(ch));
      },
    );
  }

  Map<LightChannel, double> get _values => {
    for (final ch in LightChannel.values)
      ch: _available
          ? _draft[ch] ?? _echo[ch] ?? policy.value(ch)
          : policy.value(ch),
  };

  Future<bool> _send(Future<bool> Function() send) async {
    if (_busy || !_available) return false;
    final generation = ++_generation;
    setState(() {
      _busy = true;
      _error = null;
    });
    bool ok = false;
    String? failure;
    try {
      ok = await send().timeout(const Duration(seconds: 10));
      if (!ok) failure = 'Command failed';
    } on TimeoutException {
      failure = 'No response';
    } catch (_) {
      failure = 'Command failed';
    }
    if (!mounted || generation != _generation) return false;
    setState(() {
      _busy = false;
      _error = failure;
    });
    return ok;
  }

  Future<void> _commit(LightChannel ch, double v) async {
    if (_busy || !_available || !policy.allows(ch)) return;
    final values = _values;
    values[ch] = policy.snap(ch, v);
    setState(() {
      _drag = null;
      _draft.clear();
      if (_lastUsed) _active = ch;
      // A new colour command supersedes the other colour mode's local echo.
      final obsolete = ch == LightChannel.temperature
          ? [LightChannel.hue, LightChannel.saturation]
          : ch == LightChannel.hue || ch == LightChannel.saturation
          ? [LightChannel.temperature]
          : <LightChannel>[];
      for (final old in obsolete) {
        _timers[old]?.cancel();
        _echo.remove(old);
      }
      _hold(ch, values[ch]!);
    });
    final data = policy.payload(ch, values);
    final off = ch == LightChannel.brightness && data['brightness_pct'] == 0;
    final generation = _generation + 1;
    final ok = await _send(
      () => controls.call(off ? 'turn_off' : 'turn_on', off ? null : data),
    );
    if (!mounted || generation != _generation) return;
    setState(() {
      if (ok) {
        if (!(off && controls.current?.state == 'off')) _hold(ch, values[ch]!);
        if (ch == LightChannel.hue || ch == LightChannel.saturation) {
          _hold(LightChannel.hue, values[LightChannel.hue]!);
          _hold(LightChannel.saturation, values[LightChannel.saturation]!);
        }
      } else {
        _timers[ch]?.cancel();
        _echo.remove(ch);
      }
    });
    if (ch == LightChannel.brightness) {
      widget.onLevelChanged?.call(
        ok ? values[ch]! : controls.entityValue(controls.current),
      );
    }
  }

  String _semanticValue(LightChannel ch, double value) => switch (ch) {
    LightChannel.hue => '${(value * 360).round() % 360} degrees',
    LightChannel.temperature =>
      policy.range == null
          ? 'Unknown'
          : '${(policy.range!.min + value * (policy.range!.max - policy.range!.min)).round()} kelvin',
    _ => '${(value * 100).round()}%',
  };
  double _nextValue(LightChannel ch, double value, int direction) {
    final raw = widget.config.numOr('step', 5);
    final step = raw.isFinite && raw > 0 ? raw.clamp(.1, 100) / 100 : .05;
    return ch == LightChannel.hue
        ? (value + direction * step) % 1
        : (value + direction * step).clamp(0, 1);
  }

  void _step(LightChannel ch, int direction) {
    if (_drag != null || _busy || !_available || !policy.allows(ch)) return;
    final raw = widget.config.numOr('step', 5);
    final step = raw.isFinite && raw > 0 ? raw.clamp(.1, 100) / 100 : .05;
    final value = _values[ch]!;
    final next = ch == LightChannel.hue
        ? (value + direction * step) % 1
        : (value + direction * step).clamp(0.0, 1.0);
    if (next != value) _commit(ch, next);
  }

  void _cancel() {
    if (mounted) {
      setState(() {
        _draft.clear();
        _drag = null;
      });
    }
  }

  Future<void> _action(Future<bool> Function() send) async {
    if (await _send(send) && mounted) Navigator.of(context).pop();
  }

  void _browse(String? page) => setState(() {
    _chooser = page;
    _draft.clear();
    _drag = null;
  });

  @override
  Widget build(BuildContext context) {
    final p = policy, s = controls.current;
    final available = _available;
    if (_white && !p.white) _white = false;
    if (!_white && !p.color && p.white) _white = true;
    final channels = <LightChannel>[
      if (_white && p.white) LightChannel.temperature,
      if (!_white && p.color) ...[LightChannel.hue, LightChannel.saturation],
      if (p.caps.brightness) LightChannel.brightness,
    ];
    if (!_lastUsed || !channels.contains(_active)) {
      _active = LightChannel.brightness;
    }
    final values = _values;
    final accent = controls.accent(s);
    Color target = accent;
    final previewChannel =
        (_drag == LightChannel.brightness ? null : _drag) ??
        (_echo.containsKey(LightChannel.temperature)
            ? LightChannel.temperature
            : (_echo.containsKey(LightChannel.hue) ||
                  _echo.containsKey(LightChannel.saturation))
            ? LightChannel.hue
            : null);
    final whiteTarget =
        previewChannel == LightChannel.temperature ||
        (previewChannel == null &&
            displayAttributes['color_mode'] == 'color_temp');
    if (whiteTarget && p.white && p.range != null) {
      target = LightColor.kelvin(
        p.range!.min +
            values[LightChannel.temperature]! * (p.range!.max - p.range!.min),
      );
    } else if (p.color ||
        p.caps.modes.any({'hs', 'xy', 'rgb', 'rgbw', 'rgbww'}.contains)) {
      target = HSVColor.fromAHSV(
        1,
        values[LightChannel.hue]! * 360,
        values[LightChannel.saturation]!,
        1,
      ).toColor();
    } else if (p.white) {
      target = LightColor.kelvin(
        p.range!.min +
            values[LightChannel.temperature]! * (p.range!.max - p.range!.min),
      );
    }
    final on = s?.isOn ?? false;
    final status = !available
        ? 'Unavailable'
        : on
        ? 'On'
        : hasLastValues
        ? 'Off · last values'
        : 'Off';
    final effect = displayAttributes['effect'] as String?;
    final actions = <SheetAction>[
      if (_chooser != null)
        SheetAction(
          label: 'Back',
          icon: Icons.arrow_back,
          close: false,
          run: () => _browse(null),
        )
      else ...[
        if (p.white && p.color)
          SheetAction(
            label: _white ? 'Colour' : 'White',
            icon: Icons.palette_outlined,
            close: false,
            enabled: _drag == null,
            dimWhenDisabled: false,
            run: () => setState(() {
              _white = !_white;
              _active = LightChannel.brightness;
            }),
          ),
        if (controls.presets.isNotEmpty)
          SheetAction(
            label: 'Presets',
            icon: Icons.list,
            close: false,
            enabled: _drag == null,
            dimWhenDisabled: false,
            run: () => _browse('Presets'),
          ),
        if (_favorites.isNotEmpty)
          SheetAction(
            label: 'Effects',
            icon: Icons.auto_awesome,
            close: false,
            enabled: _drag == null,
            dimWhenDisabled: false,
            run: () => _browse('Effects'),
          ),
        SheetAction(
          label: on ? 'Turn off' : 'Turn on',
          icon: Icons.power_settings_new,
          primary: true,
          close: false,
          enabled: available && !_busy && _drag == null,
          dimWhenDisabled: !available,
          run: () => _action(() => controls.call(on ? 'turn_off' : 'turn_on')),
        ),
      ],
    ];
    final contentEnabled = available && !_busy;
    bool canStep(int direction) =>
        p.allows(_active) &&
        (_active == LightChannel.hue ||
            (direction == 1 ? values[_active]! < 1 : values[_active]! > 0));
    final body = _chooser != null
        ? GridView.count(
            padding: EdgeInsets.zero,
            crossAxisCount: 2,
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            childAspectRatio: (MediaQuery.sizeOf(context).width - 40) / 2 / 76,
            children: [
              for (final item
                  in _chooser == 'Effects' ? _favorites : controls.presets)
                Builder(
                  builder: (_) {
                    final isEffect = _chooser == 'Effects';
                    final name =
                        item.str('name') ??
                        item.str('effect') ??
                        '${item['brightness_pct']}%';
                    final selected =
                        isEffect &&
                        (on || hasLastValues) &&
                        effect == item.str('effect');
                    final allowed = isEffect
                        ? p.effects.contains(item.str('effect'))
                        : p.caps.allowsPreset(s, item);
                    return SheetButton(
                      label: name,
                      dimWhenDisabled: !available || !allowed,
                      selected: selected,
                      color: selected
                          ? Color.alphaBlend(
                              accent.withValues(alpha: .16),
                              Ns.surface,
                            )
                          : Ns.surface,
                      onTap: contentEnabled && allowed && !(selected && on)
                          ? () => _action(
                              () => isEffect
                                  ? (policy.effects.contains(item.str('effect'))
                                        ? controls.call('turn_on', {
                                            'effect': item['effect'],
                                          })
                                        : Future.value(false))
                                  : controls.applyPreset(item),
                            )
                          : null,
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Row(
                          children: [
                            Icon(
                              selected
                                  ? Icons.check
                                  : mdi(
                                      item.str('icon'),
                                      isEffect
                                          ? Icons.auto_awesome
                                          : Icons.lightbulb_outline,
                                    ),
                              color: Ns.text,
                              size: 24,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Ns.text,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
            ],
          )
        : channels.isEmpty
        ? null
        : Row(
            children: [
              for (final ch in channels) ...[
                Expanded(
                  child: LightTrack(
                    key: ValueKey(
                      ch == LightChannel.brightness
                          ? 'sheet-level'
                          : 'light-${ch.name}',
                    ),
                    label: ch.name,
                    valueText: _semanticValue(ch, values[ch]!),
                    increasedText: _semanticValue(
                      ch,
                      _nextValue(ch, values[ch]!, 1),
                    ),
                    decreasedText: _semanticValue(
                      ch,
                      _nextValue(ch, values[ch]!, -1),
                    ),
                    value: values[ch]!,
                    color: target,
                    percent: ch == LightChannel.brightness,
                    active: _lastUsed && ch == _active,
                    gradient: switch (ch) {
                      LightChannel.hue => [
                        for (final h in [0, 60, 120, 180, 240, 300, 360])
                          HSVColor.fromAHSV(1, h.toDouble(), 1, 1).toColor(),
                      ],
                      LightChannel.saturation => [
                        Colors.white,
                        HSVColor.fromAHSV(
                          1,
                          values[LightChannel.hue]! * 360,
                          1,
                          1,
                        ).toColor(),
                      ],
                      LightChannel.temperature => [
                        for (var i = 0; i <= 8; i++)
                          LightColor.kelvin(
                            p.range!.min +
                                (p.range!.max - p.range!.min) * i / 8,
                          ),
                      ],
                      _ => null,
                    },
                    enabled: contentEnabled && (_drag == null || _drag == ch),
                    dimWhenDisabled: !available,
                    onInput: (v) => setState(() {
                      if (_drag == null) _draft.addAll(values);
                      _drag = ch;
                      _draft[ch] = v;
                    }),
                    onCommit: (v) => _commit(ch, v),
                    onCancel: _cancel,
                    onIncrease: () => _step(ch, 1),
                    onDecrease: () => _step(ch, -1),
                  ),
                ),
                const SizedBox(width: 14),
              ],
              SizedBox(
                width: SheetMetrics.stepWidth,
                child: Column(
                  children: [
                    for (final direction in [1, -1]) ...[
                      if (direction == -1) const SizedBox(height: 14),
                      Expanded(
                        child: SheetButton(
                          key: ValueKey(
                            direction == 1
                                ? 'sheet-increase'
                                : 'sheet-decrease',
                          ),
                          label:
                              '${direction == 1 ? 'Increase' : 'Decrease'} ${_active.name}',
                          dimWhenDisabled: !available || !canStep(direction),
                          onTap:
                              contentEnabled &&
                                  _drag == null &&
                                  canStep(direction)
                              ? () => _step(_active, direction)
                              : null,
                          child: Icon(
                            direction == 1 ? Icons.add : Icons.remove,
                            color: Ns.text,
                            size: 34,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );
    return ControlSheet(
      title:
          _chooser ?? widget.config.titleOr(friendlyName(s, controls.entity)),
      state: _error != null
          ? '$status · $_error'
          : effect != null && _chooser == 'Effects'
          ? '$status · $effect'
          : status,
      stateColor: _error != null ? Ns.danger : Ns.muted,
      value: values[LightChannel.brightness]!,
      accent: accent,
      fromTop: false,
      step: widget.config.numOr('step', 5),
      showLevel: p.caps.brightness,
      enabled: true,
      verticalPadding: 12,
      verticalGap: 8,
      body: body,
      actions: actions,
    );
  }
}
