import 'package:flutter/foundation.dart';

import '../update/adb.dart';
import 'device.dart';

/// Turning the LCD backlight fully off, and back on.
///
/// Nothing an app may call turns a display off on Android 8.1 without being
/// a device owner, and brightness 0 through the settings still leaves this
/// panel's backlight at its floor of 10/255 - a faint glow all night. What
/// does turn it off is putting the device to sleep, and the NSPanel Pro's own
/// adb daemon lets the shell user inject the SLEEP key (measured: backlight
/// power 0, proximity readings still flowing, the app still in focus when it
/// comes back). Waking is the app's own wake lock; the WAKEUP key over adb is
/// the fallback if that ever does nothing.
class DisplayPower {
  DisplayPower({AdbShell? shell}) : _shell = shell ?? AdbShell();
  final AdbShell _shell;

  /// True when the display went to sleep.
  Future<bool> off() async {
    try {
      await Device.holdCpu(true);
      await _shell.run('input keyevent 223', timeout: const Duration(seconds: 10));
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final dark = !await Device.isInteractive();
      if (!dark) await Device.holdCpu(false);
      return dark;
    } catch (e) {
      debugPrint('display: could not sleep: $e');
      await Device.holdCpu(false);
      return false;
    }
  }

  Future<void> on() async {
    await Device.wakeScreen();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    if (!await Device.isInteractive()) {
      try {
        await _shell.run('input keyevent 224', timeout: const Duration(seconds: 10));
      } catch (e) {
        debugPrint('display: could not wake: $e');
      }
    }
    await Device.holdCpu(false);
  }
}
