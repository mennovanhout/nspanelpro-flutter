import 'dart:io';

/// The socket, abstracted just far enough that a test can stand in for
/// Home Assistant. The connection logic never touches dart:io directly.
abstract class HaTransport {
  Stream<String> get messages;
  void send(String data);
  Future<void> close();
}

class WebSocketTransport implements HaTransport {
  WebSocketTransport._(this._ws);

  final WebSocket _ws;

  static Future<WebSocketTransport> connect(Uri uri) async =>
      WebSocketTransport._(await WebSocket.connect(uri.toString()));

  @override
  Stream<String> get messages => _ws.map((d) => d.toString());

  @override
  void send(String data) => _ws.add(data);

  @override
  Future<void> close() => _ws.close();
}
