import 'package:flutter_test/flutter_test.dart';
import 'package:nspanel_app/config/settings.dart';

void main() {
  group('the dashboard field takes whatever the address bar showed', () {
    final n = Settings.normaliseDashboard;

    test('a bare url_path', () => expect(n('dining-area'), 'dining-area'));
    test('with the view index HA appends', () => expect(n('/dining-area/0'), 'dining-area'));
    test('with a named view', () => expect(n('dining-area/kitchen'), 'dining-area'));
    test('the whole URL', () => expect(n('http://10.234.50.2:8123/dining-area/0'), 'dining-area'));
    test('whitespace and stray slashes', () => expect(n('  //dining-area/ '), 'dining-area'));
    test('empty means the default dashboard', () => expect(n(''), ''));
    test('the default dashboard by its own URL', () => expect(n('/lovelace/0'), ''));
  });

  test('wsUri is derived from the base URL', () {
    expect(Settings(url: 'http://10.0.0.2:8123', token: 't').wsUri.toString(),
        'ws://10.0.0.2:8123/api/websocket');
    expect(Settings(url: 'https://ha.example.com', token: 't').wsUri.toString(),
        'wss://ha.example.com/api/websocket');
    expect(Settings(url: '10.0.0.2:8123', token: 't').wsUri.toString(), 'ws://10.0.0.2:8123/api/websocket');
  });

  test('relative entity pictures resolve against HA', () {
    final s = Settings(url: 'http://10.0.0.2:8123', token: 't');
    expect(s.resolve('/api/media_player_proxy/x?token=1'), 'http://10.0.0.2:8123/api/media_player_proxy/x?token=1');
    expect(s.resolve('https://cdn.example.com/a.jpg'), 'https://cdn.example.com/a.jpg');
  });
}
