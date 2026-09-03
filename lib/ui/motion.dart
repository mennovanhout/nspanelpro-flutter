import 'dart:async';

import 'package:flutter/material.dart';

/// The two animations the app allows itself, both one-offs and both
/// opacity/transform only - the same budget the cards keep. Nothing here
/// runs continuously; on a Mali-G31 that is the whole discipline.

/// Rises into place once, on mount. `index` staggers a list.
class Enter extends StatefulWidget {
  const Enter({super.key, required this.child, this.index = 0});
  final Widget child;
  final int index;

  @override
  State<Enter> createState() => _EnterState();
}

class _EnterState extends State<Enter> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 380));
  late final Animation<double> _a = CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
  Timer? _delay;

  @override
  void initState() {
    super.initState();
    _delay = Timer(Duration(milliseconds: 60 * widget.index), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _delay?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _a,
        child: widget.child,
        builder: (_, child) => Opacity(
          opacity: _a.value,
          child: Transform.translate(offset: Offset(0, 14 * (1 - _a.value)), child: child),
        ),
      );
}

/// Fades in on mount, fades out when `visible` goes false, and tells the
/// owner when it is gone so it can be unmounted. While leaving it ignores
/// touches, so the thing underneath is usable before the fade ends.
class Reveal extends StatefulWidget {
  const Reveal({
    super.key,
    required this.visible,
    required this.child,
    this.onHidden,
    this.inDuration = const Duration(milliseconds: 700),
    this.outDuration = const Duration(milliseconds: 350),
  });

  final bool visible;
  final Widget child;
  final VoidCallback? onHidden;
  final Duration inDuration, outDuration;

  @override
  State<Reveal> createState() => _RevealState();
}

class _RevealState extends State<Reveal> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this)
    ..addStatusListener((s) {
      if (s == AnimationStatus.dismissed) widget.onHidden?.call();
    });

  @override
  void initState() {
    super.initState();
    if (widget.visible) _c.animateTo(1, duration: widget.inDuration, curve: Curves.easeOut);
  }

  @override
  void didUpdateWidget(Reveal old) {
    super.didUpdateWidget(old);
    if (widget.visible != old.visible) {
      if (widget.visible) {
        _c.animateTo(1, duration: widget.inDuration, curve: Curves.easeOut);
      } else {
        _c.animateBack(0, duration: widget.outDuration, curve: Curves.easeIn);
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        ignoring: !widget.visible,
        child: FadeTransition(opacity: _c, child: widget.child),
      );
}
