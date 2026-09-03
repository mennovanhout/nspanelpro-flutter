import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../util/color.dart';
import 'theme.dart';

class ChipSpec {
  const ChipSpec({required this.label, this.icon, required this.onTap, this.disabled = false});
  final String label;
  final IconData? icon;
  final VoidCallback onTap;
  final bool disabled;
}

/// The control surface every "set a level" card is built on: a tinted block
/// that fills the card to the value, the level line on its edge, text on top,
/// and the gesture engine - drag anywhere to set, tap, long-press.
///
/// What runs during a drag: one transform. The fill is a FractionalTranslation
/// of a full-size block, so tracking the finger is compositor work, and the
/// parent owns the value so nothing here allocates per frame beyond the
/// rebuild itself. Nothing is sent to HA until the finger lifts.
class FillCard extends StatefulWidget {
  const FillCard({
    super.key,
    required this.height,
    required this.accent,
    required this.fill,
    required this.fillOpacity,
    required this.title,
    required this.sub,
    this.fromTop = false,
    this.on = false,
    this.broken = false,
    this.leading,
    this.value,
    this.chips = const [],
    this.chips2 = const [],
    this.opaqueChips = false,
    this.dragTravel,
    this.onTap,
    this.onLongPress,
    this.onDragValue,
    this.onDragEnd,
  });

  final double height;
  final Color accent;
  final double fill;
  final double fillOpacity;
  final bool fromTop;
  final bool on;
  final bool broken;
  final Widget? leading;
  final Widget? value;
  final String title;
  final String sub;
  final List<ChipSpec> chips;
  final List<ChipSpec> chips2;
  final bool opaqueChips;
  final double? dragTravel;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final ValueChanged<double>? onDragValue;
  final ValueChanged<double>? onDragEnd;

  @override
  State<FillCard> createState() => _FillCardState();
}

class _FillCardState extends State<FillCard> {
  bool _dragging = false;
  double _start = 0;
  double _dy = 0;
  double _last = 0;

  bool get _interactive => !widget.broken;

  void _onDragStart(DragStartDetails d) {
    _dragging = true;
    _start = widget.fill;
    _dy = 0;
    _last = widget.fill;
    HapticFeedback.selectionClick();
    setState(() {});
  }

  void _onDragUpdate(DragUpdateDetails d) {
    _dy += d.delta.dy;
    final travel = widget.dragTravel ?? widget.height;
    _last = (_start - _dy / travel).clamp(0.0, 1.0);
    widget.onDragValue?.call(_last);
  }

  void _onDragEnd(DragEndDetails d) {
    _dragging = false;
    HapticFeedback.lightImpact();
    widget.onDragEnd?.call(_last);
    setState(() {});
  }

  void _onDragCancel() {
    _dragging = false;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final stops = tintStops(widget.accent);
    final canDrag = _interactive && widget.onDragValue != null;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _interactive && widget.onTap != null
          ? () {
              HapticFeedback.lightImpact();
              widget.onTap!();
            }
          : null,
      onLongPress: _interactive && widget.onLongPress != null
          ? () {
              HapticFeedback.mediumImpact();
              widget.onLongPress!();
            }
          : null,
      onVerticalDragStart: canDrag ? _onDragStart : null,
      onVerticalDragUpdate: canDrag ? _onDragUpdate : null,
      onVerticalDragEnd: canDrag ? _onDragEnd : null,
      onVerticalDragCancel: canDrag ? _onDragCancel : null,
      child: Opacity(
        opacity: widget.broken ? .45 : 1,
        child: Container(
          height: widget.height,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Ns.surface,
            borderRadius: BorderRadius.circular(Ns.radius),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // the fill: a block that slides. Transform only.
              TweenAnimationBuilder<double>(
                tween: Tween(end: widget.fill),
                duration: _dragging ? Duration.zero : const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                builder: (_, v, child) => FractionalTranslation(
                  translation: widget.fromTop ? Offset(0, -v) : Offset(0, 1 - v),
                  child: child,
                ),
                child: TweenAnimationBuilder<double>(
                  tween: Tween(end: widget.fillOpacity),
                  duration: const Duration(milliseconds: 180),
                  builder: (_, o, _) => _FillBlock(
                    strong: stops.strong.withValues(alpha: stops.strong.a * o),
                    weak: stops.weak.withValues(alpha: stops.weak.a * o),
                    line: widget.accent.withValues(alpha: o),
                    fromTop: widget.fromTop,
                  ),
                ),
              ),
              if (widget.broken)
                const Positioned(
                  top: 12,
                  right: 14,
                  child: Text('OFFLINE',
                      style: TextStyle(
                          color: Ns.danger, fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 1)),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (widget.leading != null) widget.leading!,
                        const Spacer(),
                        if (widget.value != null) widget.value!,
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: nameStyle),
                        Text(widget.sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: subStyle),
                        if (widget.chips.isNotEmpty)
                          ChipRow(chips: widget.chips, on: widget.on, opaque: widget.opaqueChips),
                        if (widget.chips2.isNotEmpty)
                          ChipRow(chips: widget.chips2, on: widget.on, opaque: widget.opaqueChips),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FillBlock extends StatelessWidget {
  const _FillBlock({required this.strong, required this.weak, required this.line, required this.fromTop});
  final Color strong, weak, line;
  final bool fromTop;

  @override
  Widget build(BuildContext context) => Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [strong, weak],
              ),
            ),
          ),
          // the level itself, unmistakable at arm's length
          Positioned(
            left: 0,
            right: 0,
            top: fromTop ? null : 0,
            bottom: fromTop ? 0 : null,
            height: 3,
            child: ColoredBox(color: line),
          ),
        ],
      );
}

