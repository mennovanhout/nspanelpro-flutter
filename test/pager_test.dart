import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nspanel_app/ui/pager.dart';

void main() {
  // The forum report: an automation sets the page entity to 0 when the
  // screensaver comes on, and nothing happens. Someone had swiped to another
  // page by hand, and HA's "0" was the value it had last asked for.
  testWidgets('HA turns the page after a swipe by hand, also to the page it asked for last', (t) async {
    final jump = PageJump();
    final shown = <int>[];
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PanelPager(
            jump: jump,
            onPage: shown.add,
            pages: [for (final n in ['one', 'two', 'three']) Center(child: Text(n))],
          ),
        ),
      ),
    );
    expect(find.text('one'), findsOneWidget);

    // a swipe by hand to the second page
    await t.drag(find.byType(PageView), const Offset(-500, 0));
    await t.pumpAndSettle();
    expect(shown.last, 1);

    // HA: page 0 - never asked for before, but 0 is where the notifier starts
    jump.go(0);
    await t.pumpAndSettle();
    expect(shown.last, 0);
    expect(find.text('one'), findsOneWidget);

    // HA: page 2, a swipe back by hand, then page 2 again
    jump.go(2);
    await t.pumpAndSettle();
    expect(shown.last, 2);
    await t.drag(find.byType(PageView), const Offset(500, 0));
    await t.pumpAndSettle();
    expect(shown.last, 1);
    jump.go(2);
    await t.pumpAndSettle();
    expect(shown.last, 2);
    expect(find.text('three'), findsOneWidget);

    // out of range is the last page, not an exception
    jump.go(0);
    await t.pumpAndSettle();
    jump.go(9);
    await t.pumpAndSettle();
    expect(shown.last, 2);
    expect(t.takeException(), isNull);
  });
}
