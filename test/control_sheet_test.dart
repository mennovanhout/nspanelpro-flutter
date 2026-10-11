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
}
