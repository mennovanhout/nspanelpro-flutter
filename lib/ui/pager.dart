import 'package:flutter/material.dart';

import 'theme.dart';

/// Pages side by side, swiped. PageView's horizontal recognizer and the
/// cards' vertical one settle it in the gesture arena, which is the same
/// axis-lock the web cards do by hand.
class PanelPager extends StatefulWidget {
  const PanelPager({super.key, required this.pages});
  final List<Widget> pages;

  @override
  State<PanelPager> createState() => _PanelPagerState();
}

class _PanelPagerState extends State<PanelPager> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final many = widget.pages.length > 1;
    return Stack(
      children: [
        PageView.builder(
          itemCount: widget.pages.length,
          onPageChanged: (i) => setState(() => _index = i),
          itemBuilder: (_, i) => Padding(
            padding: EdgeInsets.fromLTRB(Ns.gap, Ns.gap, Ns.gap, many ? 26 : Ns.gap),
            child: widget.pages[i],
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
                        color: i == _index ? Ns.text : Colors.white.withValues(alpha: .22),
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
