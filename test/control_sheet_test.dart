import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nspanel_app/ui/sheet.dart';

void main() {
  testWidgets(
    'existing sheet callers keep percentage, step and close behavior',
    (tester) async {
      final commits = <double>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () => showControlSheet(
                context,
                title: 'Cover',
                state: 'Open',
                value: .5,
                accent: Colors.blue,
                fromTop: true,
                step: 5,
                onCommit: commits.add,
              ),
              child: const Text('Open details'),
            ),
          ),
        ),
      );
      await tester.tap(find.text('Open details'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('50%'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();
      expect(commits, [.55]);
      expect(find.text('55%'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byType(ControlSheet), findsNothing);
      expect(commits, [.55]);
    },
  );

  Future<void> open(WidgetTester t, {Duration? autoClose}) async {
    Sheets.autoClose = autoClose;
    addTearDown(() => Sheets.autoClose = const Duration(seconds: 30));
    await t.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Column(
            children: [
              const Text('Dashboard card'),
              TextButton(
                onPressed: () => showControlSheet(
                  context,
                  title: 'Dining lights',
                  state: 'On · 66%',
                  value: .66,
                  accent: Colors.amber,
                ),
                child: const Text('Open details'),
              ),
            ],
          ),
        ),
      ),
    );
    await t.tap(find.text('Open details'));
    await t.pumpAndSettle();
    expect(find.byType(ControlSheet), findsOneWidget);
  }

  Future<void> settle(WidgetTester t) async {
    await t.pump();
    await t.pump(const Duration(milliseconds: 200));
  }

  testWidgets('nothing of the dashboard shows behind the page', (t) async {
    await open(t);
    // an opaque route: the page below is not painted at all
    expect(find.text('Dashboard card'), findsNothing);
    expect(find.text('Dashboard card', skipOffstage: false), findsOneWidget);
  });

  testWidgets('the whole header closes it, not just the button', (t) async {
    await open(t);
    await t.tap(find.text('Dining lights')); // the title, far from the X
    await settle(t);
    expect(find.byType(ControlSheet), findsNothing);
    expect(find.text('Dashboard card'), findsOneWidget);
  });

  testWidgets('untouched, it closes itself after the timeout', (t) async {
    await open(t, autoClose: const Duration(seconds: 10));
    await t.pump(const Duration(seconds: 9));
    expect(find.byType(ControlSheet), findsOneWidget);
    await t.pump(const Duration(seconds: 1));
    await settle(t);
    expect(find.byType(ControlSheet), findsNothing);
  });

  testWidgets('a touch starts the count again, a held finger stops it', (t) async {
    await open(t, autoClose: const Duration(seconds: 10));
    await t.pump(const Duration(seconds: 8));
    await t.tap(find.byIcon(Icons.add)); // a step: the count starts again
    await t.pump(const Duration(seconds: 8));
    expect(find.byType(ControlSheet), findsOneWidget);

    // a finger resting on the slider for longer than the timeout
    final g = await t.startGesture(t.getCenter(find.text('71%')));
    await t.pump(const Duration(seconds: 30));
    expect(find.byType(ControlSheet), findsOneWidget);
    await g.up();
    await t.pump(const Duration(seconds: 9));
    expect(find.byType(ControlSheet), findsOneWidget);
    await t.pump(const Duration(seconds: 1));
    await settle(t);
    expect(find.byType(ControlSheet), findsNothing);
  });

  testWidgets('a timeout of nothing keeps it open', (t) async {
    await open(t);
    Sheets.autoClose = null;
    await t.pump(const Duration(minutes: 10));
    expect(find.byType(ControlSheet), findsOneWidget);
  });
}
