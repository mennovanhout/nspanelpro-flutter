import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'audio/announcer.dart';
import 'cards/env.dart';
import 'cards/registry.dart';
import 'mqtt/bridge.dart';
import 'mqtt/client.dart';
import 'util/device.dart';
import 'util/frames.dart';
import 'config/dashboard.dart';
import 'config/screensaver.dart';
import 'config/settings.dart';
import 'ha/connection.dart';
import 'ha/states.dart';
import 'ha/transport.dart';
import 'ui/motion.dart';
import 'ui/pager.dart';
import 'ui/screensaver.dart';
import 'ui/setup_screen.dart';
import 'ui/theme.dart';
import 'ui/warmup.dart';
import 'update/updater.dart';
import 'util/proximity.dart';

/// Reported to Home Assistant as the device's sw_version. Keep in step with
/// pubspec.yaml.
const appVersion = '0.3.0';

class NsPanelApp extends StatelessWidget {
  const NsPanelApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'NSPanel',
        debugShowCheckedModeBanner: false,
        theme: Ns.theme(),
        home: const Shell(),
      );
}

/// Setup screen until there is a token; the dashboard after.
class Shell extends StatefulWidget {
  const Shell({super.key});

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  Settings? _settings;
  bool _loaded = false;
  bool _showSetup = false;
  String? _setupMessage;
  Updater? _updater;

  @override
  void initState() {
    super.initState();
    // A pushed setup.json wins over whatever is stored, then is gone. An
    // `--ez setup true` launch extra opens the setup screen, for adb.
    Settings.consumeSetupFile()
        .then((_) => Settings.load())
        .then((s) async => (s, await Device.wantsSetup(), await getExternalStorageDirectory()))
        .then((r) => setState(() {
              _settings = r.$1;
              _showSetup = r.$2;
              _loaded = true;
              // the app's own files dir: where setup.json goes, and where the
              // update APK lands (the panel's shell user can read it there)
              _updater = Updater(installed: appVersion, dir: r.$3 ?? Directory.systemTemp);
            }));
  }

  @override
  Widget build(BuildContext context) {
    Widget child;
    if (!_loaded) {
      child = const Scaffold(key: ValueKey('blank'), body: SizedBox());
    } else if (_settings == null || _showSetup) {
      child = SetupScreen(
        key: const ValueKey('setup'),
        initial: _settings,
        message: _setupMessage,
        updater: _updater,
        onSaved: (s) => setState(() {
          _settings = s;
          _showSetup = false;
          _setupMessage = null;
        }),
      );
    } else {
      child = Dashboard(
        key: ValueKey('dash|${_settings!.url}|${_settings!.token.hashCode}|${_settings!.dashboard}'),
        settings: _settings!,
        updater: _updater!,
        onReconfigure: (msg) => setState(() {
          _showSetup = true;
          _setupMessage = msg;
        }),
      );
    }
    // setup <-> dashboard, and the blank first frame -> whichever comes: a crossfade
    return AnimatedSwitcher(duration: const Duration(milliseconds: 450), child: child);
  }
}

class Dashboard extends StatefulWidget {
  const Dashboard({super.key, required this.settings, required this.updater, required this.onReconfigure});
  final Settings settings;
  final Updater updater;
  final ValueChanged<String?> onReconfigure;

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  final _frames = FrameWatch();
  int _shown = 0; // the page on screen; only it animates its cards in
  bool _warm = false;
  Timer? _warmTimer;
  late final HaStates _states = HaStates();
  late final HaConnection _conn;
  late final PanelEnv _env;
  List<PanelPage> _pages = const [];
  String? _error;
  Future<void> Function()? _unsubLovelace;

  // screensaver: the dashboard card wins, then setup.json, then none
  ScreensaverConfig? _saverFromDashboard;
  bool _saving = false;
  Timer? _idle;
  StreamSubscription<double>? _prox;
  final _proxBaseline = <double>[];

  ScreensaverConfig? get _saver {
    if (_forcedSaver != null) return _forcedSaver;
    if (_saverFromDashboard != null) return _saverFromDashboard;
    final m = widget.settings.screensaver;
    return m == null ? null : ScreensaverConfig.fromMap(m);
  }

