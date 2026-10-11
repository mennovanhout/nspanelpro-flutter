import 'package:flutter/material.dart';

import '../util/navigation_controller.dart';

class NavigationScope extends InheritedWidget {
  const NavigationScope({
    super.key,
    required this.navigation,
    required super.child,
  });
  final PanelNavigation navigation;
  static PanelNavigation? of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<NavigationScope>()?.navigation;
  @override
  bool updateShouldNotify(NavigationScope oldWidget) =>
      oldWidget.navigation != navigation;
}

/// Register the precise dialog route; inactivity never pops setup/other routes.
Future<void> showPanelDialog(
  BuildContext context, {
  required RoutePageBuilder pageBuilder,
  required RouteTransitionsBuilder transitionBuilder,
}) {
  final nav = NavigationScope.of(context);
  final navigator = Navigator.of(context, rootNavigator: true);
  late final RawDialogRoute<void> route;
  route = RawDialogRoute<void>(
    barrierDismissible: true,
    barrierLabel: 'close',
    barrierColor: const Color(0xFF0B0D10).withValues(alpha: .72),
    transitionDuration: const Duration(milliseconds: 180),
    transitionBuilder: transitionBuilder,
    pageBuilder: (ctx, a, b) {
      final child = pageBuilder(ctx, a, b);
      return nav == null
          ? child
          : NavigationScope(navigation: nav, child: child);
    },
  );
  final done = navigator.push(route);
  final unregister = nav?.registerDialog(() {
    if (route.isActive) navigator.removeRoute(route);
  });
  return done.whenComplete(() => unregister?.call());
}
