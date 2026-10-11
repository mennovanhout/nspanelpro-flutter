import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nspanel_app/util/navigation_controller.dart';
import 'package:nspanel_app/config/dashboard.dart';
import 'package:nspanel_app/ui/pager.dart';
import 'package:nspanel_app/ui/navigation_scope.dart';
import 'package:nspanel_app/ui/sheet.dart';
import 'package:nspanel_app/ui/keypad.dart';
import 'package:nspanel_app/cards/button_card.dart';
import 'package:nspanel_app/cards/env.dart';
import 'package:nspanel_app/config/settings.dart';
import 'package:nspanel_app/ha/connection.dart';
import 'package:nspanel_app/ha/states.dart';

import 'connection_test.dart' show FakeHa;

void main() {
  late PanelNavigation nav;
  late int now;
  void configure({
    int count = 6,
    int start = 2,
    int after = 15,
    Map<int, int> overrides = const {5: 60},
  }) {
    nav.configure(
      count: count,
      start: start,
      after: after,
      overrides: overrides,
      structure: '$count',
    );
  }

  setUp(() {
    now = 0;
    nav = PanelNavigation(now: () => now);
    configure();
  });
  tearDown(() => nav.dispose());

  test('same command after manual swipe is delivered and invalid targets do nothing', () {
    final commands = <int?>[];
    nav.addListener(() => commands.add(nav.target));
    expect(nav.navigate(4), true);
    nav.shown(4);
    nav.shown(1);
    expect(nav.navigate(4), true);
    expect(commands, [4, 4]);
    expect(nav.navigate(-1), false);
    expect(nav.navigate(6), false);
    expect(commands, [4, 4]);
  });
  test('deadline boundary and general per-page duration', () {
    nav.navigate(1);
    now = 14999;
    nav.check();
    expect(nav.current, 1);
    now = 15000;
    nav.check();
    expect(nav.current, 2);
    nav.navigate(5);
    now = 74999;
    nav.check();
    expect(nav.current, 5);
    now = 75000;
    nav.check();
    expect(nav.current, 2);
  });
  test(
    'no repeated return after completion; explicit same page renews duration',
    () {
      var commands = 0;
      nav.addListener(() => commands++);
      nav.navigate(1);
      now = 10000;
      nav.navigate(1);
      now = 15000;
      nav.check();
      expect(nav.current, 1);
      now = 25000;
      nav.check();
      expect(nav.current, 2);
      final before = commands;
      now = 100000;
      nav.check();
      expect(commands, before);
    },
  );
  test(
    'held/multiple pointers block return and release starts a full interval',
    () {
      nav.navigate(1);
      nav.pointers(2);
      now = 60000;
      nav.check();
      expect(nav.current, 1);
      nav.pointers(1);
      now = 90000;
      nav.check();
      expect(nav.current, 1);
      nav.pointers(0);
      now = 104999;
      nav.check();
      expect(nav.current, 1);
      now = 105000;
      nav.check();
      expect(nav.current, 2);
    },
  );
  test('last explicit command waits for gesture and scroll settling', () {
    nav.pointers(1);
    nav.scroll(true);
    nav.navigate(4);
    nav.navigate(5);
    expect(nav.current, 2);
    nav.pointers(0);
    expect(nav.current, 2);
    nav.scroll(false);
    expect(nav.current, 5);
  });
  test(
    'sleep counts elapsed time; rejected wake gesture cannot renew deadline',
    () {
      nav.navigate(1);
      now = 5000;
      nav.visibility(false);
      now = 30000;
      nav.pointers(1, accepted: false);
      nav.visibility(true);
      expect(nav.current, 1);
      nav.pointers(0, accepted: false);
      expect(nav.current, 2);
    },
  );
  test('resume before deadline preserves page and original deadline', () {
    nav.navigate(5);
    now = 5000;
    nav.visibility(false);
    now = 45000;
    nav.visibility(true);
    expect(nav.current, 5);
    now = 60000;
    nav.check();
    expect(nav.current, 2);
  });
  test(
    'off and page-specific off do not return; unchanged config does not renew',
    () {
      configure(after: 0);
      nav.navigate(5);
      now = 100000;
      nav.check();
      expect(nav.current, 5);
      configure(overrides: {1: 0});
      nav.navigate(1);
      now = 200000;
      nav.check();
      expect(nav.current, 1);
      nav.navigate(4);
      now += 14000;
      configure(overrides: {1: 0});
      now += 1000;
      nav.check();
      expect(nav.current, 2);
    },
  );
  test('config removal, empty pages and disposal invalidate pending work', () {
    nav.navigate(5);
    configure(count: 2, start: 0);
    expect(nav.current, 0);
    configure(count: 0, start: 0);
    expect(nav.navigate(0), false);
    expect(nav.target, null);
    configure();
    expect(nav.current, 2);
  });
  test('owned dialog closes once, including on start, without actions', () {
    var closed = 0;
    nav.registerDialog(() => closed++);
    now = 15000;
    nav.check();
    expect(closed, 1);
    now = 30000;
    nav.check();
    expect(closed, 1);
  });
  test('configuration parser preserves valid per-page overrides and rejects invalid values', () {
    final options = pagerOptionsFromLovelace({
      'views': [
        {
          'cards': [
            {
              'type': 'custom:nspanel-swipe-card',
              'cards': [{}, {}],
              'return_to_start_after': 15,
              'return_to_start_overrides': [
                {'page': 1, 'after': 60},
                {'page': 1, 'after': 45},
                {'page': 0, 'after': 0},
                {'page': 0.5, 'after': 9},
                {'page': 1, 'after': -1},
                {'page': '1', 'after': 9},
              ],
            },
          ],
        },
      ],
    });
    expect(options.returnAfter, 15);
    expect(options.returnOverrides, {1: 45, 0: 0});
    for (final action in [
      null,
      {},
      {'action': 'navigate-page', 'page': 1.5},
      {'action': 'navigate-page', 'page': -1},
      {'action': 'bad', 'page': 1},
    ]) {
      expect(navigationTarget(action), null);
    }
  });

  testWidgets(
    'real pager supports repeated commands, swiping, shrinking and current dots',
    (tester) async {
      Widget build(int count) => MaterialApp(
        home: SizedBox(
          width: 480,
          height: 480,
          child: PanelPager(
            jump: nav,
            initialPage: nav.current,
            pages: [
              for (var i = 0; i < count; i++) Center(child: Text('Page $i')),
            ],
          ),
        ),
      );
      await tester.pumpWidget(build(6));
      await tester.pumpAndSettle();
      nav.navigate(4);
      await tester.pumpAndSettle();
      expect(find.text('Page 4').hitTestable(), findsOneWidget);
      await tester.drag(find.byType(PageView), const Offset(700, 0));
      await tester.pumpAndSettle();
      nav.navigate(4);
      await tester.pumpAndSettle();
      expect(find.text('Page 4').hitTestable(), findsOneWidget);
      configure(count: 2, start: 0);
      await tester.pumpWidget(build(2));
      await tester.pumpAndSettle();
      expect(find.text('Page 0').hitTestable(), findsOneWidget);
      expect(tester.takeException(), null);
      nav.visibility(false);
    },
  );

  testWidgets('idle removes only owned sheet and keypad; no commit or submit', (
    tester,
  ) async {
    final calls = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: NavigationScope(
          navigation: nav,
          child: Builder(
            builder: (ctx) => Column(
              children: [
                TextButton(
                  onPressed: () => showControlSheet(
                    ctx,
                    title: 'Test sheet',
                    state: 'Ready',
                    value: .5,
                    accent: Colors.blue,
                    onCommit: (_) => calls.add('commit'),
                  ),
                  child: const Text('Sheet'),
                ),
                TextButton(
                  onPressed: () => showKeypadSheet(
                    ctx,
                    title: 'Test code',
                    accent: Colors.blue,
                    onSubmit: (_) async {
                      calls.add('submit');
                      return true;
                    },
                  ),
                  child: const Text('Code'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Sheet'));
    await tester.pumpAndSettle();
    expect(find.text('Test sheet'), findsOneWidget);
    now = 15000;
    nav.check();
    await tester.pumpAndSettle();
    expect(find.text('Test sheet'), findsNothing);
    await tester.tap(find.text('Code'));
    await tester.pumpAndSettle();
    expect(find.text('Test code'), findsWidgets);
    now = 30000;
    nav.check();
    await tester.pumpAndSettle();
    expect(find.text('Test code'), findsNothing);
    expect(find.text('Sheet'), findsOneWidget);
    expect(calls, isEmpty);
  });

  testWidgets(
    'navigation button works offline, takes precedence and refreshes configuration',
    (tester) async {
      tester.view.physicalSize = const Size(480, 480);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fake = FakeHa({});
      final states = HaStates();
      final conn = HaConnection(
        transportFactory: () async => fake,
        token: 'fake',
        states: states,
      );
      final env = PanelEnv(
        states: states,
        conn: conn,
        settings: Settings(url: 'http://fake', token: 'fake'),
        navigation: nav,
      );
      Widget build(dynamic page) => MaterialApp(
        home: ButtonCard(
          env: env,
          config: {
            'height': 120,
            'columns': 3,
            'haptics': false,
            'buttons': [
              {
                'name': 'Go',
                'entity': 'switch.missing',
                'service': 'switch.turn_on',
                'tap_action': {'action': 'navigate-page', 'page': page},
              },
              {
                'name': 'Other',
                'tap_action': {'action': 'navigate-page', 'page': 3},
              },
              {
                'name': 'Third',
                'tap_action': {'action': 'navigate-page', 'page': 4},
              },
            ],
          },
        ),
      );
      await tester.pumpWidget(build(1));
      await tester.tap(find.text('Go'));
      await tester.pump();
      expect(nav.current, 1);
      final target = find
          .ancestor(of: find.text('Go'), matching: find.byType(GestureDetector))
          .first;
      expect(tester.getSize(target).height, greaterThanOrEqualTo(56));
      expect(tester.getSize(target).width, greaterThanOrEqualTo(56));
      await tester.pumpWidget(build(5));
      await tester.tap(find.text('Go'));
      await tester.pump();
      expect(nav.current, 5);
      await tester.pumpWidget(build(-1));
      await tester.tap(find.text('Go'));
      await tester.pump();
      expect(nav.current, 5);
      expect(fake.calls, isEmpty);
      await tester.pumpWidget(const SizedBox());
      nav.visibility(false);
      await conn.dispose();
    },
  );
}
