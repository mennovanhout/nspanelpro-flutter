import 'package:flutter_test/flutter_test.dart';
import 'package:nspanel_app/util/color.dart';

double lum(int r, int g, int b) => 0.2126 * r + 0.7152 * g + 0.0722 * b;

void main() {
  group('readableTint keeps white text legible', () {
    test('a white light is scaled down, not left white', () {
      final c = readableTint([255, 255, 255]);
      expect(c.r, closeTo(c.g, .01)); // still neutral
      expect(lum((c.r * 255).round(), (c.g * 255).round(), (c.b * 255).round()), lessThanOrEqualTo(171));
    });

    test('a deep blue is lifted off the dark card, hue kept', () {
      final c = readableTint([0, 0, 255]);
      final r = (c.r * 255).round(), g = (c.g * 255).round(), b = (c.b * 255).round();
      expect(lum(r, g, b), greaterThanOrEqualTo(69));
      expect(b, greaterThan(r)); // still blue
      expect(b, greaterThan(g));
    });

    test('a 2700K warm white passes through nearly unchanged', () {
      final c = readableTint([255, 169, 87]);
      final r = (c.r * 255).round(), g = (c.g * 255).round(), b = (c.b * 255).round();
      expect(r, greaterThan(g));
      expect(g, greaterThan(b));
      expect(lum(r, g, b), inInclusiveRange(69, 171));
    });

    test('a saturated red survives as red', () {
      final c = readableTint([255, 0, 0]);
      expect((c.r * 255).round(), greaterThan(200));
      expect((c.g * 255).round(), lessThan(80));
    });
  });

  test('parseHex handles 3 and 6 digit forms and rejects junk', () {
    expect(parseHex('#ffb74a')!.toARGB32(), 0xFFFFB74A);
    expect(parseHex('fff')!.toARGB32(), 0xFFFFFFFF);
    expect(parseHex('#12'), isNull);
    expect(parseHex(null), isNull);
  });
}
