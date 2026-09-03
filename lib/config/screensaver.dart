import 'dashboard.dart';

/// What the panel does when nobody has touched it for a while.
///
/// Configured either as a `custom:nspanel-screensaver` card anywhere in the
/// dashboard (renders nothing; the app reads it and drops it), or under
/// `screensaver` in a pushed setup.json. The card wins when both exist.
class ScreensaverConfig {
  const ScreensaverConfig({
    this.afterSeconds = 300,
    this.imageUrl,
    this.imageRefreshSeconds = 600,
    this.clock = true,
    this.moveSeconds = 60,
    this.frost = true,
    this.wakeOnProximity = true,
    this.proximityDelta = 12,
    this.proximityBelow,
    this.proximityAbove,
  });

  final int afterSeconds;
  final String? imageUrl;
  final int imageRefreshSeconds;
  final bool clock;
  final int moveSeconds;
  final bool frost;

  /// Wake when the proximity reading moves away from its resting level by
  /// more than [proximityDelta] - learned during the first seconds of the
  /// screensaver, so nobody has to know which way the sensor counts.
  /// [proximityBelow] / [proximityAbove] are absolute overrides for people who
  /// have watched the readout and know.
  final bool wakeOnProximity;
  final double proximityDelta;
  final double? proximityBelow;
  final double? proximityAbove;

  static const cardTypeName = 'nspanel-screensaver';

  static ScreensaverConfig fromMap(Map<String, dynamic> m) => ScreensaverConfig(
        afterSeconds: (m['after'] as num?)?.toInt() ?? 300,
        imageUrl: m['image_url']?.toString(),
        imageRefreshSeconds: (m['image_refresh'] as num?)?.toInt() ?? 600,
        clock: m['clock'] is bool ? m['clock'] as bool : true,
        moveSeconds: (m['move_every'] as num?)?.toInt() ?? 60,
        frost: m['frost'] is bool ? m['frost'] as bool : true,
        wakeOnProximity: m['wake_on_proximity'] is bool ? m['wake_on_proximity'] as bool : true,
        proximityDelta: (m['proximity_delta'] as num?)?.toDouble() ?? 12,
        proximityBelow: (m['proximity_below'] as num?)?.toDouble(),
        proximityAbove: (m['proximity_above'] as num?)?.toDouble(),
      );

  /// The screensaver card, wherever it is in the dashboard - a view, a stack,
  /// a swipe card, a grid. First one wins.
  static ScreensaverConfig? findInLovelace(Map<String, dynamic> config) {
    CardConfig? found;
    void walk(dynamic node) {
      if (found != null) return;
      if (node is Map) {
        final m = node.cast<String, dynamic>();
        if (cardType(m) == ScreensaverConfig.cardTypeName) {
          found = m;
          return;
        }
        for (final key in ['views', 'cards', 'sections']) {
          if (m[key] is List) walk(m[key]);
        }
      } else if (node is List) {
        for (final n in node) {
          walk(n);
        }
      }
    }

    walk(config);
    return found == null ? null : fromMap(found!);
  }
}
