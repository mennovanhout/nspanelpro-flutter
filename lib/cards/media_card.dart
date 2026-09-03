import 'package:flutter/material.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';

import '../config/dashboard.dart';
import '../ha/states.dart';
import '../ui/fill_card.dart';
import '../ui/sheet.dart';
import '../ui/theme.dart';
import '../util/color.dart';
import '../util/icons.dart';
import 'echo.dart';
import 'env.dart';

// media_player supported_features
const _pause = 1, _volumeSet = 4, _prev = 16, _next = 32, _turnOff = 256, _stop = 4096, _play = 16384;

/// Volume on the drag, transport on the face. Album art is a fixed 76px box
/// and Flutter's image cache is keyed by URL, so an unchanged picture is never
/// decoded twice - the guard the web card has to keep by hand.
class MediaCard extends StatefulWidget {
  const MediaCard({super.key, required this.config, required this.env});
  final CardConfig config;
  final PanelEnv env;

  @override
  State<MediaCard> createState() => _MediaCardState();
}

class _MediaCardState extends State<MediaCard> with EchoMixin {
  CardConfig get c => widget.config;
  String get entity => c.str('entity') ?? '';
  int get echoMs => c.intOr('echo_ms', 1500);
  List<CardConfig> get presets => c.maps('presets');

  Future<void> _call(String service, [Map<String, dynamic>? data]) =>
      widget.env.conn.callService('media_player', service, {'entity_id': entity, ...?data});

  bool _idle(HaState? s) => s == null || const {'off', 'idle', 'standby'}.contains(s.state);
  bool _playing(HaState? s) => s?.state == 'playing';

  double _entityValue(HaState? s) => (s?.numAttr('volume_level') ?? 0).clamp(0.0, 1.0);

  void _commit(double v, HaState? s) {
    // Without VOLUME_SET there is nothing to commit to; the fill still moved.
    if (s == null || !s.supports(_volumeSet)) return;
    _call('volume_set', {'volume_level': (v * 100).round() / 100});
  }

  void _applyPreset(CardConfig p) {
    if (p['source'] != null) _call('select_source', {'source': p['source']});
    if (p['media_content_id'] != null) {
      _call('play_media', {
        'media_content_id': p['media_content_id'],
        'media_content_type': p['media_content_type'] ?? 'music',
      });
    }
    final vol = (p['volume_pct'] as num?)?.toDouble();
    if (vol != null) {
      final v = (vol / 100).clamp(0.0, 1.0);
      _call('volume_set', {'volume_level': v});
      holdLocal(v, echoMs);
    }
  }

  ({String top, String sub}) _lines(HaState? s) {
    final device = c.titleOr(friendlyName(s, entity));
    if (s == null || s.isBroken) return (top: device, sub: 'Unavailable');
    if (_idle(s)) return (top: device, sub: s.state == 'off' ? 'Off' : 'Nothing playing');
    final title = s.attr<String>('media_title');
    final top = title ?? device;
    final sub = s.attr<String>('media_artist') ??
        s.attr<String>('media_series_title') ??
        s.attr<String>('media_channel') ??
        s.attr<String>('media_album_name') ??
        (title != null ? device : (s.state == 'paused' ? 'Paused' : 'Playing'));
    return (top: top, sub: s.state == 'paused' ? 'Paused · $sub' : sub);
  }

  IconData _defaultIcon(HaState? s) {
    switch (s?.deviceClass) {
      case 'tv':
        return MdiIcons.television;
      case 'receiver':
        return MdiIcons.speaker;
      default:
        return MdiIcons.music;
    }
  }

  void _openSheet(HaState? s) {
    final lines = _lines(s);
    showControlSheet(
      context,
      title: lines.top,
      state: lines.sub,
      value: display(_entityValue(s)),
      accent: parseHex(c.str('accent')) ?? Ns.violet,
      step: c.numOr('step', 5),
      actions: [
        if (s?.supports(_prev) ?? false)
          SheetAction(label: 'Previous', icon: MdiIcons.skipPrevious, close: false, run: () => _call('media_previous_track')),
        SheetAction(
          label: _playing(s) ? 'Pause' : 'Play',
          icon: _playing(s) ? MdiIcons.pause : MdiIcons.play,
          primary: true,
          close: false,
          run: () => _call('media_play_pause'),
        ),
        if (s?.supports(_next) ?? false)
          SheetAction(label: 'Next', icon: MdiIcons.skipNext, close: false, run: () => _call('media_next_track')),
        if (s?.supports(_stop) ?? false)
          SheetAction(label: 'Stop', icon: MdiIcons.stop, run: () => _call('media_stop'))
        else if (s?.supports(_turnOff) ?? false)
          SheetAction(label: 'Off', icon: MdiIcons.power, run: () => _call('turn_off')),
      ],
      onInput: (v) => holdLocal(v, echoMs),
      onCommit: (v) {
        holdLocal(v, echoMs);
        _commit(v, s);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<HaState?>(
      valueListenable: widget.env.states.listen(entity),
      builder: (context, s, _) {
        final broken = s == null || s.isBroken;
        final idle = _idle(s);
        final v = display(_entityValue(s));
        final pct = (v * 100).round();
        final lines = _lines(s);
        final art = c.boolOr('show_art', true) && !broken ? s.attr<String>('entity_picture') : null;
        final playing = _playing(s);

        Widget leading;
        if (art != null) {
          leading = ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.network(
              widget.env.settings.resolve(art),
              width: 76,
              height: 76,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => IconBox(_defaultIcon(s), on: !idle),
            ),
          );
        } else {
          leading = IconBox(mdi(c.str('icon') ?? s?.attr<String>('icon'), _defaultIcon(s)), on: !idle && !broken);
        }

        return FillCard(
          height: c.numOr('height', 200),
          accent: parseHex(c.str('accent')) ?? Ns.violet,
          fill: broken ? 0 : v,
          fillOpacity: broken || idle ? 0 : 1,
          on: !idle && !broken,
          broken: broken,
          opaqueChips: true,
          leading: leading,
          value: broken || idle || s.numAttr('volume_level') == null ? null : ValueText('$pct', unit: '%'),
          title: lines.top,
          sub: lines.sub,
          chips: c.boolOr('show_transport', true)
              ? [
                  ChipSpec(
                      label: '',
                      icon: MdiIcons.skipPrevious,
                      disabled: broken || !s.supports(_prev),
                      onTap: () => _call('media_previous_track')),
                  ChipSpec(
                      label: '',
                      icon: playing ? MdiIcons.pause : MdiIcons.play,
                      disabled: broken || !(s.supports(_play) || s.supports(_pause)),
                      onTap: () => _call('media_play_pause')),
                  ChipSpec(
                      label: '',
                      icon: MdiIcons.skipNext,
                      disabled: broken || !s.supports(_next),
                      onTap: () => _call('media_next_track')),
                ]
              : const [],
          chips2: c.boolOr('show_presets', true)
              ? [for (final p in presets.take(4)) ChipSpec(label: p.str('name') ?? '', onTap: () => _applyPreset(p))]
              : const [],
          onTap: () => _call('media_play_pause'),
          onLongPress: c.str('long_press') == 'none' ? null : () => _openSheet(s),
          onDragValue: (nv) {
            dragging = true;
            setLocal(nv);
          },
          onDragEnd: (nv) {
            dragging = false;
            holdLocal(nv, echoMs);
            _commit(nv, s);
          },
        );
      },
    );
  }
}
