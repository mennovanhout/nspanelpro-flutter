import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../util/color.dart';
import 'theme.dart';

class SheetAction {
  const SheetAction({
    required this.label,
    this.icon,
    this.primary = false,
    this.close = true,
    this.enabled = true,
    required this.run,
  });
  final String label;
  final IconData? icon;
  final bool primary;
  final bool enabled;
  final bool close;
  final VoidCallback run;
}

/// Panel-wide behaviour of the long-press page.
abstract final class Sheets {
  /// Untouched this long, the page closes itself; null is never. The panel
  /// setting `popup_timeout` sets it.
  static Duration? autoClose = const Duration(seconds: 30);
}

/// The long-press control surface: an absolute slider, big ± steps, and up
/// to four actions. One value in, one value out, and the caller keeps the
/// echo window so the card underneath agrees with it.
Future<void> showControlSheet(
  BuildContext context, {
  required String title,
  required String state,
  required double value,
  required Color accent,
  bool fromTop = false,
  double step = 5,
  String Function(double)? format,
  List<SheetAction> actions = const [],
  ValueChanged<double>? onInput,
  ValueChanged<double>? onCommit,
}) {
  return showControlSheetBuilder(
    context,
    (_) => ControlSheet(
      title: title,
      state: state,
      value: value,
      accent: accent,
      fromTop: fromTop,
      step: step,
      format: format,
      actions: actions,
      onInput: onInput,
      onCommit: onCommit,
    ),
  );
}

/// Allows an entity-specific dialog to follow state changes without recreating
/// the route or losing the value under a finger.
///
/// An opaque page, not a dialog over the dashboard: nothing shows through,
/// and the cards underneath are not painted while it is up - on this GPU that
/// is a frame's worth of raster saved, every frame.
Future<void> showControlSheetBuilder(
  BuildContext context,
  WidgetBuilder builder,
) {
  return Navigator.of(context).push(
    PageRouteBuilder<void>(
      opaque: true,
      transitionDuration: const Duration(milliseconds: 180),
      reverseTransitionDuration: const Duration(milliseconds: 140),
      transitionsBuilder: (_, a, _, child) =>
          FadeTransition(opacity: a, child: child),
      pageBuilder: (ctx, _, _) => AutoClose(child: builder(ctx)),
    ),
  );
}

/// Closes the route it is in after [Sheets.autoClose] without a touch. Every
/// touch starts the count again, and a finger held down (on the slider,
/// mid-drag) stops it until it lifts.
class AutoClose extends StatefulWidget {
  const AutoClose({super.key, required this.child, this.after});

  final Widget child;

  /// Overrides [Sheets.autoClose]; for tests.
  final Duration? after;

  @override
  State<AutoClose> createState() => _AutoCloseState();
}

class _AutoCloseState extends State<AutoClose> {
  Timer? _timer;
  int _down = 0;

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
    _timer?.cancel();
    _timer = null;
    final after = widget.after ?? Sheets.autoClose;
    if (after == null || after <= Duration.zero || _down > 0) return;
    _timer = Timer(after, _close);
  }

  void _close() {
    if (!mounted) return;
    final route = ModalRoute.of(context);
    if (route == null || !route.isCurrent) {
      // something on top of it (the keypad): wait for that first
      _arm();
      return;
    }
    Navigator.of(context).pop();
  }

  void _up() {
    if (_down > 0) _down--;
    _arm();
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.translucent,
    onPointerDown: (_) {
      _down++;
      _timer?.cancel();
    },
    onPointerUp: (_) => _up(),
    onPointerCancel: (_) => _up(),
    child: widget.child,
  );
}

class ControlSheet extends StatefulWidget {
  const ControlSheet({
    super.key,
    this.showLevel = true,
    this.enabled = true,
    this.active,
    required this.title,
    required this.state,
    required this.value,
    required this.accent,
    required this.fromTop,
    required this.step,
    required this.actions,
    this.format,
    this.onInput,
    this.onCommit,
  });

  /// What the slider reads, from its 0..1 value; a percentage without one.
  final String Function(double)? format;
  final bool showLevel, enabled;

  /// Without a level: whether the thing is on, which lights the big button.
  /// Null reads as on.
  final bool? active;
  final String title, state;
  final double value, step;
  final Color accent;
  final bool fromTop;
  final List<SheetAction> actions;
  final ValueChanged<double>? onInput;
  final ValueChanged<double>? onCommit;

  @override
  State<ControlSheet> createState() => _SheetState();
}

class _SheetState extends State<ControlSheet> {
  late double _v = widget.value;
  bool _dragging = false;
  bool _cancelled = false;

