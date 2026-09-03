import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nspanel_app/audio/sounds.dart';

void main() {
  test('every built-in sound has its file, and every file is listed', () {
    final files = Directory('assets/sounds')
        .listSync()
        .map((f) => f.uri.pathSegments.last)
        .where((n) => n.endsWith('.wav'))
        .map((n) => n.substring(0, n.length - 4))
        .toSet();
    expect(files, equals(kSounds.keys.toSet()));
    expect(kSounds, contains('doorbell'));
    expect(kSounds, contains('alarm'));
  });
}
