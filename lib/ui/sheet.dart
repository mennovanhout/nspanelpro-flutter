import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../util/color.dart';
import 'theme.dart';

/// Existing native control-sheet geometry, in logical pixels.
abstract final class SheetMetrics {
  static const padding = 16.0;
  static const gap = 14.0;
  static const actionGap = 8.0;
  static const closeSize = 56.0;
  static const stepWidth = 96.0;
  static const actionHeight = 76.0;
  static const buttonRadius = 18.0;
  static const levelRadius = 20.0;
}

class SheetAction {
  const SheetAction({
    required this.label,
    this.icon,
    this.primary = false,
    this.close = true,
    this.enabled = true,
    this.dimWhenDisabled = true,
    this.selected = false,
    required this.run,
  });
  final String label;
  final IconData? icon;
  final bool primary;
  final bool enabled, selected, dimWhenDisabled;
  final bool close;
  final VoidCallback run;
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
      actions: actions,
      onInput: onInput,
      onCommit: onCommit,
    ),
  );
}

/// Allows an entity-specific dialog to follow state changes without recreating
/// the route or losing the value under a finger.
Future<void> showControlSheetBuilder(
  BuildContext context,
  WidgetBuilder builder,
) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'close',
    barrierColor: Ns.ground.withValues(alpha: .72),
    transitionDuration: const Duration(milliseconds: 180),
    transitionBuilder: (_, a, _, child) =>
        FadeTransition(opacity: a, child: child),
    pageBuilder: (ctx, _, _) => builder(ctx),
  );
}

class ControlSheet extends StatefulWidget {
  const ControlSheet({
    super.key,
    this.showLevel = true,
    this.enabled = true,
    required this.title,
    required this.state,
    required this.value,
    required this.accent,
    required this.fromTop,
    required this.step,
    required this.actions,
    this.onInput,
    this.onCommit,
    this.body,
    this.stateColor = Ns.muted,
    this.verticalPadding = SheetMetrics.padding,
    this.verticalGap = SheetMetrics.gap,
  });

  final bool showLevel, enabled;
  final String title, state;
  final double value, step;
  final Color accent;
  final bool fromTop;
  final List<SheetAction> actions;
  final ValueChanged<double>? onInput;
  final ValueChanged<double>? onCommit;
  final Widget? body;
  final Color stateColor;
  final double verticalPadding, verticalGap;

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
    if (!widget.enabled || !widget.showLevel) {
      _dragging = false;
      _cancelled = true;
      _v = widget.value;
    }
    if (!_dragging) _v = widget.value;
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

