import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nspanel_app/update/adb.dart';
import 'package:nspanel_app/update/updater.dart';

const release = {
  'tag_name': 'v0.3.0',
  'html_url': 'https://github.com/x/y/releases/tag/v0.3.0',
  'body': 'Alarm card, self-update.',
  'assets': [
    {'name': 'app-armeabi-v7a-release.apk', 'browser_download_url': 'https://dl/v7.apk', 'size': 1},
    {'name': 'app-arm64-v8a-release.apk', 'browser_download_url': 'https://dl/arm64.apk', 'size': 20000000},
  ],
};

void main() {
  test('versions compare numerically, v and suffixes ignored', () {
    expect(compareVersions('0.10.0', '0.9.1'), greaterThan(0));
    expect(compareVersions('v0.3.0', '0.3.0'), 0);
    expect(compareVersions('0.3.0+3', '0.3.0'), 0);
    expect(compareVersions('0.2.9', '0.3.0'), lessThan(0));
    expect(compareVersions('1.0', '1.0.0'), 0);
  });

  test('picks the arm64 APK off the release', () {
    final u = parseRelease(jsonEncode(release))!;
    expect(u.version, '0.3.0');
    expect(u.apkUrl, 'https://dl/arm64.apk');
    expect(u.notes, contains('Alarm'));
    expect(parseRelease(jsonEncode({'tag_name': 'v1', 'assets': []})), isNull);
  });

  test('check: newer means available, same does not, failure is reported', () async {
    final dir = await Directory.systemTemp.createTemp('upd');
    Updater make(String installed) => Updater(
          installed: installed,
          dir: dir,
          fetch: (_) async => jsonEncode(release),
          download: (_, _, _) async {},
        );
    final a = make('0.2.0');
    await a.check();
    expect(a.updateAvailable, isTrue);
    expect(a.status.value, 'Update 0.3.0 available');
    final b = make('0.3.0');
    await b.check();
    expect(b.updateAvailable, isFalse);
    expect(b.status.value, 'Up to date');
    final c = Updater(
      installed: '0.2.0',
      dir: dir,
      fetch: (_) => throw const SocketException('no route'),
      download: (_, _, _) async {},
    );
    await c.check();
    expect(c.latest.value, isNull);
    expect(c.status.value, startsWith('Update check failed'));
  });

  test('install: downloads, runs pm install over adb, reports progress and the result', () async {
    final dir = await Directory.systemTemp.createTemp('upd');
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final commands = <String>[];
    server.listen((s) {
      final parser = AdbParser();
      s.listen((bytes) {
        for (final m in parser.feed(bytes)) {
          if (m.cmd == adbCnxn) s.add(adbPacket(adbCnxn, 0x01000000, 4096, utf8.encode('device::\x00')));
          if (m.cmd == adbOpen) {
            commands.add(utf8.decode(m.data).replaceAll('\x00', ''));
            s.add(adbPacket(adbOkay, 3, m.arg0, const []));
            final ok = commands.last.contains('good');
            s.add(adbPacket(adbWrte, 3, m.arg0,
                utf8.encode(ok ? 'Success\n' : 'Failure [INSTALL_FAILED_UPDATE_INCOMPATIBLE]\n')));
            s.add(adbPacket(adbClse, 3, m.arg0, const []));
          }
        }
      });
    });
    final seen = <int>[];
    Updater make(Directory d) => Updater(
          installed: '0.2.0',
          dir: d,
          fetch: (_) async => jsonEncode(release),
          download: (url, to, onProgress) async {
            onProgress(50);
            onProgress(100);
            await to.writeAsString('apk bytes');
          },
          shell: AdbShell(host: '127.0.0.1', port: server.port),
        );
    final good = make(Directory('${dir.path}/good')..createSync());
    good.progress.addListener(() {
      if (good.progress.value != null) seen.add(good.progress.value!);
    });
    await good.check();
    expect(await good.install(), isTrue);
    expect(seen, [0, 50, 100]);
    expect(commands.single, startsWith('shell:pm install -r "'));
    expect(commands.single, endsWith('update.apk"'));
    expect(good.status.value, contains('Installed 0.3.0'));

    final bad = make(Directory('${dir.path}/bad')..createSync());
    await bad.check();
    expect(await bad.install(), isFalse);
    expect(bad.status.value, contains('INSTALL_FAILED_UPDATE_INCOMPATIBLE'));
    expect(File('${dir.path}/bad/update.apk').existsSync(), isFalse, reason: 'cleaned up');
    await server.close();
  });
}
