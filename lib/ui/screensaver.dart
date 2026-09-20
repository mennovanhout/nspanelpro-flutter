import 'dart:async';
import 'dart:math';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../config/screensaver.dart';
import 'theme.dart';

const _months = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December',
];
const _days = [
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
  'Sunday',
];

/// What the panel shows when nobody is using it: a photo, and a clock that
/// wanders so nothing burns in. Any touch wakes it; so does the proximity
/// sensor, handled by the caller.
///
/// The frosted clock is the one place this app uses a BackdropFilter, which
/// is exactly the thing the cards avoid on this GPU. It is affordable here
/// because nothing else is happening: the blur re-rasterises only while the
/// clock slides to a new spot once a minute, and on the minute tick.
class Screensaver extends StatefulWidget {
  const Screensaver({
    super.key,
    required this.config,
    required this.onWake,
    this.imageProvider,
  });
  final ScreensaverConfig config;
  final VoidCallback onWake;

  /// Where a photo URL becomes an image; tests hand in a MemoryImage.
  final ImageProvider Function(String url)? imageProvider;

  @override
  State<Screensaver> createState() => _ScreensaverState();
}

class _ScreensaverState extends State<Screensaver> {
  final _rng = Random();
  Timer? _clockTimer, _moveTimer, _imageTimer;
  DateTime _now = DateTime.now();
  Alignment _spot = Alignment.center;
  String? _imageUrl;
  int _imageSeq = 0;

  @override
  void initState() {
    super.initState();
    _armClock();
    _placeClock();
    if (widget.config.imageUrl != null) {
      _nextImage();
      _imageTimer = Timer.periodic(
        Duration(seconds: max(30, widget.config.imageRefreshSeconds)),
        (_) => _nextImage(),
      );
    }
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _moveTimer?.cancel();
    _imageTimer?.cancel();
    super.dispose();
  }

  void _armClock() {
    _now = DateTime.now();
    final wait = 60000 - (_now.millisecondsSinceEpoch % 60000) + 20;
    _clockTimer = Timer(Duration(milliseconds: wait), () {
      if (!mounted) return;
      setState(_armClock);
    });
  }

  /// A fixed clock sits where it was told; a wandering one starts somewhere
  /// random and moves every move_every seconds so nothing burns in.
  void _placeClock() {
    _moveTimer?.cancel();
    _moveTimer = null;
    final fixed = ScreensaverConfig.clockSpots[widget.config.clockPosition];
    if (fixed != null) {
      _spot = fixed;
      return;
    }
    _move();
    _moveTimer = Timer.periodic(
      Duration(seconds: max(10, widget.config.moveSeconds)),
      (_) => _move(),
    );
  }

  @override
  void didUpdateWidget(Screensaver old) {
    super.didUpdateWidget(old);
    // the dashboard was edited while the panel slept
    if (old.config.clockPosition != widget.config.clockPosition ||
        old.config.moveSeconds != widget.config.moveSeconds) {
      setState(_placeClock);
    }
  }

  void _move() {
    if (!mounted) return;
    setState(
      () => _spot = Alignment(
        _rng.nextDouble() * 1.6 - 0.8,
        _rng.nextDouble() * 1.6 - 0.8,
      ),
    );
  }

  /// The URL serves a different picture each time and says no-store, so the
  /// in-memory image cache is busted per fetch and the previous one evicted.
  void _nextImage() {
    final base = widget.config.imageUrl!;
    final sep = base.contains('?') ? '&' : '?';
    final old = _imageUrl;
    setState(
      () =>
          _imageUrl = '$base${sep}_ns=${DateTime.now().millisecondsSinceEpoch}',
    );
    _imageSeq++;
    if (old != null) {
      NetworkImage(old).evict();
      _provider(old).evict();
    }
  }

