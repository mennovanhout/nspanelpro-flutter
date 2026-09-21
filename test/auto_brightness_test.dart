import 'package:flutter_test/flutter_test.dart';
import 'package:nspanel_app/util/auto_brightness.dart';

void main() {
  test('the curve: min in the dark, max at daylight, log in between', () {
    int b(double lux) =>
        autoBrightness(lux: lux, min: 20, max: 255, daylightLux: 500);
    expect(b(0), 20);
    expect(b(500), 255);
    expect(b(5000), 255);
    final dim = b(5), room = b(50), bright = b(250);
    expect(dim, greaterThan(20));
    expect(room, greaterThan(dim));
    expect(bright, greaterThan(room));
    expect(bright, lessThan(255));
    // logarithmic: 5 -> 50 lx is a bigger step than 250 -> 500
    expect(room - dim, greaterThan(255 - bright));
  });

  test(
    'min above max, or a broken daylight point, still gives a sane level',
    () {
      expect(
        autoBrightness(lux: 100, min: 200, max: 100, daylightLux: 500),
        200,
      );
      expect(autoBrightness(lux: 100, min: 20, max: 255, daylightLux: 0), 255);
    },
  );

  test('the follower smooths and only moves in steps', () {
    final f = BrightnessFollower(alpha: 0.5, step: 6);
    int? feed(double lux) => f.feed(lux, min: 20, max: 255, daylightLux: 500);
    expect(feed(100), isNotNull, reason: 'the first reading applies');
    expect(feed(101), isNull, reason: 'a flicker is not a change');
    expect(feed(102), isNull);
    // a real change: several readings walk the average up, and it applies once past the step
    int? applied;
    for (var i = 0; i < 6 && applied == null; i++) {
      applied = feed(500);
    }
    expect(applied, isNotNull);
    expect(applied, greaterThan(f.applied! - 1));
    f.reset();
    expect(
      feed(500),
      isNotNull,
      reason: 'after a manual change the next reading applies again',
    );
  });
}
