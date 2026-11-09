import 'dart:async';

import 'package:flutter/foundation.dart';

/// Dashboard-local commands and inactivity. No HA, display power or sensor I/O.
class PanelNavigation extends ChangeNotifier {
  PanelNavigation({int Function()? now})
    : _now = now ?? (() => DateTime.now().millisecondsSinceEpoch);
  final int Function() _now;
  int count = 0, current = 0, start = 0, after = 0;
  Map<int, int> overrides = const {};
  int? target;
  bool animate = true;
  int revision = 0;
  int fingers = 0;
  bool scrolling = false, visible = true;
  bool _disposed = false, _returning = false;
  int? _deadline, _pending;
  String? _structure;
  Timer? _timer;
  final _dialogs = <VoidCallback>{};
  bool get busy => fingers > 0 || scrolling;
  int get seconds => after == 0 ? 0 : (overrides[current] ?? after);
  bool valid(int index) => index >= 0 && index < count;

  void configure({
    required int count,
    required int start,
    required int after,
    required Map<int, int> overrides,
    required String structure,
  }) {
    if (_disposed) return;
    final changed =
        this.count != count ||
        this.start != start ||
        this.after != after ||
        !mapEquals(this.overrides, overrides) ||
        _structure != structure;
    if (!changed) return;
    final first = _structure == null || this.count == 0;
    _structure = structure;
    this.count = count;
    this.start = count == 0 ? 0 : start.clamp(0, count - 1);
    this.after = after;
    this.overrides = Map.of(overrides);
    _pending = null;
    closeDialogs();
    if (first || !valid(current)) current = this.start;
    _command(current, animated: false);
    activity();
  }

  bool navigate(int index) {
    if (_disposed || !valid(index)) return false;
    if (busy) {
      _pending = index;
      return true;
    }
    closeDialogs();
    _command(index, animated: visible);
    // The destination duration starts even for an explicit repeated command.
    current = index;
    activity();
    return true;
  }

  void _command(int index, {required bool animated}) {
    target = count == 0 ? null : index;
    animate = animated;
    revision++;
    notifyListeners();
  }

  void shown(int index) {
    if (!valid(index)) return;
    final changed = current != index;
    current = index;
    if (target == index) target = null;
    if (changed && !_returning) activity();
  }

  void activity() {
    if (_disposed) return;
    _returning = false;
    _deadline = seconds > 0 && count > 0 ? _now() + seconds * 1000 : null;
    _arm();
  }

  void pointers(int count, {bool accepted = true}) {
    final ended = fingers > 0 && count == 0;
    fingers = count;
    if (accepted) activity();
    if (ended) _flush();
    _arm();
  }

  void scroll(bool active, {bool user = true}) {
    scrolling = active;
    if (user) activity();
    if (!active) _flush();
    _arm();
  }

  void visibility(bool value) {
    final resumed = !visible && value;
    visible = value;
    if (!value) {
      fingers = 0;
      scrolling = false;
    }
    if (resumed) check(animated: false);
    _arm();
  }

  void _flush() {
    if (busy) return;
    final pending = _pending;
    _pending = null;
    if (pending != null) {
      navigate(pending);
    } else {
      check();
    }
  }

  VoidCallback registerDialog(VoidCallback close) {
    _dialogs.add(close);
    activity();
    return () => _dialogs.remove(close);
  }

  void closeDialogs() {
    final dialogs = _dialogs.toList();
    _dialogs.clear();
    for (final close in dialogs) {
      close();
    }
  }

  void check({bool animated = true}) {
    if (_disposed ||
        !visible ||
        busy ||
        _deadline == null ||
        _now() < _deadline!) {
      return;
    }
    _deadline = null;
    _timer?.cancel();
    _returning = true;
    closeDialogs();
    if (valid(start) && current != start) {
      current = start;
      _command(start, animated: animated);
    }
  }

  void _arm() {
    _timer?.cancel();
    if (_disposed || !visible || busy || _deadline == null) return;
    _timer = Timer(
      Duration(milliseconds: (_deadline! - _now()).clamp(0, 86400000)),
      () {
        check();
        if (_deadline != null) _arm();
      },
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _dialogs.clear();
    super.dispose();
  }
}

/// Invalid explicit actions never fall through to an entity/service command.
int? navigationTarget(dynamic action) {
  if (action is! Map || action['action'] != 'navigate-page') return null;
  final page = action['page'];
  return page is num &&
          page.isFinite &&
          page >= 0 &&
          page == page.roundToDouble()
      ? page.toInt()
      : null;
}