  @override
  void initState() {
    super.initState();
    _frames.start();
    Device.hasVibrator().then((v) {
      _hasVibrator = v;
      debugPrint('touch: vibrator ${v ? 'present' : 'absent'}, sound ${widget.settings.touchSound ? 'on' : 'off'}');
    });
    _conn = HaConnection(
      transportFactory: () => WebSocketTransport.connect(widget.settings.wsUri),
      token: widget.settings.token,
      states: _states,
    );
    _env = PanelEnv(states: _states, conn: _conn, settings: widget.settings, play: (ref) => _announcer.play(ref));

    // Draw the last known dashboard immediately; HA's answer replaces it.
    final cached = widget.settings.cachedConfig;
    if (cached != null) {
      try {
        final cfg = (jsonDecode(cached) as Map).cast<String, dynamic>();
        _pages = pagesFromLovelace(cfg);
        _scheduleWarmup();
        _saverFromDashboard = ScreensaverConfig.findInLovelace(cfg);
      } catch (_) {
        // stale or unparsable cache; the fetch will fix it
      }
    }

    _conn.onReady = _loadConfig;
    _conn.status.addListener(_onStatus);
    _conn.start();
    _armIdle();
    _announcer = Announcer(settings: widget.settings, conn: _conn);
    // host and user only - the password never goes anywhere near a log
    debugPrint(widget.settings.hasMqtt
        ? 'mqtt: configured for ${widget.settings.mqttHost}:${widget.settings.mqttPort} '
            'as ${widget.settings.mqttUser ?? '(no user)'}'
        : 'mqtt: not configured (no mqtt block in settings)');
    if (widget.settings.hasMqtt) _startBridge();
  }

  // ---- the panel as a Home Assistant device, over MQTT ---------------------

  late final Announcer _announcer;
  PanelBridge? _bridge;
  MqttClient? _mqtt;
  final _pageJump = ValueNotifier<int>(0);
  StreamSubscription<double>? _proxAlways, _lightSub;
  Timer? _diag;
  Timer? _updateCheck;

  Future<void> _startBridge() async {
    final s = widget.settings;
    final id = await Device.androidId();
    if (!mounted) return;
    final base = 'nspanel/$id';
    _mqtt = MqttClient(
      transportFactory: () => SocketMqttTransport.connect(s.mqttHost, s.mqttPort),
      clientId: 'nspanel-$id',
      username: s.mqttUser,
      password: s.mqttPass,
      willTopic: '$base/availability',
      willMessage: 'offline',
    );
    final b = PanelBridge(
      mqtt: _mqtt!,
      deviceId: id,
      name: s.name,
      version: appVersion,
      presenceDelta: _saver?.proximityDelta ?? 12,
      onBrightness: (v) async {
        if (await Device.setBrightness(v)) _bridge?.brightness(v);
      },
      onVolume: (v) async {
        if (await Device.setVolume(v)) _bridge?.volume(v);
      },
      onScreensaver: (on) => on ? _sleep(force: true) : _wake(),
      onPage: (i) => _pageJump.value = i,
      onSay: _announcer.say,
      onPlay: _announcer.play,
      onStop: _announcer.stop,
      onWake: _wake,
      onInstall: () => widget.updater.install(),
    );
    _bridge = b;
    // the update entity follows the updater; the first check is half a
    // minute after start so it never competes with the dashboard loading
    for (final n in [widget.updater.latest, widget.updater.progress, widget.updater.status]) {
      n.addListener(_publishUpdate);
    }
    _updateCheck?.cancel();
    _updateCheck = Timer(const Duration(seconds: 30), () {
      widget.updater.check();
      _updateCheck = Timer.periodic(const Duration(hours: 6), (_) => widget.updater.check());
    });
    _mqtt!.connected.addListener(() {
      debugPrint('mqtt: ${_mqtt!.connected.value ? 'connected, device announced' : 'disconnected'}');
    });
    b.start();

    // sensors, continuously, rate-limited in the bridge
    _proxAlways = Proximity.stream.listen(b.proximity, onError: (_) {});
    _lightSub = Device.light.listen(b.illuminance, onError: (_) {});
    b.screensaver(_saving);
    b.page(0);
    _publishDiagnostics();
    _diag = Timer.periodic(const Duration(seconds: 60), (_) => _publishDiagnostics());
  }

