import 'package:flutter/material.dart';

/// The same tokens as BASE_CSS in the web bundle, so the two renderers agree.
class Ns {
  static const ground = Color(0xFF0B0D10);
  static const surface = Color(0xFF16191F);
  static const surface2 = Color(0xFF1E232B);
  static const text = Color(0xFFF2F4F7);
  static const muted = Color(0xFF98A1B0);
  static const amber = Color(0xFFFFB74A);
  static const sky = Color(0xFF7CC4FF);
  static const ember = Color(0xFFFF8A65);
  static const violet = Color(0xFFA78BFA);
  static const mint = Color(0xFF8DDBA4);
  static const gold = Color(0xFFF0A03C);
  static const danger = Color(0xFFF87171);

  static const radius = 22.0;
  static const gap = 12.0;

  /// Text sits over an arbitrary fill, so it carries a small shadow - the
  /// same one the web card uses. Glyph shadows are rasterised with the text,
  /// not as a separate blur pass.
  static const shadow = [Shadow(offset: Offset(0, 1), blurRadius: 3, color: Color(0x73000000))];

  static const tabular = [FontFeature.tabularFigures()];

  static ThemeData theme() => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: ground,
        colorScheme: const ColorScheme.dark(primary: amber, surface: surface),
        fontFamily: 'Roboto',
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
      );
}
