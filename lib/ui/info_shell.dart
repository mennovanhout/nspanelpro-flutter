import 'package:flutter/material.dart';

import '../util/color.dart';
import 'theme.dart';

/// The read-only card: same surface, same radius, no gestures. An optional
/// fill for the sensor card's range bar.
class InfoShell extends StatelessWidget {
  const InfoShell({
    super.key,
    required this.height,
    required this.child,
    this.accent = Ns.sky,
    this.fill,
    this.broken = false,
    this.padding = const EdgeInsets.fromLTRB(20, 18, 20, 18),
  });

  final double height;
  final Widget child;
  final Color accent;
  final double? fill;
  final bool broken;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final stops = tintStops(accent);
    return Opacity(
      opacity: broken ? .45 : 1,
      child: Container(
        height: height,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: Ns.surface, borderRadius: BorderRadius.circular(Ns.radius)),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (fill != null)
              TweenAnimationBuilder<double>(
                tween: Tween(end: fill!.clamp(0.0, 1.0)),
                duration: const Duration(milliseconds: 180),
                builder: (_, v, c) => FractionalTranslation(translation: Offset(0, 1 - v), child: c),
                child: Stack(fit: StackFit.expand, children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [stops.strong, stops.weak],
                      ),
                    ),
                  ),
                  Positioned(left: 0, right: 0, top: 0, height: 3, child: ColoredBox(color: accent)),
                ]),
              ),
            if (broken)
              const Positioned(
                top: 12,
                right: 14,
                child: Text('OFFLINE',
                    style:
                        TextStyle(color: Ns.danger, fontSize: 13, fontWeight: FontWeight.w700, letterSpacing: 1)),
              ),
            Padding(padding: padding, child: child),
          ],
        ),
      ),
    );
  }
}

/// One number, read from across the room.
class BigValue extends StatelessWidget {
  const BigValue(this.value, {super.key, this.unit = '', this.size = 64});
  final String value;
  final String unit;
  final double size;

  @override
  Widget build(BuildContext context) => Text.rich(
        TextSpan(children: [
          TextSpan(
              text: value,
              style: TextStyle(
                  fontSize: size,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -size * .03,
                  height: 1,
                  color: Ns.text,
                  fontFeatures: Ns.tabular,
                  shadows: Ns.shadow)),
          if (unit.isNotEmpty)
            TextSpan(
                text: unit,
                style: TextStyle(
                    fontSize: size * .4,
                    fontWeight: FontWeight.w600,
                    color: Ns.text.withValues(alpha: .7),
                    shadows: Ns.shadow)),
        ]),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      );
}

/// A tile in a grid: icon, name, state. Used by the status card and, with a
/// different shape, the button card.
class Tile extends StatelessWidget {
  const Tile({
    super.key,
    required this.icon,
    required this.name,
    required this.sub,
    this.alert = false,
    this.accent = Ns.gold,
    this.compact = false,
    this.onTap,
  });

  final IconData icon;
  final String name, sub;
  final bool alert, compact;
  final Color accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 62,
          padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 12),
          decoration: BoxDecoration(
            color: alert ? accent.withValues(alpha: .16) : Colors.white.withValues(alpha: .06),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Icon(icon, size: compact ? 20 : 24, color: alert ? accent : Ns.muted),
              SizedBox(width: compact ? 8 : 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            color: Ns.text, fontSize: compact ? 14 : 15, fontWeight: FontWeight.w600, height: 1.2)),
                    Text(sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: alert ? accent : Ns.muted, fontSize: 12, height: 1.3)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
}

/// `columns` across, wrapping, tiles stretched to share the rows. A partial
/// last row is shared by the tiles that are in it - two buttons under
/// `columns: 3` are two half-width buttons, not two thirds and a gap - which
/// is what the web cards' `flex: 1 0 ...` does.
class TileGrid extends StatelessWidget {
  const TileGrid({super.key, required this.children, required this.columns, this.stretch = false});
  final List<Widget> children;
  final int columns;
  final bool stretch;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += columns) {
      final cells = <Widget>[];
      for (var j = 0; j < columns && i + j < children.length; j++) {
        if (j > 0) cells.add(const SizedBox(width: 10));
        cells.add(Expanded(child: children[i + j]));
      }
      final row = Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: cells);
      if (rows.isNotEmpty) rows.add(const SizedBox(height: 10));
      rows.add(stretch ? Expanded(child: row) : row);
    }
    return Column(mainAxisSize: stretch ? MainAxisSize.max : MainAxisSize.min, children: rows);
  }
}
