import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nspanel_app/update/adb.dart';

/// Enough of adbd to answer one shell command, on a real socket.
class FakeAdbd {
  FakeAdbd({this.secure = false, this.output = 'Success\n'});
  final bool secure;
  final String output;
  late ServerSocket server;
  final opened = <String>[];
  final okays = <(int, int)>[];
  /// Completes when the client's CLSE has arrived, i.e. after its acks.
  final closed = Completer<void>();
  int? clientMaxData;

  Future<void> start() async {
    server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((s) {
      final parser = AdbParser();
      const remote = 7;
      s.listen((bytes) {
        for (final m in parser.feed(bytes)) {
          switch (m.cmd) {
            case adbCnxn:
              clientMaxData = m.arg1;
              if (secure) {
                s.add(adbPacket(adbAuth, 1, 0, List.filled(20, 1)));
              } else {
                s.add(adbPacket(adbCnxn, 0x01000000, 4096, utf8.encode('device::ro.product.name=px30;\x00')));
              }
            case adbOpen:
              opened.add(utf8.decode(m.data).replaceAll('\x00', ''));
              s.add(adbPacket(adbOkay, remote, m.arg0, const []));
              // two writes, so reassembly and acking are both exercised
              final half = output.length ~/ 2;
              s.add(adbPacket(adbWrte, remote, m.arg0, utf8.encode(output.substring(0, half))));
              s.add(adbPacket(adbWrte, remote, m.arg0, utf8.encode(output.substring(half))));
              s.add(adbPacket(adbClse, remote, m.arg0, const []));
            case adbOkay:
              okays.add((m.arg0, m.arg1));
            case adbClse:
              s.destroy();
              if (!closed.isCompleted) closed.complete();
          }
        }
      });
    });
  }

  AdbShell shell() => AdbShell(host: '127.0.0.1', port: server.port);
}

void main() {
  test('packet: header fields, checksum, magic', () {
    final p = adbPacket(adbCnxn, 0x01000000, 4096, utf8.encode('host::\x00'));
    expect(p.length, 24 + 7);
    final m = AdbParser().feed(p).single;
    expect(m.cmd, adbCnxn);
    expect(m.arg0, 0x01000000);
    expect(m.arg1, 4096);
    expect(utf8.decode(m.data), 'host::\x00');
    // magic is the command inverted
    expect(p[20] | (p[21] << 8) | (p[22] << 16) | (p[23] << 24), (adbCnxn ^ 0xffffffff) & 0xffffffff);
  });

  test('parser reassembles across chunk boundaries', () {
    final a = adbPacket(adbWrte, 1, 2, utf8.encode('hello '));
    final b = adbPacket(adbWrte, 1, 2, utf8.encode('world'));
    final all = [...a, ...b];
    final parser = AdbParser();
    final got = <AdbMessage>[];
    for (var i = 0; i < all.length; i += 5) {
      got.addAll(parser.feed(all.sublist(i, (i + 5).clamp(0, all.length))));
    }
    expect(got.map((m) => utf8.decode(m.data)).join(), 'hello world');
  });

  test('runs a shell command and collects its output', () async {
    final d = FakeAdbd(output: 'Success\n');
    await d.start();
    final out = await d.shell().run('pm install -r "/sdcard/x.apk"');
    expect(out, 'Success\n');
    expect(d.opened, ['shell:pm install -r "/sdcard/x.apk"']);
    // the client is done when its acks are flushed, not when they are read
    await d.closed.future.timeout(const Duration(seconds: 5));
    expect(d.okays.length, 2, reason: 'each WRTE is acked');
    await d.server.close();
  });

  test('a device that wants authentication fails clearly', () async {
    final d = FakeAdbd(secure: true);
    await d.start();
    await expectLater(d.shell().run('id'), throwsA(isA<StateError>()));
    await d.server.close();
  });

  test('nobody listening fails, not hangs', () async {
    final shell = AdbShell(host: '127.0.0.1', port: 1);
    await expectLater(shell.run('id', timeout: const Duration(seconds: 5)), throwsA(anything));
  });
}