  @override
  Widget build(BuildContext context) {
    final stops = tintStops(widget.accent);
    return Material(
      color: Colors.transparent,
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: SheetMetrics.padding,
            vertical: widget.verticalPadding,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Ns.text,
                            fontSize: 22,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          widget.state,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: widget.stateColor,
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  SheetButton(
                    key: const ValueKey('sheet-close'),
                    label: 'Close',
                    size: SheetMetrics.closeSize,
                    onTap: () => Navigator.of(context).pop(),
                    child: const Icon(Icons.close, color: Ns.text, size: 26),
                  ),
                ],
              ),
              SizedBox(height: widget.verticalGap),
              if (widget.body != null)
                Expanded(child: widget.body!)
              else if (!widget.showLevel)
                Expanded(
                  child: Center(
                    child: Text(
                      widget.state,
                      style: const TextStyle(
                        color: Ns.text,
                        fontSize: 36,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                )
              else
                Expanded(
                  child: AbsorbPointer(
                    absorbing: !widget.enabled,
                    child: Row(
                      children: [
                        Expanded(
                          child: LayoutBuilder(
                            builder: (_, box) {
                              final h = box.maxHeight;
                              double fromY(double y) =>
                                  (1 - y / h).clamp(0.0, 1.0);
                              return Listener(
                                onPointerDown: (_) {
                                  _cancelled = false;
                                },
                                onPointerCancel: (_) {
                                  setState(() {
                                    _cancelled = true;
                                    _dragging = false;
                                    _v = widget.value;
                                  });
                                },
                                child: GestureDetector(
                                  key: const ValueKey('sheet-level'),
                                  behavior: HitTestBehavior.opaque,
                                  onTapUp: (d) => _set(
                                    fromY(d.localPosition.dy),
                                    commit: true,
                                  ),
                                  onVerticalDragStart: (d) {
                                    _dragging = true;
                                    _set(fromY(d.localPosition.dy));
                                  },
                                  onVerticalDragUpdate: (d) =>
                                      _set(fromY(d.localPosition.dy)),
                                  onVerticalDragCancel: () {
                                    setState(() {
                                      _dragging = false;
                                      _v = widget.value;
                                    });
                                  },
                                  onVerticalDragEnd: (_) {
                                    final commit = _dragging && !_cancelled;
                                    _dragging = false;
                                    if (commit) _set(_v, commit: true);
                                  },
                                  child: Container(
                                    clipBehavior: Clip.antiAlias,
                                    decoration: BoxDecoration(
                                      color: Ns.surface,
                                      borderRadius: BorderRadius.circular(
                                        SheetMetrics.levelRadius,
                                      ),
                                    ),
                                    child: Stack(
                                      fit: StackFit.expand,
                                      children: [
                                        TweenAnimationBuilder<double>(
                                          tween: Tween(end: _v),
                                          duration: _dragging
                                              ? Duration.zero
                                              : const Duration(
                                                  milliseconds: 120,
                                                ),
                                          builder: (_, v, child) =>
                                              FractionalTranslation(
                                                translation: widget.fromTop
                                                    ? Offset(0, -v)
                                                    : Offset(0, 1 - v),
                                                child: child,
                                              ),
                                          child: DecoratedBox(
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                begin: Alignment.topCenter,
                                                end: Alignment.bottomCenter,
                                                colors: [
                                                  widget.accent,
                                                  stops.strong,
                                                ],
                                              ),
                                            ),
                                          ),
                                        ),
                                        Center(
                                          child: Text(
                                            '${(_v * 100).round()}%',
                                            style: const TextStyle(
                                              color: Ns.text,
                                              fontSize: 44,
                                              fontWeight: FontWeight.w700,
                                              fontFeatures: Ns.tabular,
                                              shadows: Ns.shadow,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: SheetMetrics.gap),
                        SizedBox(
                          width: SheetMetrics.stepWidth,
                          child: Column(
                            children: [
                              Expanded(
                                child: SheetButton(
                                  key: const ValueKey('sheet-increase'),
                                  label: 'Increase',
                                  onTap: widget.enabled && _v < 1
                                      ? () => _stepBy(widget.step)
                                      : null,
                                  child: const Icon(
                                    Icons.add,
                                    color: Ns.text,
                                    size: 34,
                                  ),
                                ),
                              ),
                              const SizedBox(height: SheetMetrics.gap),
                              Expanded(
                                child: SheetButton(
                                  key: const ValueKey('sheet-decrease'),
                                  label: 'Decrease',
                                  onTap: widget.enabled && _v > 0
                                      ? () => _stepBy(-widget.step)
                                      : null,
                                  child: const Icon(
                                    Icons.remove,
                                    color: Ns.text,
                                    size: 34,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              if (widget.actions.isNotEmpty) ...[
                SizedBox(height: widget.verticalGap),
                SizedBox(
                  height: SheetMetrics.actionHeight,
                  child: Row(
                    children: [
                      for (
                        var i = 0;
                        i < widget.actions.length && i < 4;
                        i++
                      ) ...[
                        if (i > 0)
                          const SizedBox(width: SheetMetrics.actionGap),
                        Expanded(
                          child: SheetButton(
                            label: widget.actions[i].label,
                            dimWhenDisabled: widget.actions[i].dimWhenDisabled,
                            color: widget.actions[i].primary
                                ? widget.accent
                                : widget.actions[i].selected
                                ? widget.accent.withValues(alpha: .16)
                                : Ns.surface,
                            onTap: !widget.enabled || !widget.actions[i].enabled
                                ? null
                                : () {
                                    HapticFeedback.lightImpact();
                                    widget.actions[i].run();
                                    if (widget.actions[i].close) {
                                      Navigator.of(context).pop();
                                    }
                                  },
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (widget.actions[i].icon != null)
                                  Icon(
                                    widget.actions[i].icon,
                                    size: 24,
                                    color: widget.actions[i].primary
                                        ? Ns.ground
                                        : Ns.text,
                                  ),
                                const SizedBox(height: 4),
                                Text(
                                  widget.actions[i].label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: widget.actions[i].primary
                                        ? Ns.ground
                                        : Ns.text,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class SheetButton extends StatelessWidget {
  const SheetButton({
    super.key,
    this.label,
    required this.onTap,
    required this.child,
    this.size,
    this.color = Ns.surface,
    this.dimWhenDisabled = true,
    this.selected = false,
  });
  final String? label;
  final VoidCallback? onTap;
  final Widget child;
  final double? size;
  final Color color;
  final bool dimWhenDisabled;
  final bool selected;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: onTap != null,
    selected: selected ? true : null,
    label: label,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Opacity(
        opacity: onTap == null && dimWhenDisabled ? .35 : 1,
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(SheetMetrics.buttonRadius),
          ),
          foregroundDecoration: selected
              ? BoxDecoration(
                  border: Border.all(color: Ns.text, width: 2),
                  borderRadius: BorderRadius.circular(
                    SheetMetrics.buttonRadius,
                  ),
                )
              : null,
          child: child,
        ),
      ),
    ),
  );
}