const nameStyle = TextStyle(
    color: Ns.text, fontSize: 22, fontWeight: FontWeight.w600, height: 28 / 22, letterSpacing: -.2, shadows: Ns.shadow);
const subStyle = TextStyle(
    color: Color(0xB8FFFFFF), fontSize: 15, fontWeight: FontWeight.w500, height: 20 / 15, shadows: Ns.shadow);

/// The big number in the top-right of a control card: `68` and a smaller `%`.
class ValueText extends StatelessWidget {
  const ValueText(this.value, {super.key, this.unit = '', this.size = 40});
  final String value;
  final String unit;
  final double size;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text.rich(
          TextSpan(children: [
            TextSpan(
                text: value,
                style: TextStyle(
                    fontSize: size,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -.8,
                    height: 1,
                    color: Ns.text,
                    fontFeatures: Ns.tabular,
                    shadows: Ns.shadow)),
            if (unit.isNotEmpty)
              TextSpan(
                  text: unit,
                  style: TextStyle(
                      fontSize: size / 2,
                      fontWeight: FontWeight.w600,
                      color: Ns.text.withValues(alpha: .65),
                      shadows: Ns.shadow)),
          ]),
        ),
      );
}

/// The rounded square that holds a card's icon.
class IconBox extends StatelessWidget {
  const IconBox(this.icon, {super.key, this.on = false, this.color});
  final IconData icon;
  final bool on;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
        width: 52,
        height: 52,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: on ? .16 : .10),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Icon(icon, size: 30, color: color ?? Ns.text),
      );
}

/// A row of 56px chips - presets, transport, favourites.
class ChipRow extends StatelessWidget {
  const ChipRow({super.key, required this.chips, this.on = false, this.opaque = false});
  final List<ChipSpec> chips;
  final bool on;
  final bool opaque;

  @override
  Widget build(BuildContext context) {
    final bg = opaque
        ? Ns.surface2
        : (on ? Colors.black.withValues(alpha: .34) : Colors.white.withValues(alpha: .10));
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          for (var i = 0; i < chips.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            Expanded(child: _Chip(spec: chips[i], bg: bg)),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.spec, required this.bg});
  final ChipSpec spec;
  final Color bg;

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: spec.disabled
            ? null
            : () {
                HapticFeedback.lightImpact();
                spec.onTap();
              },
        // Claim the gestures the card would otherwise take from a chip: a
        // drag or hold that starts on a button should not move the level.
        onVerticalDragStart: (_) {},
        onLongPress: () {},
        child: Opacity(
          opacity: spec.disabled ? .35 : 1,
          child: Container(
            height: 56,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
            child: spec.icon != null && spec.label.isEmpty
                ? Icon(spec.icon, size: 26, color: Colors.white)
                : Text(spec.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
          ),
        ),
      );
}
