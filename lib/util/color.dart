import 'dart:ui';

/// A light's own colour, made safe to put white text on.
///
/// The fill is a tint over a dark card with the card's text on top. Raw bulb
/// colours break that at both ends: a white light washes the fill out until
/// the label disappears into it, and a saturated blue is so dark it vanishes
/// against the card. So the colour is pulled into a luminance band - scaled
/// down above 170, mixed toward white below 70. Hue survives, which is the
/// part that matters: a blue lamp still reads blue.
///
/// Same maths as readableTint() in the web bundle.
Color readableTint(List<num> rgb) {
  double r = rgb[0].toDouble().clamp(0, 255);
  double g = rgb[1].toDouble().clamp(0, 255);
  double b = rgb[2].toDouble().clamp(0, 255);
  final lum = 0.2126 * r + 0.7152 * g + 0.0722 * b;
  if (lum > 170) {
    final k = 170 / lum;
    r *= k;
    g *= k;
    b *= k;
  } else if (lum < 70) {
    // Scaling up cannot help a channel already at 255, so lift toward white.
    final k = (70 - lum) / (255 - lum);
    r += (255 - r) * k;
    g += (255 - g) * k;
    b += (255 - b) * k;
  }
  return Color.fromARGB(255, r.round(), g.round(), b.round());
}

/// One accent in, the two translucent stops of the fill gradient out.
({Color strong, Color weak}) tintStops(Color accent) =>
    (strong: accent.withValues(alpha: .62), weak: accent.withValues(alpha: .34));

Color? parseHex(String? hex) {
  if (hex == null) return null;
  var h = hex.trim().replaceFirst('#', '');
  if (h.length == 3) h = h.split('').map((c) => '$c$c').join();
  if (h.length != 6) return null;
  final v = int.tryParse(h, radix: 16);
  return v == null ? null : Color(0xFF000000 | v);
}
