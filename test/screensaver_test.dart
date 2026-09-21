import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nspanel_app/config/screensaver.dart';

void main() {
  test(
    'defaults: five minutes, clock on, frost on, proximity on, no image',
    () {
      final s = ScreensaverConfig.fromMap({});
      expect(s.afterSeconds, 300);
      expect(s.imageUrl, isNull);
      expect(s.imageFit, 'contain');
      expect(
        ScreensaverConfig.fromMap({'image_fit': 'cover'}).imageFit,
        'cover',
      );
      expect(
        ScreensaverConfig.fromMap({'image_fit': 'stretch'}).imageFit,
        'contain',
      );
      expect(s.clock, isTrue);
      expect(s.clockPosition, 'wander');
      expect(s.clockWanders, isTrue);
      expect(s.clockSize, 64);
      expect(s.clockDate, isTrue);
      expect(s.frost, isTrue);
      expect(s.sleep, isFalse);
      expect(s.sleepAfterSeconds, 0);
      expect(s.wakeOnProximity, isTrue);
      expect(s.proximityDelta, 12);
      expect(s.proximityBelow, isNull);
    },
  );

  test('reads the card options', () {
    final s = ScreensaverConfig.fromMap({
      'after': 120,
      'image_url': 'https://example.com/r/x',
      'image_refresh': 300,
      'move_every': 30,
      'frost': false,
      'clock_position': 'bottom-right',
      'clock_size': 96,
      'clock_date': false,
      'sleep': true,
      'sleep_after': 600,
      'wake_on_proximity': false,
      'proximity_below': 40,
    });
    expect(s.afterSeconds, 120);
    expect(s.imageUrl, 'https://example.com/r/x');
    expect(s.imageRefreshSeconds, 300);
    expect(s.moveSeconds, 30);
    expect(s.frost, isFalse);
    expect(s.clockPosition, 'bottom-right');
    expect(s.clockWanders, isFalse);
    expect(
      ScreensaverConfig.clockSpots[s.clockPosition],
      const Alignment(0.8, 0.8),
    );
    expect(s.clockSize, 96);
    expect(s.clockDate, isFalse);
    expect(s.sleep, isTrue);
    expect(s.sleepAfterSeconds, 600);
    expect(ScreensaverConfig.fromMap({'sleep_after': -5}).sleepAfterSeconds, 0);
    // an unknown spot wanders; the size is kept readable
    expect(
      ScreensaverConfig.fromMap({'clock_position': 'middle'}).clockWanders,
      isTrue,
    );
    expect(ScreensaverConfig.fromMap({'clock_size': 4}).clockSize, 24);
    expect(ScreensaverConfig.fromMap({'clock_size': 900}).clockSize, 160);
    expect(s.wakeOnProximity, isFalse);
    expect(s.proximityBelow, 40);
  });

  test('overrides from HA win over the card, key by key, and are clamped', () {
    final card = ScreensaverConfig.fromMap({
      'after': 300,
      'sleep': false,
      'image_url': 'https://x/p',
    });
    final s = card.withOverrides({
      'after': 60,
      'sleep': true,
      'proximity_delta': 30,
    });
    expect(s.afterSeconds, 60);
    expect(s.sleep, isTrue);
    expect(s.sleepAfterSeconds, 0, reason: 'not overridden: the card value');
    expect(s.proximityDelta, 30);
    expect(s.imageUrl, 'https://x/p', reason: 'everything else is the card');
    expect(card.withOverrides(null), same(card));
    expect(card.withOverrides({}), same(card));
    expect(card.withOverrides({'after': 1}).afterSeconds, 10);
  });

  test('is found wherever it sits in the dashboard', () {
    final cfg = {
      'views': [
        {
          'type': 'panel',
          'cards': [
            {
              'type': 'custom:simple-swipe-card',
              'cards': [
                {
                  'type': 'vertical-stack',
                  'cards': [
                    {'type': 'custom:nspanel-light-card', 'entity': 'light.a'},
                    {
                      'type': 'custom:nspanel-screensaver',
                      'after': 90,
                      'image_url': 'u',
                    },
                  ],
                },
              ],
            },
          ],
        },
      ],
    };
    final s = ScreensaverConfig.findInLovelace(cfg);
    expect(s, isNotNull);
    expect(s!.afterSeconds, 90);
    expect(s.imageUrl, 'u');
  });

  test('absent means null, not a default screensaver', () {
    expect(ScreensaverConfig.findInLovelace({'views': []}), isNull);
    expect(ScreensaverConfig.findInLovelace({}), isNull);
  });
}
