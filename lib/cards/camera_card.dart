import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';

import '../config/dashboard.dart';
import '../ha/states.dart';
import '../ui/page_scope.dart';
import '../ui/theme.dart';
import 'env.dart';

/// One still from a camera: the entity, and the size it will be shown at.
typedef FrameFetch = Future<Uint8List?> Function(String entity, int width, int height);

/// A camera on the wall - a doorbell, a driveway.
///
/// Not video. A still from Home Assistant's camera proxy, asked for at the
/// card's own size and replaced about once a second, and only while the card
/// is on screen: its page is the one showing and the screensaver is not up
/// ([PageScope]). A camera on page three costs nothing while page one is
/// showing. That is what this hardware can afford - no decoder, no stream
/// held open - and it works for every camera HA has. Measured against a 4 MP
/// camera: the scaled still is ~150 kB and takes ~300 ms end to end, so one a
/// second leaves the panel idle most of the time. The next still is asked
/// for when the last one has arrived, so a slow network slows the pictures
/// down rather than piling requests up.
class CameraCard extends StatefulWidget {
  const CameraCard({super.key, required this.config, required this.env, this.fetch});
  final CardConfig config;
  final PanelEnv env;

  /// Where a still comes from; tests hand in their own.
  final FrameFetch? fetch;

  @override
  State<CameraCard> createState() => _CameraCardState();
}

class _CameraCardState extends State<CameraCard> {
  CardConfig get c => widget.config;
  String get _entity => c.str('entity') ?? '';

  PageScope? _scope;
  Listenable? _changes;
  Uint8List? _frame;
  Timer? _next;
  bool _fetching = false;
  int _fails = 0;
  bool _logged = false;
  Size _size = const Size(480, 300);

  static final _http = HttpClient()..connectionTimeout = const Duration(seconds: 6);

  bool get _active => _scope?.active ?? true;

  Duration get _interval =>
      Duration(milliseconds: (c.numOr('interval', 1).clamp(0.2, 3600) * 1000).round());

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final scope = PageScope.maybeOf(context);
    if (!identical(scope, _scope)) {
      _changes?.removeListener(_sync);
      _scope = scope;
      _changes = scope?.changes;
      _changes?.addListener(_sync);
    }
    _sync();
  }

  @override
  void dispose() {
    _changes?.removeListener(_sync);
    _next?.cancel();
    super.dispose();
  }

  /// On screen: fetch. Off screen: stop, and keep the last still so the page
  /// does not come back empty.
  void _sync() {
    if (!mounted) return;
    if (_active) {
      if (!_fetching && _next == null) _poll();
    } else {
      _next?.cancel();
      _next = null;
    }
  }

  Future<Uint8List?> _fromHa(String entity, int width, int height) async {
    final s = widget.env.settings;
    final uri = Uri.parse(s.resolve('/api/camera_proxy/$entity?width=$width&height=$height'));
    final req = await _http.getUrl(uri);
    // the long-lived token, not the entity's rotating one: nothing to refresh
    req.headers.set(HttpHeaders.authorizationHeader, 'Bearer ${s.token}');
    final res = await req.close().timeout(const Duration(seconds: 10));
    if (res.statusCode != 200) {
      await res.drain<void>();
      throw HttpException('HTTP ${res.statusCode}', uri: Uri.parse(uri.path));
    }
    final b = BytesBuilder(copy: false);
    await for (final chunk in res.timeout(const Duration(seconds: 10))) {
      b.add(chunk);
    }
    return b.takeBytes();
  }

  Future<void> _poll() async {
    if (!mounted || !_active || _fetching || _entity.isEmpty) return;
    _fetching = true;
    final started = DateTime.now();
    Uint8List? bytes;
    try {
      final dpr = MediaQuery.devicePixelRatioOf(context);
      bytes = await (widget.fetch ?? _fromHa)(
        _entity,
        (_size.width * dpr).round().clamp(160, 1920),
        (_size.height * dpr).round().clamp(120, 1920),
      );
    } catch (e) {
      bytes = null;
      // said once per run of failures, with the reason: a camera card that
      // stays empty and silent cannot be debugged from a hallway
      if (_fails == 0) debugPrint('camera: $_entity no still: $e');
    }
    _fetching = false;
    if (!mounted) return;
    if (bytes != null && bytes.isNotEmpty) {
      _fails = 0;
      if (!_logged) {
        _logged = true;
        debugPrint('camera: $_entity first still ${bytes.length ~/ 1024} kB in '
            '${DateTime.now().difference(started).inMilliseconds} ms');
      }
      setState(() => _frame = bytes);
    } else {
      _fails++;
      if (_fails == 3) setState(() {});
    }
    if (!_active) return;
    // a camera that is not answering is asked less often, not hammered
    final wait = _fails > 0 ? Duration(seconds: _fails.clamp(3, 15)) : _interval;
    _next?.cancel();
    _next = Timer(wait, () {
      _next = null;
      _poll();
    });
  }

  @override
  Widget build(BuildContext context) {
    final height = c.numOr('height', 300);
    return ValueListenableBuilder<HaState?>(
      valueListenable: widget.env.states.listen(_entity),
      builder: (context, s, _) {
        final gone = s == null || s.state == 'unavailable';
        final showName = c.boolOr('show_name', true);
        final contain = c.str('fit') == 'contain';
        final frame = _frame;
        return Container(
          height: height,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(color: Ns.surface, borderRadius: BorderRadius.circular(Ns.radius)),
          child: LayoutBuilder(builder: (context, box) {
            _size = Size(box.maxWidth.isFinite ? box.maxWidth : 480, height);
            return Stack(
              fit: StackFit.expand,
              children: [
                if (frame == null || _fails >= 3)
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(MdiIcons.cctv, size: 44, color: Ns.muted),
                      const SizedBox(height: 8),
                      Text(
                        gone
                            ? 'Camera unavailable'
                            : _fails >= 3
                                ? 'No picture'
                                : 'Loading…',
                        style: const TextStyle(color: Ns.muted, fontSize: 15),
                      ),
                    ],
                  )
                else
                  ColoredBox(
                    color: Colors.black,
                    child: Image.memory(
                      frame,
                      fit: contain ? BoxFit.contain : BoxFit.cover,
                      // the new still replaces the old one without a blank between
                      gaplessPlayback: true,
                      // decoded at the card's size, not the camera's
                      cacheWidth: (_size.width * MediaQuery.devicePixelRatioOf(context)).round(),
                      errorBuilder: (_, _, _) => const SizedBox(),
                    ),
                  ),
                if (showName && frame != null && _fails < 3) ...[
                  const Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 72,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: [Color(0x8C000000), Color(0x00000000)],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 20,
                    right: 20,
                    bottom: 14,
                    child: Text(
                      c.str('title') ?? c.str('name') ?? friendlyName(s, _entity),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        letterSpacing: -.2,
                        shadows: [Shadow(offset: Offset(0, 1), blurRadius: 4, color: Color(0x99000000))],
                      ),
                    ),
                  ),
                ],
              ],
            );
          }),
        );
      },
    );
  }
}
