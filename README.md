# NSPanel app

Home Assistant on the Sonoff NSPanel Pro 86, natively.

A Flutter app that renders the `custom:nspanel-*` cards from
[NSPanel-cards](https://github.com/mennovanhout/NSPanel-cards) without a browser in the way.
The web cards are careful with the panel's frame budget, but they are passengers: open a
dashboard in the companion app and the WebView is also running the whole HA frontend, and on a
PX30 that is most of the cost. This draws straight to the GPU instead.

**New here?** [TUTORIAL.md](TUTORIAL.md) walks from an empty Home Assistant to a working
panel, and has the short recipe for adding the second, third and fourth one.

## One config, two renderers

The app **reads your Lovelace dashboard from Home Assistant** over the websocket and renders
the `nspanel-*` cards in it. You keep configuring in HA - YAML or the GUI editor, which keeps
working - and the panel follows; edit the dashboard and it reloads on its own. The same
config still works in a browser with the web cards, on a phone or a tablet.

The layout it expects is the one the cards' README recommends: a panel view holding a swipe
card whose children are the pages. A view with no swipe card becomes one page. Cards it does
not know are shown as a marked gap rather than dropped, so you can see what a dashboard is
asking for that this app cannot do.

```yaml
views:
  - type: panel
    cards:
      - type: custom:simple-swipe-card
        cards:
          - type: vertical-stack
            cards:
              - type: custom:nspanel-light-card
                entity: light.dining_lights
                title: Dining table
                height: 260
              - type: custom:nspanel-light-card
                entity: light.lounge_lamp
                title: Lounge lamp
                height: 184
                show_presets: false
          - type: vertical-stack
            cards:
              - type: custom:nspanel-climate-card
                entity: climate.living_room
                height: 300
              - type: custom:nspanel-sensors-card
                height: 144
                entities: [sensor.outside_temp, sensor.outside_hum, sensor.wind]
```

Every card and option is documented in the cards repo's README; this app takes the same ones.
Heights are in logical pixels, which on the panel at stock density are the panel's pixels.

The alarm card is the one with a keypad: when the alarm wants a code, arming or disarming
opens one full screen, and a refused code says so and clears. It rings the built-in
`armed`, `disarmed` and `alarm` sounds as the state changes (`sounds: false` to stop it).

`vertical-stack`, `horizontal-stack` and `grid` are rendered as layout, nested as deep as you
like. In a horizontal stack every child is an equal column and keeps its own `height`, so give
them the same one. `grid` takes `columns`; `square` is ignored.

## Screensaver

After a period without a touch the panel shows a photo and a clock that wanders so nothing
burns in. Any touch wakes it, and so does someone walking up to it - the NSPanel Pro has a
real proximity sensor and the app reads it.

Configure it with a card anywhere in the dashboard. It renders nothing (the web bundle ships a
matching empty card, so Lovelace does not complain either); the app reads it and drops it:

```yaml
- type: custom:nspanel-screensaver
  after: 300                  # seconds without a touch; default 300
  image_url: https://fastly.picsum.photos/id/650/440/440.jpg
  image_refresh: 600          # seconds between new pictures while idle; default 600
  image_fit: contain          # the whole picture, its own shape, black around it (default);
                              # `cover` fills the screen and crops
  clock: true                 # default true
  move_every: 60              # seconds between clock positions; default 60
  frost: true                 # frosted panel behind the clock; default true
  wake_on_proximity: true     # default true
  proximity_delta: 12         # how far the reading must move from its resting level
```

The same keys also go under `screensaver` in a pushed `setup.json`, which is the right place
when different panels want different pictures; the dashboard card wins when both exist.

**Proximity.** The sensor reports a graded value at ~10 Hz, not near/far, and which way it moves
when someone approaches depends on the unit. Its resting level depends on the wall it hangs on
(58 on one wall in this house, 410 on another), its noise grows with that level, and the
display's own light reaches it, so the level shifts when the dark photo replaces the bright
dashboard. So the app ignores the first two seconds of the screensaver, takes the next two as
the resting level, and wakes when two readings in a row depart from it by `proximity_delta`
or 15% of the resting level, whichever is more. The setup screen (two-finger hold) shows the live value; watch
it as you walk up, and if you would rather be explicit, `proximity_below: 30` or
`proximity_above: 90` wake on an absolute threshold instead.

**The frosted clock is the one `BackdropFilter` in this app**, the exact thing the cards avoid
on this GPU. It is affordable here because nothing else is happening: the blur re-rasterises
only while the clock slides once a minute. `frost: false` if it ever stutters. Pictures are
decoded at the panel's size, not the photo's, and the previous one is evicted before the next
is fetched, so a stream of large photos does not grow memory.

## Install

Every push builds an APK on GitHub Actions — the **Actions** tab, latest run, under
Artifacts, `nspanel-app-arm64`. The panel is arm64; that is the only one it needs. Or build
it yourself:

```bash
flutter build apk --release --split-per-abi
adb connect <panel-ip>:5555
adb install -r build/app/outputs/flutter-apk/app-arm64-v8a-release.apk
```

Enabling adb on the panel, and everything after this, is walked through step by step in
[TUTORIAL.md](TUTORIAL.md).

First launch asks for the Home Assistant URL, a long-lived access token (profile → Security →
bottom of the page), and optionally which dashboard (its `url_path`; empty for the default).
The token is stored on the panel only. To get that screen back later, hold **two fingers**
still on the dashboard for a second - a gesture no card uses, so it cannot fire one by
accident - or from your desk:

```bash
adb shell am force-stop nl.mennovanhout.nspanel
adb shell am start -n nl.mennovanhout.nspanel/nl.mennovanhout.nspanel_app.MainActivity --ez setup true
```

### Provisioning without a keyboard

A wall panel has no comfortable way to type a 180-character token, so the app also takes its
settings from a file you push over adb. Write `setup.json` on your computer:

```json
{ "url": "http://10.0.0.2:8123", "token": "eyJ...", "dashboard": "" }
```

then push it into the app's own directory (no storage permission needed) and launch:

```bash
adb push setup.json /sdcard/Android/data/nl.mennovanhout.nspanel/files/setup.json
adb shell monkey -p nl.mennovanhout.nspanel -c android.intent.category.LAUNCHER 1
```

The app reads it once, saves the settings, and deletes the file. Delete `setup.json` from your
computer too; it has your token in it. A later file is a **partial** update — only the keys in
it change — which is how you re-point a panel at a different dashboard, or adjust its
screensaver, from your desk without re-entering the token. The full set of keys is `url`,
`token`, `dashboard`, `name`, `mqtt`, `tts_engine`, `screensaver` and `feedback`.

### Touch feedback

Every touch-down clicks, and buzzes if the panel has a motor. The click is the built-in
`pop` through a SoundPool, the one Android path that plays within the touch's own frame
(a media player takes a tenth of a second to start, which reads as lag, not feedback). Both
are on by default; turn either off or set the click's volume in `setup.json`:

```json
{ "feedback": { "sound": true, "vibrate": true, "volume": 0.5 } }
```

### Start on boot

The app comes back up by itself after a power cut, and after it has updated itself. Nothing
to enable. If you also want it to be the panel's home screen, so nothing else ever shows
and a stray Home press lands on the dashboard, there is a disabled `Home` alias you can
switch on from your desk:

```bash
adb shell pm enable nl.mennovanhout.nspanel/nl.mennovanhout.nspanel_app.Home
adb shell cmd package set-home-activity nl.mennovanhout.nspanel/nl.mennovanhout.nspanel_app.Home
```

The stock launcher stays installed; `set-home-activity l.l/...` (its package is `l.l`) puts
it back.

### Updating

Once the panel is a Home Assistant device (next section) it has an **update entity**: HA
shows "0.3.0 available" with the release notes and an Install button, and the panel
downloads the APK from this repo's GitHub Releases and installs it on its own - no adb, no
one at the panel. Four panels are four Install buttons, or one automation.

How it can do that: the NSPanel Pro ships with adb listening on its own port 5555 with
authentication off (`ro.adb.secure=0`), so the app talks the adb protocol to
`127.0.0.1:5555` and runs `pm install -r` on itself, exactly what you would do from your
desk. The install kills the running app; a broadcast receiver starts the new one, so from HA
it looks like a ten-second reboot. The setup screen (two-finger hold) shows the installed
version and has the same Update button, and the panel checks GitHub half a minute after
start and every six hours.

Releases come from a tag: `git tag v0.3.0 && git push --tags` and the `Release` workflow
builds the APK and attaches it. **The signing key matters:** Android only installs an update
over an app signed with the same key, so the workflow signs with the keystore in the
repository secrets (`KEYSTORE_B64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`) and
refuses to run without them, and a dev machine signs with the same key through
`android/key.properties` (gitignored). An APK you build without it is signed with your
debug key and installs fine - but a release will not install over it; uninstall first.

The panel is Android 8.1; the build targets API 24 and up. On the Mali-G31 the Flutter engine
falls back from Impeller to Skia on its own (it says so in logcat at startup, worded as an
"opt-out"); nothing to configure, and that is the renderer every measurement here was made on.

## The panel as a Home Assistant device

Give the app your MQTT broker and it registers itself through MQTT discovery: one device,
"NSPanel Dining" or whatever you name it, with these entities.

| Entity | What |
| --- | --- |
| `sensor` Proximity | the graded reading, once a second at most |
| `binary_sensor` Presence | somebody at the panel, from a learned resting level (`proximity_delta`) |
| `sensor` Illuminance | lux, from the light sensor |
| `binary_sensor` Screensaver | whether the wallpaper is showing right now |
| `switch` Screensaver | put the panel to sleep or wake it from an automation |
| `number` Page | which page is showing; set it to turn the page |
| `number` Screen brightness | 0–255 |
| `number` Volume | speaker, 0–100 |
| `notify` Announce | `notify.send_message`: text is spoken; a URL, an HA path, a media-browser file or a built-in sound is played |
| `update` App | the installed and latest version, release notes, and Install (see Updating) |
| `button` Stop audio | |
| Wi-Fi signal, SoC temperature, slow frames, app version, last touch | diagnostics |

Availability is an MQTT will, so the device goes unavailable the moment the panel drops off.

Configure it in `setup.json` (the token line can be left out when it is already stored):

```json
{
  "name": "NSPanel Dining",
  "mqtt": { "host": "10.0.0.2", "port": 1883, "username": "mqtt", "password": "YOUR-MQTT-PASSWORD" },
  "tts_engine": ""
}
```

or on the setup screen. The MQTT client is hand-rolled and QoS 0 with retained state, tested
against a fake broker the same way the HA client is.

**Announcements.** `notify.send_message` with a message speaks it: the app asks Home
Assistant's own TTS engine for the audio (`/api/tts_get_url`), so the voice is whichever you
have configured, and nothing is synthesised on the panel. Leave `tts_engine` empty to use the
first engine HA lists, or name one, e.g. `tts.google_en_com`. Try it from Developer tools →
Actions:

```yaml
action: notify.send_message
target:
  entity_id: notify.nspanel_dining_announce
data:
  message: The washing machine is done
```

A message that names audio is played instead of spoken:

| Message | Plays |
| --- | --- |
| `sound:doorbell` | one of the built-in sounds, listed below |
| `/local/sounds/bell.mp3` | a file in Home Assistant's `www` folder |
| `media-source://media_source/local/bell.mp3` | a file from HA's media browser, resolved through HA |
| `https://…/bell.mp3` | any URL |

JSON works too, and adds two things: `wake` brings the panel out of the screensaver first,
and `volume` sets the speaker for this announcement. Spoken text goes under `message`, a file
under `url`, a built-in sound under `sound`:

```yaml
message: '{"message": "Dinner is ready", "wake": true, "volume": 60}'
```

A doorbell, then, is one automation:

```yaml
alias: Doorbell on the panels
triggers:
  - trigger: state
    entity_id: binary_sensor.doorbell
    to: "on"
actions:
  - action: notify.send_message
    target:
      entity_id: notify.nspanel_dining_announce
    data:
      message: '{"sound": "doorbell", "wake": true, "volume": 80}'
```

The same JSON can be published straight to `nspanel/<id>/say/set`.

**The built-in sounds.** All synthesised (`tool/sounds.py`), so there is nothing to license
and nothing to host; an unknown name is logged with this list. `alarm` and `ring` are the loud
ones; `battery`, `goodnight` and `pop` are deliberately quiet.

| Sound | What it is |
| --- | --- |
| `doorbell` | ding-dong |
| `chime` | one bell |
| `notify` | two soft notes, a plain notification |
| `pop` | a click, for a button |
| `alert` | three beeps |
| `warning` | two falling tones, twice: a door left open, a leak |
| `alarm` | a siren, three seconds: smoke, intrusion |
| `armed` | three rising beeps |
| `disarmed` | three falling beeps |
| `success` | a rising arpeggio: something completed |
| `error` | two low buzzes: something failed |
| `knock` | three knocks on wood |
| `ring` | a phone ringing |
| `timer` | a kitchen timer |
| `laundry` | a little tune: the washer is done |
| `door_open` | a short slide up |
| `door_close` | a short slide down |
| `battery` | two quiet low beeps |
| `morning` | a gentle rising phrase |
| `goodnight` | a slow falling phrase, quiet |

**Screen brightness** needs the `WRITE_SETTINGS` permission, which Android grants only by a
one-time toggle on the panel - or from your desk:

```bash
adb shell appops set nl.mennovanhout.nspanel WRITE_SETTINGS allow
```

Until it is granted, the brightness entity reads but does not write.

There is no MQTT `media_player` platform in Home Assistant, so this does not make the panel
one; announcements, chimes and a volume slider are what a small mono speaker is for. A real
`media_player` entity would come from a DLNA renderer inside the app, which HA discovers on
its own - a separate piece of work.

## Motion

Four moments animate, and only those: cards rise into place when a page first shows (fade
and a 14px lift, 60 ms apart); the screensaver fades in over the dashboard; it fades out
again, with touches reaching the dashboard the moment the fade starts rather than when it
ends; and a new photo crossfades over the old with a soft push, the first one fading in
rather than popping when its bytes land.

All of it is opacity and transform, each a one-off - the same budget the cards keep, because
the panel is the reason this app exists. Nothing runs continuously, and nothing animates
while you are dragging a card.

**The first swipe.** Skia compiles a shader the first time a draw op reaches this GPU, and
on the panel that was 150–270 ms per frame the first time a page was swiped in, on top of
building the page inside the gesture. So the pages next to the one on screen are built
ahead of time, without their entrance animation, and a second after load the app swipes
through every page once, hidden, to spend the compile time while nothing moves. After a
normal launch the first swipe now has no slow frame; after a fresh install, when Android's
shader cache is empty, one survives, and the next launch is clean. The **Slow frames**
diagnostic counts frames over 33 ms since launch, and `adb logcat -s flutter` names each
one with its build and raster time, so lag is a number you can chart in HA.

## What carries over from the web cards, and what does not

The rules that make the web cards feel right on this hardware are decisions, not web code,
and they are all here: no service call until the finger lifts, the local value winning for
`echo_ms` after a change, the bulb's colour clamped into a readable band, a scene at `unknown`
not being "broken", a button that acknowledges a tap the state will never confirm. The
websocket client is a port of the one verified against a fake HA in the cards repo, and is
tested the same way here (`flutter test`).

Not here: Home Assistant's more-info dialog. Where the web cards open it, this app opens the
card's own sheet (climate) or does nothing (read-only cards). And only these eleven card
types render; this is a panel, not a browser.

## Layout

```
lib/ha/          Home Assistant websocket, entity state with a notifier per entity
lib/mqtt/        MQTT 3.1.1 client (hand-rolled) and the HA-discovery bridge
lib/update/      GitHub Releases check, and an adb client for installing over 127.0.0.1:5555
lib/audio/       the speaker: TTS via HA, URLs, media-browser files, built-in sounds
lib/config/      settings (url, token, dashboard, mqtt, ...), Lovelace -> pages, screensaver
lib/ui/          the shared drag surface, the long-press sheet, the pager, screensaver, setup
lib/cards/       one file per card, plus the registry that maps type -> widget
lib/util/        colour clamp, icon lookup, number formatting, the panel's sensors
assets/sounds/   the built-in sounds, generated by tool/sounds.py together with lib/audio/sounds.dart
test/            colour, config parsing, the HA protocol and MQTT against fakes
```
