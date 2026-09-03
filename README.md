# NSPanel app

Home Assistant on the Sonoff NSPanel Pro 86, natively.

A Flutter app that renders the `custom:nspanel-*` cards from
[NSPanel-cards](https://github.com/mennovanhout/NSPanel-cards) without a browser in the way.
The web cards are careful with the panel's frame budget, but they are passengers: open a
dashboard in the companion app and the WebView is also running the whole HA frontend, and on a
PX30 that is most of the cost. This draws straight to the GPU instead.

## One config, two renderers

The app **reads your Lovelace dashboard from Home Assistant** over the websocket and renders
the `nspanel-*` cards in it. You keep configuring in HA - YAML or the GUI editor, which keeps
working - and the panel follows; edit the dashboard and it reloads on its own. The same
config still works in a browser with the web cards, on a phone or a tablet.

The layout it expects is the one the cards' README recommends: a panel view holding a swipe
card whose children are the pages. A plain view with no swipe card becomes one page, stacks
flattened into it. Cards it does not know are shown as a marked gap rather than dropped, so
you can see what a dashboard is asking for that this app cannot do.

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
  image_url: https://mennovanhout.nl/r/62bcce7ed0807c94b3432152b3ba00a4
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
when someone approaches depends on the unit. So by default the app takes the first two seconds
of the screensaver as the resting level and wakes when a reading departs from it by
`proximity_delta`. The setup screen (triple-tap the top-left corner) shows the live value; watch
it as you walk up, and if you would rather be explicit, `proximity_below: 30` or
`proximity_above: 90` wake on an absolute threshold instead.

**The frosted clock is the one `BackdropFilter` in this app**, the exact thing the cards avoid
on this GPU. It is affordable here because nothing else is happening: the blur re-rasterises
only while the clock slides once a minute. `frost: false` if it ever stutters. Pictures are
decoded at the panel's size, not the photo's, and the previous one is evicted before the next
is fetched, so a stream of large photos does not grow memory.

## Install

```bash
flutter build apk --release
adb connect <panel-ip>:5555
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

First launch asks for the Home Assistant URL, a long-lived access token (profile → Security →
bottom of the page), and optionally which dashboard (its `url_path`; empty for the default).
The token is stored on the panel only. Triple-tap the top-left corner to get that screen back.

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
computer too; it has your token in it. Pushing a new file later replaces the stored settings,
which is also how you re-point a panel at a different HA or dashboard from your desk.

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
| `notify` Announce | `notify.send_message`: text is spoken, a URL is played |
| `button` Stop audio | |
| Wi-Fi signal, SoC temperature, app version, last touch | diagnostics |

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
first engine HA lists, or name one, e.g. `tts.google_en_com`. A message that is a URL is
played instead. Automations can also publish straight to `nspanel/<id>/say/set`, as text or
as `{"url": "..."}`.

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

## What carries over from the web cards, and what does not

The rules that make the web cards feel right on this hardware are decisions, not web code,
and they are all here: no service call until the finger lifts, the local value winning for
`echo_ms` after a change, the bulb's colour clamped into a readable band, a scene at `unknown`
not being "broken", a button that acknowledges a tap the state will never confirm. The
websocket client is a port of the one verified against a fake HA in the cards repo, and is
tested the same way here (`flutter test`).

Not here: Home Assistant's more-info dialog. Where the web cards open it, this app opens the
card's own sheet (climate) or does nothing (read-only cards). And only these ten card types
render; this is a panel, not a browser.

## Layout

```
lib/ha/          websocket protocol, entity state with a notifier per entity
lib/config/      settings (url, token, dashboard) and the Lovelace -> pages parser
lib/ui/          the shared drag surface, the long-press sheet, the pager, setup
lib/cards/       one file per card, plus the registry that maps type -> widget
lib/util/        colour clamp, icon lookup, number formatting
test/            colour, config parsing, and the protocol against a fake HA
```
