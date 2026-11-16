// Renders the long-press page at the panel's 480x480 with the real fonts, for
// looking at a design without long-pressing a card on a panel in somebody's
// house. Not part of `flutter test` (it lives outside test/):
//
//   flutter test tool/shots/sheet_shots_test.dart --dart-define=SHOTS=<dir>
//
// PNGs land in <dir>. Fonts come from the Flutter SDK (Roboto, Material
// Icons) and the pub cache (Material Design Icons).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_design_icons_flutter/material_design_icons_flutter.dart';
import 'package:nspanel_app/ui/sheet.dart';
import 'package:nspanel_app/ui/theme.dart';

const _out = String.fromEnvironment('SHOTS');

Future<void> _font(String family, List<String> files) async {
  final loader = FontLoader(family);
  for (final f in files) {
    final bytes = File(f).readAsBytesSync();
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
  }
  await loader.load();
}

String get _flutterRoot {
  final env = Platform.environment['FLUTTER_ROOT'];
  if (env != null && env.isNotEmpty) return env;
  // the test runs in .../flutter/bin/cache/artifacts/engine/<host>/flutter_tester
  var d = File(Platform.resolvedExecutable).parent;
  while (!Directory('${d.path}/bin/cache/artifacts/material_fonts').existsSync()) {
    d = d.parent;
  }
  return d.path;
}

String get _pubCache =>
    Platform.environment['PUB_CACHE'] ??
    '${Platform.environment['LOCALAPPDATA']}/Pub/Cache';

Future<void> _fonts() async {
  final fonts = '$_flutterRoot/bin/cache/artifacts/material_fonts';
  await _font('Roboto', [
    for (final w in ['regular', 'medium', 'bold']) '$fonts/roboto-$w.ttf',
  ]);
  await _font('MaterialIcons', ['$fonts/materialicons-regular.otf']);
  final mdi = Directory('$_pubCache/hosted/pub.dev')
      .listSync()
      .whereType<Directory>()
      .firstWhere((d) => d.path.contains('material_design_icons_flutter-'));
  await _font('packages/material_design_icons_flutter/Material Design Icons', [
    '${mdi.path}/lib/fonts/materialdesignicons-webfont.ttf',
  ]);
}

Future<void> _shot(WidgetTester t, String name, Widget sheet) async {
  final key = GlobalKey();
  await t.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: Ns.theme(),
      home: RepaintBoundary(key: key, child: sheet),
    ),
  );
  await t.pump(const Duration(milliseconds: 300));
  expect(t.takeException(), isNull, reason: name);
  await t.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$_out/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
}

void main() {
  testWidgets('sheet shots', (t) async {
    if (_out.isEmpty) return;
    Directory(_out).createSync(recursive: true);
    t.view.physicalSize = const Size(480, 480);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.runAsync(_fonts);

    void noop() {}
    await _shot(
      t,
      'light',
      ControlSheet(
        title: 'Dining lights',
        state: 'On · 66%',
        value: .66,
        accent: Ns.amber,
        fromTop: false,
        step: 5,
        actions: [
          SheetAction(label: 'Night', icon: MdiIcons.weatherNight, run: noop),
          SheetAction(label: 'Dinner', icon: MdiIcons.silverwareForkKnife, run: noop),
          SheetAction(label: 'Full', icon: MdiIcons.lightbulbOnOutline, run: noop),
          SheetAction(label: 'Turn off', icon: MdiIcons.lightbulbOff, primary: true, run: noop),
        ],
      ),
    );
    await _shot(
      t,
      'cover',
      ControlSheet(
        title: 'Living room blinds',
        state: '40% open',
        value: .4,
        accent: Ns.sky,
        fromTop: true,
        step: 5,
        actions: [
          SheetAction(label: 'Open', icon: MdiIcons.arrowUp, run: noop),
          SheetAction(label: 'Stop', icon: MdiIcons.stop, primary: true, run: noop),
          SheetAction(label: 'Close', icon: MdiIcons.arrowDown, run: noop),
        ],
      ),
    );
    await _shot(
      t,
      'climate',
      ControlSheet(
        title: 'Thermostat',
        state: 'Now 20.5° · Heating',
        value: .55,
        accent: Ns.ember,
        fromTop: false,
        step: 2,
        format: (v) => '${(7 + v * 23).toStringAsFixed(1)}°',
        actions: [
          SheetAction(label: 'Off', icon: MdiIcons.power, run: noop),
          SheetAction(label: 'Heat', icon: MdiIcons.fire, primary: true, run: noop),
          SheetAction(label: 'Auto', icon: MdiIcons.thermostatAuto, run: noop),
        ],
      ),
    );
    await _shot(
      t,
      'switch',
      ControlSheet(
        title: 'Coffee machine',
        state: 'On',
        value: 0,
        accent: Ns.amber,
        fromTop: false,
        step: 5,
        showLevel: false,
        active: true,
        actions: [
          SheetAction(label: 'Turn off', icon: Icons.power_settings_new, primary: true, run: noop),
        ],
      ),
    );
    await _shot(
      t,
      'switch-off',
      ControlSheet(
        title: 'Coffee machine',
        state: 'Off',
        value: 0,
        accent: Ns.amber,
        fromTop: false,
        step: 5,
        showLevel: false,
        active: false,
        actions: [
          SheetAction(label: 'Turn on', icon: Icons.power_settings_new, primary: true, run: noop),
        ],
      ),
    );
    await _shot(
      t,
      'light-onoff',
      ControlSheet(
        title: 'Hallway',
        state: 'On',
        value: 0,
        accent: Ns.amber,
        fromTop: false,
        step: 5,
        showLevel: false,
        active: true,
        actions: [
          SheetAction(label: 'Night', icon: MdiIcons.weatherNight, run: noop),
          SheetAction(label: 'Dinner', icon: MdiIcons.silverwareForkKnife, run: noop),
          SheetAction(label: 'Full', icon: MdiIcons.lightbulbOnOutline, run: noop),
          SheetAction(label: 'Turn off', icon: MdiIcons.lightbulbOff, primary: true, run: noop),
        ],
      ),
    );
    await _shot(
      t,
      'media',
      ControlSheet(
        title: 'Kitchen speaker',
        state: 'Playing · Radio 2',
        value: .32,
        accent: Ns.violet,
        fromTop: false,
        step: 5,
        actions: [
          SheetAction(label: 'Previous', icon: MdiIcons.skipPrevious, run: noop),
          SheetAction(label: 'Pause', icon: MdiIcons.pause, primary: true, run: noop),
          SheetAction(label: 'Next', icon: MdiIcons.skipNext, run: noop),
        ],
      ),
    );
  });
}
