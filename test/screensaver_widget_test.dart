import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nspanel_app/config/screensaver.dart';
import 'package:nspanel_app/ui/screensaver.dart';

// a 1x1 png
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=',
);

void main() {
  clockTests();
  Widget host(String fit) => MaterialApp(
    home: Center(
      child: SizedBox(
        width: 480,
        height: 480,
        child: Screensaver(
          config: ScreensaverConfig.fromMap({
            'image_url': 'https://x/photo',
            'image_fit': fit,
            'clock': false,
          }),
          onWake: () {},
          imageProvider: (_) => MemoryImage(_png),
        ),
      ),
    ),
  );

  testWidgets(
    'the photo is laid out over the whole screen, whatever its own shape',
    (t) async {
      for (final fit in ['cover', 'contain']) {
        await t.pumpWidget(host(fit));
        await t.pump(const Duration(seconds: 2));
        final image = t.widget<Image>(find.byType(Image));
        expect(image.fit, fit == 'cover' ? BoxFit.cover : BoxFit.contain);
        // the box the fit works within is the screen, not the decoded picture
        expect(
          t.getSize(find.byType(Image)),
          const Size(480, 480),
          reason: fit,
        );
      }
    },
  );
}

void clockTests() {
  Widget host(Map<String, dynamic> cfg) => MaterialApp(
    home: Center(
      child: SizedBox(
        width: 480,
        height: 480,
        child: Screensaver(
          config: ScreensaverConfig.fromMap(cfg),
          onWake: () {},
        ),
      ),
    ),
  );

  testWidgets(
    'a fixed clock sits where it was told, at the size it was given, with or without the date',
    (t) async {
      await t.pumpWidget(
        host({
          'clock_position': 'top-left',
          'clock_size': 96,
          'clock_date': false,
        }),
      );
      await t.pump();
      expect(
        t.widget<AnimatedAlign>(find.byType(AnimatedAlign)).alignment,
        const Alignment(-0.8, -0.8),
      );
      final texts = t.widgetList<Text>(find.byType(Text)).toList();
      expect(texts.length, 1, reason: 'no date');
      expect(texts.single.style?.fontSize, 96);
      // past a wander interval: still where it was
      await t.pump(const Duration(seconds: 70));
      expect(
        t.widget<AnimatedAlign>(find.byType(AnimatedAlign)).alignment,
        const Alignment(-0.8, -0.8),
      );

      await t.pumpWidget(host({'clock_position': 'center'}));
      await t.pump();
      expect(
        t.widget<AnimatedAlign>(find.byType(AnimatedAlign)).alignment,
        Alignment.center,
      );
      expect(
        t.widgetList<Text>(find.byType(Text)).length,
        2,
        reason: 'time and date',
      );
      await t.pumpWidget(const SizedBox());
    },
  );
}
