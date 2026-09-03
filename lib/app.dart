import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'cards/env.dart';
import 'cards/registry.dart';
import 'config/dashboard.dart';
import 'config/screensaver.dart';
import 'config/settings.dart';
import 'ha/connection.dart';
import 'ha/states.dart';
import 'ha/transport.dart';
import 'ui/pager.dart';
import 'ui/screensaver.dart';
import 'ui/setup_screen.dart';
import 'ui/theme.dart';
import 'util/proximity.dart';

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

  @override
  void initState() {
    super.initState();
    // A pushed setup.json wins over whatever is stored, then is gone.
    Settings.consumeSetupFile().then((_) => Settings.load()).then((s) => setState(() {
          _settings = s;
          _loaded = true;
        }));
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const Scaffold(body: SizedBox());
    if (_settings == null || _showSetup) {
      return SetupScreen(
        initial: _settings,
        message: _setupMessage,
        onSaved: (s) => setState(() {
          _settings = s;
          _showSetup = false;
          _setupMessage = null;
        }),
      );
    }
    return Dashboard(
      key: ValueKey('${_settings!.url}|${_settings!.token.hashCode}|${_settings!.dashboard}'),
      settings: _settings!,
      onReconfigure: (msg) => setState(() {
        _showSetup = true;
        _setupMessage = msg;
      }),
    );
  }
}

class Dashboard extends StatefulWidget {
  const Dashboard({super.key, required this.settings, required this.onReconfigure});
  final Settings settings;
  final ValueChanged<String?> onReconfigure;

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  late final HaStates _states = HaStates();
  late final HaConnection _conn;
  late final PanelEnv _env;
  List<PanelPage> _pages = const [];
  String? _error;
  Future<void> Function()? _unsubLovelace;
  final _taps = <DateTime>[];

  // screensaver: the dashboard card wins, then setup.json, then none
  ScreensaverConfig? _saverFromDashboard;
  bool _saving = false;
  Timer? _idle;
  StreamSubscription<double>? _prox;
  final _proxBaseline = <double>[];

  ScreensaverConfig? get _saver {
    if (_saverFromDashboard != null) return _saverFromDashboard;
    final m = widget.settings.screensaver;
    return m == null ? null : ScreensaverConfig.fromMap(m);
  }

  @override
  void initState() {
    super.initState();
    _conn = HaConnection(
      transportFactory: () => WebSocketTransport.connect(widget.settings.wsUri),
      token: widget.settings.token,
      states: _states,
    );
    _env = PanelEnv(states: _states, conn: _conn, settings: widget.settings);

    // Draw the last known dashboard immediately; HA's answer replaces it.
    final cached = widget.settings.cachedConfig;
    if (cached != null) {
      try {
        final cfg = (jsonDecode(cached) as Map).cast<String, dynamic>();
        _pages = pagesFromLovelace(cfg);
        _saverFromDashboard = ScreensaverConfig.findInLovelace(cfg);
      } catch (_) {
        // stale or unparsable cache; the fetch will fix it
      }
    }

    _conn.onReady = _loadConfig;
    _conn.status.addListener(_onStatus);
    _conn.start();
    _armIdle();
  }

  @override
  void dispose() {
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

  /// Triple-tap the top-left corner to get the setup screen back.
  void _cornerTap(TapDownDetails d) {
    if (d.globalPosition.dx > 60 || d.globalPosition.dy > 60) return;
    final now = DateTime.now();
    _taps.removeWhere((t) => now.difference(t).inMilliseconds > 900);
    _taps.add(now);
    if (_taps.length >= 3) {
      _taps.clear();
      widget.onReconfigure(null);
    }
  }

  // ---- idle / screensaver -------------------------------------------------

  void _armIdle() {
    _idle?.cancel();
    final s = _saver;
    if (s == null) return;
    _idle = Timer(Duration(seconds: s.afterSeconds.clamp(10, 86400)), _sleep);
  }

  void _touched() {
    if (_saving) return; // the overlay handles its own wake
    _armIdle();
  }

  void _sleep() {
    if (!mounted || _saver == null) return;
    setState(() => _saving = true);
    _watchProximity();
  }

  void _wake() {
    _prox?.cancel();
    _prox = null;
    _proxBaseline.clear();
    if (mounted) setState(() => _saving = false);
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
          _cornerTap(TapDownDetails(globalPosition: e.position));
        },
        onPointerMove: (_) => _touched(),
        onPointerUp: (_) => _touched(),
        child: Stack(
          children: [
            if (_pages.isNotEmpty)
              PanelPager(pages: [
                for (final p in _pages)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < p.cards.length; i++) ...[
                        if (i > 0) const SizedBox(height: Ns.gap),
                        buildCard(p.cards[i], _env),
                      ],
                    ],
                  ),
              ])
            else
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(_error ?? 'Connecting…',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _error == null ? Ns.muted : Ns.danger, fontSize: 15, height: 1.4)),
                ),
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
            if (_saving && _saver != null)
              Positioned.fill(child: Screensaver(config: _saver!, onWake: _wake)),
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
