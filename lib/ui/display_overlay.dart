import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../util/display_controller.dart';
import 'motion.dart';
import 'screensaver.dart';

/// Mounted above MaterialApp's Navigator so modal controls cannot sit above sleep.
class DisplayOverlay extends StatefulWidget {
  const DisplayOverlay({
    super.key,
    required this.controller,
    required this.child,
    this.weather,
  });
  final DisplayController controller;
  final Widget child;

  /// Shown with the clock; the caller has the connection to HA, this does not.
  final ValueListenable<Widget?>? weather;

  @override
  State<DisplayOverlay> createState() => _DisplayOverlayState();
}

class _DisplayOverlayState extends State<DisplayOverlay> {
  // Keeps the screensaver in the tree while it fades out; the dashboard is
  // touchable from the moment the fade starts.
  bool _shown = false;

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return ListenableBuilder(
      listenable: Listenable.merge([c, ?widget.weather]),
      builder: (context, _) {
        final saving = c.enabled && c.saving;
        final black = saving && c.effective.sleep && c.effective.sleepAfterSeconds == 0;
        if (saving && !black) _shown = true;
        return Stack(
          children: [
            widget.child,
            if (black)
              Positioned.fill(
                child: Listener(
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (_) => c.wake(),
                  child: const ColoredBox(color: Color(0xff000000)),
                ),
              )
            else if (_shown)
              Positioned.fill(
                child: Reveal(
                  visible: saving,
                  onHidden: () {
                    if (mounted) setState(() => _shown = false);
                  },
                  // Above the navigator there is no Material, and text falls
                  // back to Flutter's yellow-underlined error style.
                  child: Material(
                    type: MaterialType.transparency,
                    child: Screensaver(
                      config: c.effective,
                      onWake: c.wake,
                      weather: widget.weather?.value,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
