import 'package:flutter/widgets.dart';

/// Local value vs. incoming state.
///
/// `_local` is the value under the user's finger, or the one they just let go
/// of. For `echoMs` after a change, incoming state loses to it, so a slow
/// round-trip can never yank the fill backwards under a hand. `display()` is
/// the one place that resolves it - read values through it, never from the
/// entity directly.
mixin EchoMixin<T extends StatefulWidget> on State<T> {
  double? _local;
  DateTime _localUntil = DateTime.fromMillisecondsSinceEpoch(0);
  bool dragging = false;

  double display(double entityValue) {
    if (_local != null && (dragging || DateTime.now().isBefore(_localUntil))) return _local!;
    _local = null;
    return entityValue;
  }

  /// During a drag: track the finger, no timers, no service calls.
  void setLocal(double v) => setState(() => _local = v);

  /// After a change was sent: keep showing it until HA has had time to echo.
  void holdLocal(double v, int echoMs) {
    setState(() {
      _local = v;
      _localUntil = DateTime.now().add(Duration(milliseconds: echoMs));
    });
  }
}
