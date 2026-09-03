import 'package:flutter_test/flutter_test.dart';
import 'package:nspanel_app/config/screensaver.dart';

void main() {
  test('defaults: five minutes, clock on, frost on, proximity on, no image', () {
    final s = ScreensaverConfig.fromMap({});
    expect(s.afterSeconds, 300);
    expect(s.imageUrl, isNull);
    expect(s.clock, isTrue);
    expect(s.frost, isTrue);
    expect(s.wakeOnProximity, isTrue);
    expect(s.proximityDelta, 12);
    expect(s.proximityBelow, isNull);
  });

  test('reads the card options', () {
    final s = ScreensaverConfig.fromMap({
      'after': 120,
      'image_url': 'https://example.com/r/x',
      'image_refresh': 300,
      'move_every': 30,
      'frost': false,
      'wake_on_proximity': false,
      'proximity_below': 40,
    });
    expect(s.afterSeconds, 120);
    expect(s.imageUrl, 'https://example.com/r/x');
    expect(s.imageRefreshSeconds, 300);
    expect(s.moveSeconds, 30);
    expect(s.frost, isFalse);
    expect(s.wakeOnProximity, isFalse);
    expect(s.proximityBelow, 40);
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
                    {'type': 'custom:nspanel-screensaver', 'after': 90, 'image_url': 'u'},
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
