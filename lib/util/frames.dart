import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Counts frames that missed their budget and says why in the log, so a
/// laggy swipe on the panel is a number, not a feeling. `adb logcat -s flutter`
/// shows lines like `frame: build 41ms raster 9ms` for each slow one.
class FrameWatch {
  FrameWatch({this.budget = const Duration(milliseconds: 33)});

  final Duration budget;

  /// How many slow frames since launch. Published to HA as a diagnostic.
  final slow = ValueNotifier<int>(0);

  void start() => SchedulerBinding.instance.addTimingsCallback(_onTimings);

  void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      if (t.totalSpan <= budget) continue;
      slow.value += 1;
      debugPrint('frame: build ${t.buildDuration.inMilliseconds}ms '
          'raster ${t.rasterDuration.inMilliseconds}ms (#${slow.value})');
    }
  }
}
