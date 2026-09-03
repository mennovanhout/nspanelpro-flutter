import 'dart:async';
import 'dart:math';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../config/screensaver.dart';
import 'theme.dart';

const _months = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];
const _days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

/// What the panel shows when nobody is using it: a photo, and a clock that
/// wanders so nothing burns in. Any touch wakes it; so does the proximity
/// sensor, handled by the caller.
///
/// The frosted clock is the one place this app uses a BackdropFilter, which
/// is exactly the thing the cards avoid on this GPU. It is affordable here
/// because nothing else is happening: the blur re-rasterises only while the
/// clock slides to a new spot once a minute, and on the minute tick.
class Screensaver extends StatefulWidget {
  const Screensaver({super.key, required this.config, required this.onWake});
  final ScreensaverConfig config;
  final VoidCallback onWake;

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
    _move();
    _moveTimer = Timer.periodic(Duration(seconds: max(10, widget.config.moveSeconds)), (_) => _move());
    if (widget.config.imageUrl != null) {
      _nextImage();
      _imageTimer = Timer.periodic(
          Duration(seconds: max(30, widget.config.imageRefreshSeconds)), (_) => _nextImage());
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

  void _move() {
    if (!mounted) return;
    setState(() => _spot = Alignment(_rng.nextDouble() * 1.6 - 0.8, _rng.nextDouble() * 1.6 - 0.8));
  }

  /// The URL serves a different picture each time and says no-store, so the
  /// in-memory image cache is busted per fetch and the previous one evicted.
  void _nextImage() {
    final base = widget.config.imageUrl!;
    final sep = base.contains('?') ? '&' : '?';
    final old = _imageUrl;
    setState(() => _imageUrl = '$base${sep}_ns=${DateTime.now().millisecondsSinceEpoch}');
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
  ImageProvider _provider(String url) {
    final size = MediaQuery.sizeOf(context) * MediaQuery.devicePixelRatioOf(context);
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
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 900),
              child: Image(
                image: _provider(_imageUrl!),
                key: ValueKey(_imageSeq),
                // the whole picture, its own shape, black around it - unless
                // asked to fill the screen and crop
                fit: cfg.imageFit == 'cover' ? BoxFit.cover : BoxFit.contain,
                gaplessPlayback: true,
                errorBuilder: (_, _, _) => const ColoredBox(color: Ns.ground),
                loadingBuilder: (_, child, progress) => progress == null ? child : const SizedBox(),
              ),
            ),
          if (cfg.clock)
            AnimatedAlign(
              alignment: _spot,
              duration: const Duration(milliseconds: 800),
              curve: Curves.easeInOutCubic,
              child: _FrostedClock(
                time: '$hh:$mm',
                date: '${_days[_now.weekday - 1]} ${_now.day} ${_months[_now.month - 1]}',
                frost: cfg.frost,
              ),
            ),
        ],
      ),
    );
  }
}

class _FrostedClock extends StatelessWidget {
  const _FrostedClock({required this.time, required this.date, required this.frost});
  final String time, date;
  final bool frost;

  @override
  Widget build(BuildContext context) {
    final panel = Container(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: frost ? .14 : .0),
        borderRadius: BorderRadius.circular(24),
        border: frost ? Border.all(color: Colors.white.withValues(alpha: .22)) : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(time,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 64,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -2.5,
                  height: 1,
                  fontFeatures: Ns.tabular,
                  shadows: [Shadow(offset: Offset(0, 1), blurRadius: 6, color: Color(0x80000000))])),
          const SizedBox(height: 6),
          Text(date,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: .85),
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  shadows: const [Shadow(offset: Offset(0, 1), blurRadius: 4, color: Color(0x80000000))])),
        ],
      ),
    );
    if (!frost) return panel;
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: panel,
      ),
    );
  }
}
