import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Just enough of the adb wire protocol to run one shell command on the
/// panel's own adb daemon. The NSPanel Pro ships with adb listening on
/// 127.0.0.1:5555 and `ro.adb.secure=0`, so there is no key exchange: a
/// CNXN handshake, OPEN `shell:<cmd>`, collect the WRTEs, done. That is how
/// the app installs its own update with `pm install -r` and no one touching
/// the screen. On a device that does want authentication this fails
/// clearly rather than hanging.
const adbCnxn = 0x4e584e43;
const adbOpen = 0x4e45504f;
const adbOkay = 0x59414b4f;
const adbClse = 0x45534c43;
const adbWrte = 0x45545257;
const adbAuth = 0x48545541;

/// One 24-byte header plus payload, checksum and magic included.
Uint8List adbPacket(int cmd, int arg0, int arg1, List<int> data) {
  final b = ByteData(24);
  b.setUint32(0, cmd, Endian.little);
  b.setUint32(4, arg0, Endian.little);
  b.setUint32(8, arg1, Endian.little);
  b.setUint32(12, data.length, Endian.little);
  b.setUint32(16, data.fold<int>(0, (a, x) => a + x) & 0xffffffff, Endian.little);
  b.setUint32(20, (cmd ^ 0xffffffff) & 0xffffffff, Endian.little);
  return Uint8List.fromList([...b.buffer.asUint8List(), ...data]);
}

class AdbMessage {
  AdbMessage(this.cmd, this.arg0, this.arg1, this.data);
  final int cmd, arg0, arg1;
  final Uint8List data;
}

/// Reassembles packets from a byte stream.
class AdbParser {
  var _buf = Uint8List(0);

  List<AdbMessage> feed(List<int> bytes) {
    final b = Uint8List.fromList([..._buf, ...bytes]);
    final out = <AdbMessage>[];
    var off = 0;
    while (b.length - off >= 24) {
      final h = ByteData.sublistView(b, off, off + 24);
      final len = h.getUint32(12, Endian.little);
      if (b.length - off < 24 + len) break;
      out.add(AdbMessage(
        h.getUint32(0, Endian.little),
        h.getUint32(4, Endian.little),
        h.getUint32(8, Endian.little),
        Uint8List.sublistView(b, off + 24, off + 24 + len),
      ));
      off += 24 + len;
    }
    _buf = b.sublist(off);
    return out;
  }
}

typedef AdbConnect = Future<Socket> Function(String host, int port);

class AdbShell {
  AdbShell({this.host = '127.0.0.1', this.port = 5555, AdbConnect? connect})
      : _connect = connect ?? ((h, p) => Socket.connect(h, p, timeout: const Duration(seconds: 3)));

  final String host;
  final int port;
  final AdbConnect _connect;

  /// Runs `command` through adbd's `shell:` service and returns everything it
  /// printed. The v1 shell protocol carries no exit code; read the output.
  Future<String> run(String command, {Duration timeout = const Duration(minutes: 5)}) async {
    final socket = await _connect(host, port);
    final out = BytesBuilder();
    final done = Completer<String>();
    final parser = AdbParser();
    const localId = 1;

    void finish() {
      if (!done.isCompleted) done.complete(utf8.decode(out.takeBytes(), allowMalformed: true));
    }

    socket.listen((bytes) {
      for (final m in parser.feed(bytes)) {
        switch (m.cmd) {
          case adbCnxn:
            socket.add(adbPacket(adbOpen, localId, 0, utf8.encode('shell:$command\x00')));
          case adbAuth:
            if (!done.isCompleted) {
              done.completeError(
                  StateError('adb wants authentication (ro.adb.secure=1); self-update needs an unsecured adbd'));
            }
            socket.destroy();
          case adbWrte:
            out.add(m.data);
            socket.add(adbPacket(adbOkay, localId, m.arg0, const []));
          case adbClse:
            socket.add(adbPacket(adbClse, localId, m.arg0, const []));
            finish();
            // flush, not destroy: the acks and this CLSE are still in the buffer
            socket.flush().whenComplete(socket.destroy).ignore();
          default:
            break; // OKAY: nothing to do
        }
      }
    }, onError: (Object e) {
      if (!done.isCompleted) done.completeError(e);
    }, onDone: finish);

    socket.add(adbPacket(adbCnxn, 0x01000000, 256 * 1024, utf8.encode('host::\x00')));
    return done.future.timeout(timeout, onTimeout: () {
      socket.destroy();
      throw TimeoutException('adb shell "$command" timed out');
    });
  }
}
