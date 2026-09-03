import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../util/color.dart';
import 'theme.dart';

class SheetAction {
  const SheetAction({required this.label, this.icon, this.primary = false, this.close = true, required this.run});
  final String label;
  final IconData? icon;
  final bool primary;
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
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'close',
    barrierColor: Ns.ground.withValues(alpha: .72),
    transitionDuration: const Duration(milliseconds: 180),
    transitionBuilder: (_, a, _, child) => FadeTransition(opacity: a, child: child),
    pageBuilder: (ctx, _, _) => _Sheet(
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

class _Sheet extends StatefulWidget {
  const _Sheet({
    required this.title,
    required this.state,
    required this.value,
    required this.accent,
    required this.fromTop,
    required this.step,
    required this.actions,
    this.onInput,
    this.onCommit,
  });

  final String title, state;
  final double value, step;
  final Color accent;
  final bool fromTop;
  final List<SheetAction> actions;
  final ValueChanged<double>? onInput;
  final ValueChanged<double>? onCommit;

  @override
  State<_Sheet> createState() => _SheetState();
}

class _SheetState extends State<_Sheet> {
  late double _v = widget.value;
  bool _dragging = false;

  void _set(double v, {bool commit = false}) {
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
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(widget.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Ns.text, fontSize: 22, fontWeight: FontWeight.w700)),
                        Text(widget.state,
                            style: const TextStyle(color: Ns.muted, fontSize: 15, fontWeight: FontWeight.w500)),
                      ],
                    ),
                  ),
                  _Square(
                    size: 56,
                    onTap: () => Navigator.of(context).pop(),
                    child: const Icon(Icons.close, color: Ns.text, size: 26),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: LayoutBuilder(
                        builder: (_, box) {
                          final h = box.maxHeight;
                          double fromY(double y) => (1 - y / h).clamp(0.0, 1.0);
                          return GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTapDown: (d) => _set(fromY(d.localPosition.dy), commit: true),
                            onVerticalDragStart: (d) {
                              _dragging = true;
                              _set(fromY(d.localPosition.dy));
                            },
                            onVerticalDragUpdate: (d) => _set(fromY(d.localPosition.dy)),
                            onVerticalDragEnd: (_) {
                              _dragging = false;
                              _set(_v, commit: true);
                            },
                            child: Container(
                              clipBehavior: Clip.antiAlias,
                              decoration: BoxDecoration(
                                color: Ns.surface,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  TweenAnimationBuilder<double>(
                                    tween: Tween(end: _v),
                                    duration: _dragging ? Duration.zero : const Duration(milliseconds: 120),
                                    builder: (_, v, child) => FractionalTranslation(
                                      translation: widget.fromTop ? Offset(0, -v) : Offset(0, 1 - v),
                                      child: child,
                                    ),
                                    child: DecoratedBox(
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.topCenter,
                                          end: Alignment.bottomCenter,
                                          colors: [widget.accent, stops.strong],
                                        ),
                                      ),
                                    ),
                                  ),
                                  Center(
                                    child: Text('${(_v * 100).round()}%',
                                        style: const TextStyle(
                                            color: Ns.text,
                                            fontSize: 44,
                                            fontWeight: FontWeight.w700,
                                            fontFeatures: Ns.tabular,
                                            shadows: Ns.shadow)),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(width: 14),
                    SizedBox(
                      width: 96,
                      child: Column(
                        children: [
                          Expanded(
                            child: _Square(
                              onTap: () => _stepBy(widget.step),
                              child: const Icon(Icons.add, color: Ns.text, size: 34),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Expanded(
                            child: _Square(
                              onTap: () => _stepBy(-widget.step),
                              child: const Icon(Icons.remove, color: Ns.text, size: 34),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.actions.isNotEmpty) ...[
                const SizedBox(height: 14),
                SizedBox(
                  height: 76,
                  child: Row(
                    children: [
                      for (var i = 0; i < widget.actions.length && i < 4; i++) ...[
                        if (i > 0) const SizedBox(width: 8),
                        Expanded(
                          child: _Square(
                            color: widget.actions[i].primary ? widget.accent : Ns.surface,
                            onTap: () {
                              HapticFeedback.lightImpact();
                              widget.actions[i].run();
                              if (widget.actions[i].close) Navigator.of(context).pop();
                            },
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                if (widget.actions[i].icon != null)
                                  Icon(widget.actions[i].icon,
                                      size: 24, color: widget.actions[i].primary ? Ns.ground : Ns.text),
                                const SizedBox(height: 4),
                                Text(widget.actions[i].label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: widget.actions[i].primary ? Ns.ground : Ns.text,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600)),
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

class _Square extends StatelessWidget {
  const _Square({required this.onTap, required this.child, this.size, this.color = Ns.surface});
  final VoidCallback onTap;
  final Widget child;
  final double? size;
  final Color color;

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(18)),
          child: child,
        ),
      );
}
