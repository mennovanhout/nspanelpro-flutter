import 'package:flutter/material.dart';

/// Swipes through `children` once, all but invisible, resting on each, then
/// calls `onDone` so the owner drops it. Skia compiles a shader the first time a draw op
/// reaches the GPU, and on this panel a page's first swipe costs 150-270 ms
/// per frame in exactly that - so this does the same swipe a second after
/// load, while nothing moves and nobody is touching the screen. It has to
/// be a real scrolling PageView: the shaders a page needs while it slides
/// (fractional offsets, the viewport's clip) are not the ones it needs
/// standing still, which a plain hidden paint proved. It rests on each page
/// because a page that has held still for a few frames is raster-cached,
/// which is its own first-time cost. Opacity 0 would skip painting
/// entirely, and so does hiding it behind something opaque; drawing it on
/// screen shrunk to a corner compiles the wrong variants. All measured.
///
/// What this buys, on the panel: after a normal launch the first swipe has
/// no slow frame at all (it had one of 90 ms, plus the page build). After a
/// fresh install, when Android's shader cache is empty, one 260 ms frame
/// survives; the next launch is clean.
class Warmup extends StatefulWidget {
  const Warmup({super.key, required this.children, required this.onDone});
  final List<Widget> children;
  final VoidCallback onDone;

  @override
  State<Warmup> createState() => _WarmupState();
}

class _WarmupState extends State<Warmup> {
  final _controller = PageController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _run());
  }

  Future<void> _run() async {
    const d = Duration(milliseconds: 260);
    const rest = Duration(milliseconds: 150);
    for (var i = 1; i < widget.children.length && mounted; i++) {
      await _controller.animateToPage(i, duration: d, curve: Curves.easeInOut);
      await Future<void>.delayed(rest);
    }
    if (mounted) await _controller.animateToPage(0, duration: d, curve: Curves.easeInOut);
    if (mounted) widget.onDone();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Opacity(
          opacity: 0.01,
          child: PageView(
            controller: _controller,
            physics: const NeverScrollableScrollPhysics(),
            allowImplicitScrolling: true,
            children: widget.children,
          ),
        ),
      );
}