  /// A second after the pages appear - the cards have risen into place by
  /// then - every page is painted once, hidden, so the first swipe does not
  /// pay for shader compilation. See [Warmup].
  void _scheduleWarmup() {
    _warmTimer?.cancel();
    if (_pages.length < 2) return;
    _warmTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _warm = true);
    });
  }

  Widget _page(PanelPage p, {required bool animate}) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < p.cards.length; i++) ...[
            if (i > 0) const SizedBox(height: Ns.gap),
            // cards rise into place, staggered, when a page first shows
            Enter(index: i, animate: animate, child: buildCard(p.cards[i], _env)),
          ],
        ],
      );

  void _publishUpdate() {
    final u = widget.updater;
    final l = u.latest.value;
    _bridge?.updateState(
      installed: u.installed,
      latest: l?.version,
      url: l?.url,
      notes: l?.notes,
      inProgress: u.progress.value != null,
      percent: u.progress.value,
    );
    if (u.status.value.isNotEmpty) debugPrint('update: ${u.status.value}');
  }

  Future<void> _publishDiagnostics() async {
    final b = _bridge;
    if (b == null) return;
    b.slowFrames(_frames.slow.value);
    _publishUpdate();
    final rssi = await Device.wifiRssi();
    if (rssi != null) b.rssi(rssi);
    final t = await Device.socTemperature();
    if (t != null) b.temperature(t);
    final br = await Device.brightness();
    if (br != null && br >= 0) b.brightness(br);
    final vol = await Device.volume();
    if (vol != null) b.volume(vol);
  }

  @override
  void dispose() {
    _hold?.cancel();
    _diag?.cancel();
    _warmTimer?.cancel();
    _updateCheck?.cancel();
    for (final n in [widget.updater.latest, widget.updater.progress, widget.updater.status]) {
      n.removeListener(_publishUpdate);
    }
    _proxAlways?.cancel();
    _lightSub?.cancel();
    _mqtt?.dispose();
    _announcer.dispose();
    _pageJump.dispose();
    _idle?.cancel();
    _prox?.cancel();
    _conn.status.removeListener(_onStatus);
    _unsubLovelace?.call();
    _conn.dispose();
    super.dispose();
  }

  void _onStatus() {
    if (_conn.status.value == HaStatus.authFailed) {
      widget.onReconfigure('That token was rejected. Paste a new one.');
    }
  }

  Future<void> _loadConfig() async {
    final path = widget.settings.dashboardPath;
    try {
      final cfg = await _conn.fetchLovelace(path);
      final pages = pagesFromLovelace(cfg);
      if (!mounted) return;
      setState(() {
        _pages = pages;
        _scheduleWarmup();
        _saverFromDashboard = ScreensaverConfig.findInLovelace(cfg);
        _error = pages.isEmpty
            ? 'The dashboard "${path.isEmpty ? 'default' : path}" has no cards this app can '
                'draw. It needs custom:nspanel-* cards.'
            : null;
      });
      await widget.settings.cacheConfig(jsonEncode(cfg));
      // Edit the dashboard in HA and the panel follows.
      _unsubLovelace ??= await _conn.subscribe(
        {'type': 'subscribe_events', 'event_type': 'lovelace_updated'},
        (_) => _loadConfig(),
      );
    } catch (e) {
      final msg = await _explain(path, e);
      if (!mounted) return;
      setState(() => _error = msg);
    }
  }

  /// "Not found" from lovelace/config means one of two different things, and
  /// the person standing at the panel cannot tell which. Ask HA which
  /// dashboards exist and say so.
  Future<String> _explain(String path, Object e) async {
    final name = path.isEmpty ? 'the default dashboard' : '"$path"';
    List<Map<String, dynamic>> list = const [];
    try {
      final r = await _conn.send({'type': 'lovelace/dashboards/list'});
      list = (r as List).whereType<Map>().map((m) => m.cast<String, dynamic>()).toList();
    } catch (_) {
      return 'Could not load $name: $e';
    }
    final paths = list.map((d) => d['url_path']?.toString()).whereType<String>().toList();
    if (path.isNotEmpty && paths.contains(path)) {
      return 'Dashboard "$path" exists but has no saved config yet - it is still the '
          'auto-generated one. In Home Assistant open it, then ⋮ → Edit dashboard → '
          'Take control, add the nspanel cards and save. This panel reloads on its own.';
    }
    final known = ['(empty) for the default dashboard', ...paths];
    return 'Could not load $name: $e\n\nDashboards on this Home Assistant:\n'
        '${known.map((p) => '  • $p').join('\n')}\n\n'
        'Triple-tap the top-left corner to change it.';
  }

  /// Two fingers held still for a moment opens the setup screen.
  ///
  /// It used to be a triple-tap in a corner, and the corner is always on top
  /// of somebody's first card - three taps on a "Goodmorning" button with
  /// confirm on is one armed and one fired. A gesture the cards never use
  /// cannot be mistaken for one they do.
  final _fingers = <int, Offset>{};
  Timer? _hold;

  void _pointerDown(PointerDownEvent e) {
    _fingers[e.pointer] = e.position;
    if (_fingers.length == 2) {
      _hold?.cancel();
      _hold = Timer(const Duration(milliseconds: 1200), () {
        if (_fingers.length == 2 && mounted) widget.onReconfigure(null);
      });
    } else {
      _hold?.cancel();
    }
  }

  void _pointerMove(PointerMoveEvent e) {
    final start = _fingers[e.pointer];
    if (start != null && (e.position - start).distance > 24) _hold?.cancel();
  }

  void _pointerUp(int pointer) {
    _fingers.remove(pointer);
    _hold?.cancel();
  }

  // ---- idle / screensaver -------------------------------------------------

  void _armIdle() {
    _idle?.cancel();
    final s = _saver;
    if (s == null) return;
    _idle = Timer(Duration(seconds: s.afterSeconds.clamp(10, 86400)), _sleep);
  }

  void _touched() {
    _bridge?.touched();
    if (_saving) return; // the overlay handles its own wake
    _armIdle();
  }

  /// Every touch-down clicks and, when the panel has a motor, buzzes -
  /// fired here, at the touch, not when a card decides what it meant, so
  /// the feedback is within the same frame as the finger.
  void _feedback() {
    final s = widget.settings;
    if (s.touchSound) {
      Device.tick(s.touchVolume).then((ok) {
        if (_tickLogged < 2) {
          _tickLogged++;
          debugPrint('touch: click sound ${ok ? 'playing' : 'not loaded yet'}');
        }
      });
    }
    if (s.touchVibrate && _hasVibrator) Device.vibrate(12);
  }

  int _tickLogged = 0;

  bool _hasVibrator = false;

  // _saving is the target state; _saverMounted keeps the overlay in the tree
  // while it fades out, so the dashboard is touchable the moment it starts.
  bool _saverMounted = false;

  /// `force` is Home Assistant switching the screensaver on: it works even
  /// with none configured, as a clock on black.
  ScreensaverConfig? _forcedSaver;

  void _sleep({bool force = false}) {
    if (!mounted) return;
    if (_saver == null) {
      if (!force) return;
      _forcedSaver = const ScreensaverConfig();
    }
    setState(() {
      _saving = true;
      _saverMounted = true;
    });
    _bridge?.screensaver(true);
    _watchProximity();
  }

  void _wake() {
    _prox?.cancel();
    _prox = null;
    _proxBaseline.clear();
    if (mounted && _saving) setState(() => _saving = false);
    _forcedSaver = null;
    _bridge?.screensaver(false);
    _armIdle();
  }

  /// Wake on approach. The sensor reports a graded value, and which way it
  /// moves when someone walks up depends on the unit, so the first two
  /// seconds of readings set the resting level and a departure from it by
  /// `proximity_delta` wakes the panel. Absolute below/above overrides exist
  /// for anyone who has watched the readout and knows.
  void _watchProximity() {
    final s = _saver;
    if (s == null || !s.wakeOnProximity) return;
    _proxBaseline.clear();
    _prox = Proximity.stream.listen((v) {
      if (s.proximityBelow != null && v < s.proximityBelow!) return _wake();
      if (s.proximityAbove != null && v > s.proximityAbove!) return _wake();
      if (s.proximityBelow != null || s.proximityAbove != null) return;
      if (_proxBaseline.length < 20) {
        _proxBaseline.add(v);
        return;
      }
      final sorted = [..._proxBaseline]..sort();
      final median = sorted[sorted.length ~/ 2];
      if ((v - median).abs() > s.proximityDelta) _wake();
    }, onError: (_) {
      // no sensor on this device; touch still wakes it
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Listener(
        onPointerDown: (e) {
          _touched();
          _feedback();
          _pointerDown(e);
        },
        onPointerMove: (e) {
          _touched();
          _pointerMove(e);
        },
        onPointerUp: (e) {
          _touched();
          _pointerUp(e.pointer);
        },
        onPointerCancel: (e) => _pointerUp(e.pointer),
        child: Stack(
          children: [
            if (_pages.isNotEmpty)
              PanelPager(
                jump: _pageJump,
                onPage: (i) {
                  _shown = i;
                  _bridge?.page(i);
                },
                pages: [
                  for (var i = 0; i < _pages.length; i++) _page(_pages[i], animate: i == _shown),
                ],
              )
            else
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_error ?? 'Connecting…',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _error == null ? Ns.muted : Ns.danger, fontSize: 15, height: 1.4)),
                ),
              ),
            if (_warm)
              Warmup(
                onDone: () => setState(() => _warm = false),
                children: [for (final p in _pages) _page(p, animate: false)],
              ),
            if (_error != null && _pages.isNotEmpty)
              Positioned(
                left: 12,
                right: 12,
                bottom: 30,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Ns.surface, borderRadius: BorderRadius.circular(12)),
                  child: Text(_error!, style: const TextStyle(color: Ns.danger, fontSize: 12)),
                ),
              ),
            if (_saverMounted && _saver != null)
              Positioned.fill(
                child: Reveal(
                  visible: _saving,
                  onHidden: () {
                    if (mounted) setState(() => _saverMounted = false);
                  },
                  child: Screensaver(config: _saver!, onWake: _wake),
                ),
              ),
            Positioned(
              top: 6,
              right: 8,
              child: ValueListenableBuilder<HaStatus>(
                valueListenable: _conn.status,
                builder: (_, st, _) => AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: st == HaStatus.online ? 0 : 1,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: st == HaStatus.connecting ? Ns.gold : Ns.danger,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