  @override
  void didUpdateWidget(ControlSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled || !widget.showLevel) _dragging = false;
    if (!_dragging && widget.value != oldWidget.value) _v = widget.value;
  }

  void _set(double v, {bool commit = false}) {
    if (!widget.enabled || !widget.showLevel) return;
    _v = v.clamp(0.0, 1.0);
    setState(() {});
    if (commit) {
      widget.onCommit?.call(_v);
    } else {
      widget.onInput?.call(_v);
    }
  }

  void _stepBy(double delta) {
    HapticFeedback.lightImpact();
    _set(_v + delta / 100, commit: true);
  }

  void _close() => Navigator.of(context).maybePop();

  VoidCallback? _runner(SheetAction a) => !widget.enabled || !a.enabled
      ? null
      : () {
          HapticFeedback.lightImpact();
          a.run();
          if (a.close) Navigator.of(context).maybePop();
        };

  @override
  Widget build(BuildContext context) {
    final a = widget.accent;
    return Material(
      color: Ns.ground,
      // one static gradient, painted with the page: the accent glows in from
      // the corner the title sits in
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(-1, -1.2),
            radius: 1.4,
            colors: [a.withValues(alpha: .22), a.withValues(alpha: 0)],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 12, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _Header(
                  title: widget.title,
                  state: widget.state,
                  accent: a,
                  onClose: _close,
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: widget.showLevel ? _levelBody() : _toggleBody(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---- with a level: capsule | readout, stepper, actions -----------------

  Widget _levelBody() => AbsorbPointer(
    absorbing: !widget.enabled,
    child: Opacity(
      opacity: widget.enabled ? 1 : .45,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: 148, child: _capsule()),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  height: 76,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      widget.format?.call(_v) ?? '${(_v * 100).round()}%',
                      style: const TextStyle(
                        color: Ns.text,
                        fontSize: 68,
                        height: 1,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -1.5,
                        fontFeatures: Ns.tabular,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(height: 72, child: _stepper()),
                if (widget.actions.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Expanded(child: _actions()),
                ] else
                  const Spacer(),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  /// The slider: a tall capsule that fills with the accent from the bottom
  /// (from the top for a blind), with a grip on the fill's edge.
  Widget _capsule() => LayoutBuilder(
    builder: (_, box) {
      final h = box.maxHeight;
      double fromY(double y) => (1 - y / h).clamp(0.0, 1.0);
      final grip = Padding(
        padding: const EdgeInsets.all(14),
        child: Container(
          width: 44,
          height: 6,
          decoration: BoxDecoration(
            color: Ns.ground.withValues(alpha: .35),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      );
      return Listener(
        onPointerDown: (_) => _cancelled = false,
        onPointerCancel: (_) => _cancelled = true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) => _set(fromY(d.localPosition.dy), commit: true),
          onVerticalDragStart: (d) {
            _dragging = true;
            _set(fromY(d.localPosition.dy));
          },
          onVerticalDragUpdate: (d) => _set(fromY(d.localPosition.dy)),
          onVerticalDragCancel: () => _dragging = false,
          onVerticalDragEnd: (_) {
            final commit = _dragging && !_cancelled;
            _dragging = false;
            if (commit) _set(_v, commit: true);
          },
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: Ns.text.withValues(alpha: .07),
              borderRadius: BorderRadius.circular(44),
            ),
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: _v),
              duration: _dragging
                  ? Duration.zero
                  : const Duration(milliseconds: 120),
              builder: (_, v, child) => FractionalTranslation(
                translation: widget.fromTop ? Offset(0, -v) : Offset(0, 1 - v),
                child: child,
              ),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: widget.fromTop
                        ? [tintStops(widget.accent).strong, widget.accent]
                        : [widget.accent, tintStops(widget.accent).strong],
                  ),
                ),
                child: Align(
                  alignment: widget.fromTop
                      ? Alignment.bottomCenter
                      : Alignment.topCenter,
                  child: grip,
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  /// − and + as one segmented pill.
  Widget _stepper() => Container(
    decoration: BoxDecoration(
      color: Ns.surface2,
      borderRadius: BorderRadius.circular(36),
    ),
    child: Row(
      children: [
        Expanded(
          child: _Tap(
            semantics: 'decrease',
            onTap: () => _stepBy(-widget.step),
            child: const Center(
              child: Icon(Icons.remove, color: Ns.text, size: 36),
            ),
          ),
        ),
        Container(
          width: 1.5,
          height: 32,
          color: Ns.text.withValues(alpha: .12),
        ),
        Expanded(
          child: _Tap(
            semantics: 'increase',
            onTap: () => _stepBy(widget.step),
            child: const Center(
              child: Icon(Icons.add, color: Ns.text, size: 36),
            ),
          ),
        ),
      ],
    ),
  );

  /// Up to three as full-width rows; four as a 2x2 of tiles.
  Widget _actions() {
    final list = widget.actions.take(4).toList();
    if (list.length == 4) {
      Widget row(int i) => Expanded(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: _tile(list[i])),
            const SizedBox(width: 10),
            Expanded(child: _tile(list[i + 1])),
          ],
        ),
      );
      return Column(children: [row(0), const SizedBox(height: 10), row(2)]);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < list.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          Expanded(child: _row(list[i])),
        ],
        // one or two do not stretch into slabs
        for (var i = list.length; i < 3; i++) ...[
          const SizedBox(height: 10),
          const Expanded(child: SizedBox()),
        ],
      ],
    );
  }

  ({Color bg, Color fg}) _look(SheetAction a) => a.primary
      ? (bg: widget.accent, fg: Ns.ground)
      : (bg: Ns.surface2, fg: Ns.text);

  Widget _row(SheetAction a) {
    final c = _look(a);
    return _Pill(
      color: c.bg,
      onTap: _runner(a),
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Row(
        children: [
          if (a.icon != null) ...[
            Icon(a.icon, size: 26, color: c.fg),
            const SizedBox(width: 12),
          ],
          Expanded(child: _label(a.label, c.fg, 17)),
        ],
      ),
    );
  }

  Widget _tile(SheetAction a) {
    final c = _look(a);
    return _Pill(
      color: c.bg,
      onTap: _runner(a),
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          if (a.icon != null) Icon(a.icon, size: 28, color: c.fg),
          _label(a.label, c.fg, 15),
        ],
      ),
    );
  }

  Widget _label(String s, Color fg, double size) => Text(
    s,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
    style: TextStyle(color: fg, fontSize: size, fontWeight: FontWeight.w700),
  );

  // ---- without a level: one big round button ----------------------------

  Widget _toggleBody() {
    final list = widget.actions.take(4).toList();
    final main = list.where((a) => a.primary).firstOrNull;
    final rest = [
      for (final a in list)
        if (a != main) a,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(child: main == null ? _bigState() : _bigButton(main)),
        if (rest.isNotEmpty) ...[
          const SizedBox(height: 12),
          SizedBox(
            height: 80,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < rest.length; i++) ...[
                  if (i > 0) const SizedBox(width: 10),
                  Expanded(child: _tile(rest[i])),
                ],
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _bigState() => Center(
    child: Text(
      widget.state,
      textAlign: TextAlign.center,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: Ns.text,
        fontSize: 44,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  Widget _bigButton(SheetAction a) {
    final on = widget.active ?? true;
    final onTap = _runner(a);
    return LayoutBuilder(
      builder: (_, box) {
        final d = (box.maxHeight - 52).clamp(96.0, 220.0);
        return Semantics(
          button: true,
          label: a.label,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Opacity(
              opacity: onTap == null ? .4 : 1,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // a flat halo, not a blur: two circles
                  Container(
                    width: d,
                    height: d,
                    padding: EdgeInsets.all(d * .07),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: on
                          ? widget.accent.withValues(alpha: .18)
                          : Ns.surface,
                    ),
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: on ? widget.accent : Ns.surface2,
                      ),
                      child: Icon(
                        a.icon ?? Icons.power_settings_new,
                        size: d * .36,
                        color: on ? Ns.ground : Ns.muted,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _label(a.label, Ns.text, 20),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Title, state, and the way out. The whole strip closes the page, not just
/// the button at its end: a finger aimed at a corner lands anywhere near it.
class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.state,
    required this.accent,
    required this.onClose,
  });
  final String title, state;
  final Color accent;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: 'close',
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onClose,
      // at least the button's height; more when the text size wants it
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 80),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Ns.text,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -.3,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    state,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: accent,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: 80,
              height: 80,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Ns.text.withValues(alpha: .14),
              ),
              child: const Icon(Icons.close, color: Ns.text, size: 42),
            ),
          ],
        ),
      ),
    ),
  );
}

/// A rounded, filled surface you press.
class _Pill extends StatelessWidget {
  const _Pill({
    required this.onTap,
    required this.child,
    required this.color,
    required this.padding,
  });
  final VoidCallback? onTap;
  final Widget child;
  final Color color;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) => _Tap(
    onTap: onTap,
    child: Container(
      padding: padding,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(24),
      ),
      child: child,
    ),
  );
}

class _Tap extends StatelessWidget {
  const _Tap({required this.onTap, required this.child, this.semantics});
  final VoidCallback? onTap;
  final Widget child;
  final String? semantics;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: semantics,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Opacity(opacity: onTap == null ? .35 : 1, child: child),
    ),
  );
}
