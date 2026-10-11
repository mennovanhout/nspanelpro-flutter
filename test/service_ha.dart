import 'dart:async';
import 'dart:convert';

import 'connection_test.dart' show FakeHa;

/// Service acknowledgement is separate from state, as with a real appliance.
class ServiceHa extends FakeHa {
  ServiceHa(super.states) {
    super.messages.listen(_results.add);
  }
  final _results = StreamController<String>();
  bool refuses = false;
  bool delay = false;
  @override
  Stream<String> get messages => _results.stream;
  @override
  void send(String raw) {
    final msg = jsonDecode(raw) as Map<String, dynamic>;
    if (msg['type'] != 'call_service') {
      super.send(raw);
      return;
    }
    sent.add(msg);
    calls.add(
      '${msg['domain']}.${msg['service']} ${jsonEncode(msg['service_data'])}',
    );
    if (!delay) respond(msg['id'] as int);
  }

  void respond(int id) => _results.add(
    jsonEncode({
      'id': id,
      'type': 'result',
      'success': !refuses,
      if (refuses) 'error': {'code': 'test', 'message': 'Refused'},
      'result': null,
    }),
  );
  @override
  Future<void> close() async {
    await super.close();
    await _results.close();
  }
}
