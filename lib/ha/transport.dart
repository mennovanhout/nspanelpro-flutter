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

  /// A socket that dies without a goodbye - Wi-Fi roaming, an AP restart -
  /// looks exactly like a quiet one, and a panel would show old states until
  /// TCP gave up, which can take many minutes. dart:io closes the socket when
  /// a ping goes unanswered, and the close is what starts the reconnect.
  static Future<WebSocketTransport> connect(
    Uri uri, {
    Duration ping = const Duration(seconds: 20),
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final ws = await WebSocket.connect(
      uri.toString(),
      customClient: HttpClient()..connectionTimeout = timeout,
    );
    ws.pingInterval = ping;
    return WebSocketTransport._(ws);
  }

  @override
  Stream<String> get messages => _ws.map((d) => d.toString());

  @override
  void send(String data) => _ws.add(data);

  @override
  Future<void> close() => _ws.close();
}
