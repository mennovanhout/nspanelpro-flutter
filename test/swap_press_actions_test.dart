import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nspanel_app/cards/light_card.dart';
import 'package:nspanel_app/cards/light_sheet.dart';
import 'package:nspanel_app/ha/states.dart';
import 'package:nspanel_app/ui/fill_card.dart';
import 'package:nspanel_app/ui/sheet.dart';

import 'light_widget_test.dart' as light;
import 'switch_details_test.dart' as switches;

void main() {
  for (final disabled in [false, true]) {
    testWidgets(
      'swapped light tap details / hold once (details disabled=$disabled)',
      (t) async {
        final (fake, _) = await light.mount(
          t,
          ['brightness'],
          config: {
            'swap_press_actions': true,
            'show_presets': false,
            if (disabled) 'long_press': 'none',
          },
        );
        await t.tap(find.text('Test light'));
        await t.pumpAndSettle();
        expect(
          find.byType(ControlSheet),
          disabled ? findsNothing : findsOneWidget,
        );
        expect(fake.calls, isEmpty);
        if (!disabled) {
          await t.tap(find.byIcon(Icons.close));
          await t.pumpAndSettle();
        }
        final g = await t.startGesture(t.getCenter(find.text('Test light')));
        await t.pump(const Duration(milliseconds: 650));
        expect(fake.calls, ['light.toggle {"entity_id":"light.test"}']);
        await g.up();
        await t.pumpAndSettle();
        expect(fake.calls.length, 1);
        expect(find.byType(ControlSheet), findsNothing);
      },
    );
  }
  testWidgets('swapped light cancel, swipe, unavailable and config reload', (
    t,
  ) async {
    final (fake, states) = await light.mount(
      t,
      ['onoff'],
      config: {'swap_press_actions': true, 'title': 'Test light'},
    );
    var g = await t.startGesture(t.getCenter(find.byType(FillCard)));
    await g.cancel();
    await t.pumpAndSettle();
    await t.drag(find.byType(FillCard), const Offset(100, 0));
    await t.pumpAndSettle();
    expect(fake.calls, isEmpty);
    expect(find.byType(ControlSheet), findsNothing);
    states.update(
      'light.test',
      const HaState(
        entityId: 'light.test',
        state: 'unavailable',
        attributes: {},
      ),
    );
    await t.pump();
    await t.tap(find.text('Test light'));
    await t.longPress(find.text('Test light'));
    await t.pumpAndSettle();
    expect(fake.calls, isEmpty);
    expect(find.byType(ControlSheet), findsNothing);
    states.update(
      'light.test',
      const HaState(
        entityId: 'light.test',
        state: 'off',
        attributes: {
          'supported_color_modes': ['onoff'],
        },
      ),
    );
    final old = t.widget<LightCard>(find.byType(LightCard));
    await t.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LightCard(
            config: {...old.config, 'swap_press_actions': false},
            env: old.env,
          ),
        ),
      ),
    );
    await t.tap(find.text('Test light'));
    await t.pumpAndSettle();
    expect(fake.calls.length, 1);
  });
  for (final itemOverride in [null, false, true]) {
    testWidgets(
      'switch item override $itemOverride and separate detail target',
      (t) async {
        final swap = itemOverride ?? true;
        final (fake, states) = await switches.mount(
          t,
          config: {
            'swap_press_actions': true,
            'switches': [
              {
                'entity': 'switch.test',
                'name': 'Shortcut',
                'detail_entity': 'light.detail',
                'swap_press_actions': ?itemOverride,
              },
            ],
          },
        );
        states.update(
          'light.detail',
          const HaState(
            entityId: 'light.detail',
            state: 'on',
            attributes: {
              'supported_color_modes': ['color_temp'],
              'brightness': 255,
            },
          ),
        );
        await t.pump();
        if (swap) {
          await t.tap(find.text('Shortcut'));
        } else {
          await t.longPress(find.text('Shortcut'));
        }
        await t.pumpAndSettle();
        expect(find.byType(LightSheet), findsOneWidget);
        expect(fake.calls, isEmpty);
        expect(
          t.widget<LightSheet>(find.byType(LightSheet)).config['entity'],
          'light.detail',
        );
        await t.tap(find.byIcon(Icons.close));
        await t.pumpAndSettle();
        if (swap) {
          await t.longPress(find.text('Shortcut'));
        } else {
          await t.tap(find.text('Shortcut'));
        }
        await t.pumpAndSettle();
        expect(fake.calls, [
          'homeassistant.turn_on {"entity_id":"switch.test"}',
        ]);
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(seconds: 2));
      },
    );
  }
  testWidgets(
    'swapped switch disabled details, movement and unknown block actions',
    (t) async {
      final (fake, states) = await switches.mount(
        t,
        config: {'swap_press_actions': true, 'more_info': false},
      );
      await t.tap(find.text('Test entity'));
      await t.pumpAndSettle();
      expect(find.byType(ControlSheet), findsNothing);
      expect(fake.calls, isEmpty);
      final g = await t.startGesture(t.getCenter(find.text('Test entity')));
      await g.cancel();
      await t.pumpAndSettle();
      expect(fake.calls, isEmpty);
      await t.longPress(find.text('Test entity'));
      await t.pumpAndSettle();
      expect(fake.calls.length, 1);
      states.update(
        'switch.test',
        const HaState(
          entityId: 'switch.test',
          state: 'unknown',
          attributes: {'friendly_name': 'Test entity'},
        ),
      );
      await t.pump();
      await t.tap(find.text('Test entity'));
      await t.longPress(find.text('Test entity'));
      await t.pumpAndSettle();
      expect(fake.calls.length, 1);
      await t.drag(find.text('Test entity'), const Offset(-400, 0));
      await t.pumpAndSettle();
      expect(find.text('Next page'), findsOneWidget);
      expect(fake.calls.length, 1);
      await t.pumpWidget(const SizedBox());
      await t.pump(const Duration(seconds: 2));
    },
  );
}
