import 'dart:async';

/// `return_after`: once another app has had the screen for that long - the
/// stock launcher's menu after a stray Home press, mostly - the app puts
/// itself back in front. It is how the dashboard stays the dashboard without
/// replacing the stock launcher as home, which on some panels also runs the
/// Matter bridge and the relays.
///
/// Only another app counts: the panel sleeping its own screen keeps the app
/// in the foreground, so a dark panel is never "away".
class ReturnToFront {
  ReturnToFront({required this.bringToFront});

  final Future<void> Function() bringToFront;
  Timer? _timer;
  int _seconds = 0;
  bool _foreground = true;

  /// Seconds in the background before coming back; 0 is never.
  int get seconds => _seconds;
  set seconds(int v) {
    if (v == _seconds) return;
    _seconds = v;
    _timer?.cancel();
    _timer = null;
    _arm();
  }

  /// Whether the app has the screen now.
  set foreground(bool v) {
    if (v == _foreground) return;
    _foreground = v;
    if (v) {
      _timer?.cancel();
      _timer = null;
    } else {
      _arm();
    }
  }

  void _arm() {
    if (_foreground || _seconds <= 0 || _timer != null) return;
    _timer = Timer(Duration(seconds: _seconds), () {
      _timer = null;
      if (_foreground) return;
      unawaited(bringToFront());
      // and again a period later, should that one not have taken
      _arm();
    });
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
