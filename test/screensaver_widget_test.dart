import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nspanel_app/config/screensaver.dart';
import 'package:nspanel_app/ui/screensaver.dart';

// a 1x1 png
final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=');

void main() {
  Widget host(String fit) => MaterialApp(
        home: Center(
          child: SizedBox(
            width: 480,
            height: 480,
            child: Screensaver(
              config: ScreensaverConfig.fromMap({'image_url': 'https://x/photo', 'image_fit': fit, 'clock': false}),
              onWake: () {},
              imageProvider: (_) => MemoryImage(_png),
            ),
          ),
        ),
      );

  testWidgets('the photo is laid out over the whole screen, whatever its own shape', (t) async {
    for (final fit in ['cover', 'contain']) {
      await t.pumpWidget(host(fit));
      await t.pump(const Duration(seconds: 2));
      final image = t.widget<Image>(find.byType(Image));
      expect(image.fit, fit == 'cover' ? BoxFit.cover : BoxFit.contain);
      // the box the fit works within is the screen, not the decoded picture
      expect(t.getSize(find.byType(Image)), const Size(480, 480), reason: fit);
    }
  });
}
