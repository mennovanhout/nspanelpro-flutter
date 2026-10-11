import '../util/navigation_controller.dart';

import 'package:flutter/material.dart';

import 'theme.dart';

/// Pages side by side, swiped. PageView's horizontal recognizer and the
/// cards' vertical one settle it in the gesture arena, which is the same
/// axis-lock the web cards do by hand.
class PanelPager extends StatefulWidget {
  const PanelPager({
    super.key,
    required this.pages,
    this.jump,
    this.onPage,
    this.showDots = true,
    this.initialPage = 0,
  });
  final List<Widget> pages;

  /// The page dots at the bottom; the swipe card's `dots: false` hides them.
  final bool showDots;
  final int initialPage;

  /// Imperative dashboard navigation; repeated target commands are preserved.
  final PanelNavigation? jump;
  final ValueChanged<int>? onPage;

  @override
  State<PanelPager> createState() => _PanelPagerState();
}

class _PanelPagerState extends State<PanelPager> {
  late int _index = widget.initialPage.clamp(
    0,
    widget.pages.isEmpty ? 0 : widget.pages.length - 1,
  );
  late final _controller = PageController(initialPage: _index);

  @override
  void initState() {
    super.initState();
    widget.jump?.addListener(_onJump);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onJump();
    });
    if (_index != 0) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => widget.onPage?.call(_index),
      );
    }
  }

  @override
  void didUpdateWidget(PanelPager oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.jump != widget.jump) {
      oldWidget.jump?.removeListener(_onJump);
      widget.jump?.addListener(_onJump);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onJump();
    });
  }

  @override
  void dispose() {
    widget.jump?.removeListener(_onJump);
    _controller.dispose();
    super.dispose();
  }

  bool _programmatic = false;
  int _motion = 0;
  void _onJump() {
    final nav = widget.jump;
    final i = nav?.target;
    if (i == null || i < 0 || i >= widget.pages.length) return;
    if (!_controller.hasClients) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _onJump();
      });
      return;
    }
    if (i == _index && (_controller.page ?? i.toDouble()) == i) {
      nav!.shown(i);
      return;
    }
    final motion = ++_motion;
    _programmatic = true;
    if (!nav!.animate) {
      _controller.jumpToPage(i);
      _programmatic = false;
    } else {
      _controller
          .animateToPage(
            i,
            duration: const Duration(milliseconds: 350),
            curve: Curves.easeOutCubic,
          )
          .whenComplete(() {
            if (mounted && motion == _motion) _programmatic = false;
          });
    }
  }

  @override
  Widget build(BuildContext context) {
    final many = widget.pages.length > 1 && widget.showDots;
    return Stack(
      children: [
        NotificationListener<ScrollNotification>(
          onNotification: (event) {
            if (event.depth != 0) return false;
            if (event is ScrollStartNotification) {
              if (event.dragDetails != null) _programmatic = false;
              widget.jump?.scroll(true, user: !_programmatic);
            } else if (event is ScrollEndNotification) {
              widget.jump?.scroll(false, user: !_programmatic);
            }
            return false;
          },
          child: PageView.builder(
            controller: _controller,
            // the neighbouring pages are built while this one is shown, not
            // in the middle of the swipe that reveals them
            allowImplicitScrolling: true,
            itemCount: widget.pages.length,
            onPageChanged: (i) {
              setState(() => _index = i);
              widget.jump?.shown(i);
              widget.onPage?.call(i);
            },
            itemBuilder: (_, i) => Padding(
              padding: EdgeInsets.fromLTRB(
                Ns.gap,
                Ns.gap,
                Ns.gap,
                many ? 26 : Ns.gap,
              ),
              child: widget.pages[i],
            ),
          ),
        ),
        if (many)
          Positioned(
            left: 0,
            right: 0,
            bottom: 7,
            child: IgnorePointer(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < widget.pages.length; i++)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      margin: const EdgeInsets.symmetric(horizontal: 3.5),
                      width: i == _index ? 8 : 7,
                      height: i == _index ? 8 : 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i == _index
                            ? Ns.text
                            : Colors.white.withValues(alpha: .22),
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
