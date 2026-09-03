# CLAUDE.md

Guidance for working in this repo. The README is the user-facing account; this is the
working one.

## What this is

A Flutter app (Flutter 3.47, Dart 3.13, Android API 24+) that runs on the Sonoff NSPanel Pro
86 - 480x480, PX30 with a Mali-G31, Android 8.1 - and renders the `custom:nspanel-*` cards
from the user's Lovelace dashboard natively, read from Home Assistant over the websocket.
The cards themselves, their options and their documentation live in the sibling repo
[NSPanel-cards](https://github.com/mennovanhout/NSPanel-cards); this app is the second
renderer of the same configs. A card option that exists in one renderer exists in the other,
or the README of the one that lacks it says so.

Beyond the cards: a screensaver (photo, wandering clock, proximity wake), a hand-rolled MQTT
client plus HA discovery so each panel is a device in HA (sensors, screensaver switch, page,
brightness, volume, a notify entity that speaks or plays sounds, an update entity), built-in
sounds, TTS through HA, self-update from GitHub Releases, start on boot.

## Rules that are not obvious from the code

- **The GPU budget is the reason this app exists.** Animation is opacity and transform,
  one-off, never continuous; no BackdropFilter except the screensaver's frosted clock. A
  laggy swipe is measured (`FrameWatch` logs every frame over 33 ms with build and raster
  time; `adb logcat -s flutter`), not felt. The first-swipe warm-up in `lib/ui/warmup.dart`
  exists because Skia compiles shaders on first paint - read its comment before touching it;
  four variants were measured and three do not work.
- **Never drive the user's real dashboard with blind adb taps or swipes.** The panel in this
  house runs the user's actual home; a stray tap has fired their Goodmorning script before.
  Safe touch targets: the bottom 26 px strip (page dots, no cards) at y=470, and the setup
  screen. Open setup with `adb shell am start -n nl.mennovanhout.nspanel/nl.mennovanhout.nspanel_app.MainActivity --ez setup true`.
- **Secrets never enter this repo or the transcript.** The HA token and the MQTT password
  live in the user's `setup.json`, which the user pushes; docs use placeholders. Never type
  either into a file, a command, or a log.
- **The signing key is fixed.** Android only installs an update over the same key, and the
  panels update themselves from GitHub Releases, so every APK that lands on a panel must be
  signed with the project keystore: `android/key.properties` (gitignored) on a dev machine,
  the `KEYSTORE_*` secrets on CI. A debug-signed build still installs, but the next release
  will not install over it. Changing the key means uninstall + reprovision on every panel.
- **Self-update is adb over localhost.** The NSPanel Pro ships with `ro.adb.secure=0` and adbd
  on 127.0.0.1:5555; `lib/update/adb.dart` speaks just enough of the protocol to run
  `pm install -r` on the APK in the app's own files dir (which the shell user can read).
  `BootReceiver` restarts the app on `MY_PACKAGE_REPLACED`. On a device that wants auth this
  fails clearly; it does not fall back to anything.
- **Card options are the cards repo's.** When adding an option here, add it to the cards repo
  (default literal, README row, editor schema) or document it as native-only in both READMEs.
  Native-only today: `sounds` and `haptics` on the alarm card.
- **Tests run against fakes, not the house.** `test/connection_test.dart` has `FakeHa` (the
  websocket, including a refused alarm code), `test/mqtt_client_test.dart` a fake broker,
  `test/adb_test.dart` a fake adbd. A widget test of a flow (see `alarm_widget_test.dart`)
  must use bounded pumps and must not `await conn.dispose()` under fake async.
- Sounds are synthesised by `tool/sounds.py`, which also writes `lib/audio/sounds.dart`;
  edit the script, never the outputs. A test holds the folder and the list equal.

## Panel facts (the one in this house)

adb at 10.234.50.233:5555; HA at 10.234.50.2:8123; Mosquitto at 10.234.50.2:1883. Proximity
sensor is graded (~53-58 at rest, ~10 Hz). No vibration motor, so touch feedback is the
SoundPool click. Home app is package `l.l`. WRITE_SETTINGS granted via appops. The Flutter
engine falls back from Impeller to Skia on this GPU on its own.

## Layout

```
lib/ha/        websocket client, entity state with a notifier per entity
lib/mqtt/      MQTT 3.1.1 client and the HA-discovery bridge (PanelBridge)
lib/update/    GitHub release check, adb client, self-install
lib/audio/     Announcer (TTS via HA, URLs, media-source, built-in sounds), sounds list
lib/config/    settings (+ setup.json), Lovelace -> pages, screensaver config
lib/ui/        pager, warm-up, screensaver, sheets, keypad, setup screen, theme
lib/cards/     one file per card, registry, PanelEnv
lib/util/      colour clamp, icons, formatting, proximity, Device (MethodChannel), FrameWatch
android/       MainActivity (sensors, brightness, volume, vibrate, tick), BootReceiver
tool/          sounds.py (generator), adb_probe.dart (adb client against a real device)
test/          everything above against fakes
```

## Releasing

Bump `version` in `pubspec.yaml` and `appVersion` in `lib/app.dart` together. Tag `vX.Y.Z`
and push the tag; the Release workflow signs with the secrets and attaches the arm64 APK.
The panels see it within six hours, or at once after a restart.
