import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nspanel_app/ha/transport.dart';

// A file of its own: testWidgets anywhere in a suite mocks HttpClient for all of it.
void main() {
  test('a socket that stops answering pings closes, so HA reconnects', () async {
    // Accepts the websocket handshake and then never says anything again:
    // what a panel sees when the access point loses it.
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final held = <Socket>[];
    server.listen((s) {
      held.add(s);
      final buffer = StringBuffer();
      s.listen((d) {
        if (buffer.toString().contains('\r\n\r\n')) return;
        buffer.write(latin1.decode(d));
        final req = buffer.toString();
        if (!req.contains('\r\n\r\n')) return;
        final key = RegExp(r'sec-websocket-key: (.*)\r\n', caseSensitive: false)
            .firstMatch(req)!
            .group(1)!
            .trim();
        final accept = base64.encode(
          sha1.convert(utf8.encode('${key}258EAFA5-E914-47DA-95CA-C5AB0DC85B11')).bytes,
        );
        s.write(
          'HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\n'
          'Connection: Upgrade\r\nSec-WebSocket-Accept: $accept\r\n\r\n',
        );
      });
    });
    final t = await WebSocketTransport.connect(
      Uri.parse('ws://127.0.0.1:${server.port}/'),
      ping: const Duration(milliseconds: 100),
    );
    final done = Completer<void>();
    t.messages.listen(null, onDone: done.complete, onError: (_) => done.complete());
    await done.future.timeout(const Duration(seconds: 3));
    for (final s in held) {
      s.destroy();
    }
    await server.close();
  });
}
