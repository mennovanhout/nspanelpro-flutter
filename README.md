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

## Install

```bash
flutter build apk --release
adb connect <panel-ip>:5555
adb install -r build/app/outputs/flutter-apk/app-release.apk
```

First launch asks for the Home Assistant URL, a long-lived access token (profile → Security →
bottom of the page), and optionally which dashboard (its `url_path`; empty for the default).
The token is stored on the panel only. Triple-tap the top-left corner to get that screen back.

The panel is Android 8.1; the build targets API 24 and up. If you see rendering glitches on
the Mali-G31, switch the renderer off Impeller in `AndroidManifest.xml`:

```xml
<meta-data android:name="io.flutter.embedding.android.EnableImpeller" android:value="false"/>
```

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
