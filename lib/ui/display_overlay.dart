import 'package:flutter/widgets.dart';

import '../util/display_controller.dart';
import 'screensaver.dart';

/// Mounted above MaterialApp's Navigator so modal controls cannot sit above sleep.
class DisplayOverlay extends StatelessWidget {
  const DisplayOverlay({
    super.key,
    required this.controller,
    required this.child,
  });
  final DisplayController controller;
  final Widget child;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => Stack(
      children: [
        child,
        if (controller.enabled && controller.saving)
          Positioned.fill(
            child:
                controller.effective.sleep &&
                    controller.effective.sleepAfterSeconds == 0
                ? Listener(
                    behavior: HitTestBehavior.opaque,
                    onPointerDown: (_) => controller.wake(),
                    child: const ColoredBox(color: Color(0xff000000)),
                  )
                : Screensaver(
                    config: controller.effective,
                    onWake: controller.wake,
                  ),
          ),
      ],
    ),
  );
}
