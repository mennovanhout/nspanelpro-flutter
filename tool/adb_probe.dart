// Runs one shell command on a device through lib/update/adb.dart, against a
// real adbd, so the protocol is proven off the panel before the panel uses
// it on itself:  dart run tool/adb_probe.dart 10.234.50.233 "getprop ro.product.model"
import 'dart:io';

import 'package:nspanel_app/update/adb.dart';

Future<void> main(List<String> args) async {
  if (args.length < 2) {
    stderr.writeln('usage: adb_probe <host> <command>');
    exit(2);
  }
  final out = await AdbShell(host: args[0]).run(args[1], timeout: const Duration(seconds: 30));
  stdout.write(out);
}