  /// Decode at the panel's size, not the photo's - a 4000px photo decoded
  /// whole is most of this device's spare memory. `fit` keeps the aspect
  /// ratio while bounding both sides; passing width and height without it
  /// squashes the picture to exactly that box, which is the bug this fixes.
  /// For `cover` the bound is 1.5x the screen, so any photo between 2:3 and
  /// 3:2 still has the screen's full height or width after decoding and is
  /// not scaled up on the way to the glass.
  ImageProvider _provider(String url) {
    if (widget.imageProvider != null) return widget.imageProvider!(url);
    final scale = widget.config.imageFit == 'cover' ? 1.5 : 1.0;
    final size =
        MediaQuery.sizeOf(context) *
        MediaQuery.devicePixelRatioOf(context) *
        scale;
    return ResizeImage(
      NetworkImage(url),
      width: size.width.round(),
      height: size.height.round(),
      policy: ResizeImagePolicy.fit,
      allowUpscaling: false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cfg = widget.config;
    final hh = _now.hour.toString().padLeft(2, '0');
    final mm = _now.minute.toString().padLeft(2, '0');

    return Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => widget.onWake(),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Colors.black),
          if (_imageUrl != null)
            // A new photo crossfades over the old one with a soft push - the
            // incoming settles from 1.04x, the outgoing drifts up to it.
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 1200),
              switchInCurve: Curves.easeOut,
              switchOutCurve: Curves.easeIn,
              transitionBuilder: (child, anim) => FadeTransition(
                opacity: anim,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 1.04, end: 1).animate(anim),
                  child: child,
                ),
              ),
              // The switcher lays its children out loose, and a loose Image
              // takes the decoded picture's own size - so `cover` was
              // covering a 480x430 box with black above and below. Expand it
              // to the screen first; the fit then works within that.
              child: SizedBox.expand(
                key: ValueKey(_imageSeq),
                child: Image(
                  image: _provider(_imageUrl!),
                  // the whole picture, its own shape, black around it - unless
                  // asked to fill the screen and crop
                  fit: cfg.imageFit == 'cover' ? BoxFit.cover : BoxFit.contain,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => const ColoredBox(color: Ns.ground),
                  // the first frame fades in rather than popping when the bytes land
                  frameBuilder: (_, child, frame, syncLoaded) => syncLoaded
                      ? child
                      : AnimatedOpacity(
                          opacity: frame == null ? 0 : 1,
                          duration: const Duration(milliseconds: 700),
                          curve: Curves.easeOut,
                          child: child,
                        ),
                ),
              ),
            ),
          if (cfg.clock)
            AnimatedAlign(
              alignment: _spot,
              duration: const Duration(milliseconds: 800),
              curve: Curves.easeInOutCubic,
              child: _FrostedClock(
                time: '$hh:$mm',
                date: cfg.clockDate
                    ? '${_days[_now.weekday - 1]} ${_now.day} ${_months[_now.month - 1]}'
                    : null,
                frost: cfg.frost,
                size: cfg.clockSize,
              ),
            ),
        ],
      ),
    );
  }
}

class _FrostedClock extends StatelessWidget {
  const _FrostedClock({
    required this.time,
    required this.date,
    required this.frost,
    required this.size,
  });
  final String time;
  final String? date;
  final bool frost;

  /// The digits' height; everything else is a proportion of it, so the
  /// 64 px default and a 120 px clock look like the same thing at two sizes.
  final double size;

  @override
  Widget build(BuildContext context) {
    final k = size / 64;
    final radius = 24 * k;
    final panel = Container(
      padding: EdgeInsets.fromLTRB(22 * k, 14 * k, 22 * k, 16 * k),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: frost ? .14 : .0),
        borderRadius: BorderRadius.circular(radius),
        border: frost
            ? Border.all(color: Colors.white.withValues(alpha: .22))
            : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            time,
            style: TextStyle(
              color: Colors.white,
              fontSize: size,
              fontWeight: FontWeight.w700,
              letterSpacing: -2.5 * k,
              height: 1,
              fontFeatures: Ns.tabular,
              shadows: const [
                Shadow(
                  offset: Offset(0, 1),
                  blurRadius: 6,
                  color: Color(0x80000000),
                ),
              ],
            ),
          ),
          if (date != null) SizedBox(height: 6 * k),
          if (date != null)
            Text(
              date!,
              style: TextStyle(
                color: Colors.white.withValues(alpha: .85),
                fontSize: 16 * k,
                fontWeight: FontWeight.w600,
                shadows: const [
                  Shadow(
                    offset: Offset(0, 1),
                    blurRadius: 4,
                    color: Color(0x80000000),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
    if (!frost) return panel;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: panel,
      ),
    );
  }
}
