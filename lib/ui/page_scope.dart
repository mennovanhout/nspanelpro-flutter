import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Which page a card sits on, which page is showing, and whether anybody can
/// see the dashboard at all.
///
/// Most cards never look: they follow their entity and cost nothing when it
/// does not change. A card that fetches while it is on screen - the camera -
/// asks here, so a camera on page three does nothing while page one is
/// showing or the screensaver is up. A card built outside a pager (a test, a
/// single page) finds no scope and counts as active.
class PageScope extends InheritedWidget {
  const PageScope({
    super.key,
    required this.index,
    required this.shown,
    required this.awake,
    required super.child,
  });

  /// This page's place in the pager; -1 for a copy that is never on screen
  /// (the warm-up paints every page once, hidden).
  final int index;
  final ValueListenable<int> shown;
  final ValueListenable<bool> awake;

  bool get active => index >= 0 && shown.value == index && awake.value;

  /// Fires when [active] may have changed.
  Listenable get changes => Listenable.merge([shown, awake]);

  static PageScope? maybeOf(BuildContext context) => context.getInheritedWidgetOfExactType<PageScope>();

  @override
  bool updateShouldNotify(PageScope old) => index != old.index || shown != old.shown || awake != old.awake;
}
