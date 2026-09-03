# NSPanel Pro + Home Assistant, from nothing to a working panel

Two parts. **Part 1** is the one-time setup: the cards in Home Assistant, a dashboard, the app
on your first panel. **Part 2** is the recipe for every panel after that — most people have
several, and once Part 1 is done each new one is ten minutes.

If you already have the cards installed and a dashboard that works, skip to
[Part 2](#part-2-adding-a-panel).

---

## What you are setting up

Three pieces, and it helps to know which does what:

| Piece | Lives | Does |
| --- | --- | --- |
| **NSPanel-cards** | Home Assistant, via HACS | The cards: light, cover, climate, media, buttons, sensors, status, weather, clock. They work in any browser and in the app. |
| **A dashboard** | Home Assistant | Your layout, in YAML or the GUI editor. One config; both the browser and the app render it. |
| **The app** | On each panel | Renders that dashboard natively (the panel's browser is too slow for it), and makes the panel a Home Assistant device with sensors, a screensaver and a speaker. |

The dashboard is the contract between them. You configure it in Home Assistant exactly once,
and the app on each panel follows it — edit it and the panels update themselves.

---

## Part 1: first-time setup

### 1. Install the cards

1. HACS → ⋮ (top right) → **Custom repositories**
2. Repository `https://github.com/mennovanhout/NSPanel-cards`, category **Dashboard**, Add
3. Find **NSPanel Cards** in HACS and install it
4. HACS usually registers the resource itself. Check: Settings → Dashboards → ⋮ →
   **Resources**. You want `/hacsfiles/nspanel-cards/nspanel-cards.js` as a
   **JavaScript module**. Add it if it is missing.
5. Reload the browser (Home Assistant caches hard; a hard refresh, Ctrl+Shift+R, if the cards
   do not appear in the card picker).

For swiping between pages in the **browser**, also install
[simple-swipe-card](https://github.com/nutteloost/simple-swipe-card) from HACS. The app does
not need it — it treats a swipe card's children as pages, and each dashboard view as a page
when there is no swipe card — but the browser does.

### 2. Make a dashboard for the panel

Settings → Dashboards → **Add dashboard** → "New dashboard from scratch". Two things matter:

- **Title** whatever you like; the **URL** must contain a hyphen, e.g. `nspanel-dining`.
  That URL path is how the app finds it.
- Open it, ⋮ → **Edit dashboard** → **Take control**. A brand-new dashboard is auto-generated
  and has no saved config yet; the app cannot read one until you have taken control and saved.

Then ⋮ → **Raw configuration editor** and paste a starting point. This one is the layout the
cards were designed around: a 480×480 panel, one view, pages inside a swipe card, each page a
vertical stack that adds up to the panel's height (260 + 184, or 300 + 144, plus the gaps).

```yaml
title: Dining
views:
  - type: panel
    cards:
      - type: custom:simple-swipe-card
        card_spacing: 12
        cards:
          - type: vertical-stack
            cards:
              - type: custom:nspanel-light-card
                entity: light.dining_lights
                title: Dining table
                height: 260
                presets:
                  - name: Low
                    brightness_pct: 15
                  - name: Dinner
                    brightness_pct: 45
                    color_temp_kelvin: 2400
                  - name: Full
                    brightness_pct: 100
              - type: custom:nspanel-light-card
                entity: light.kitchen_spots
                title: Kitchen spots
                height: 184
                show_presets: false

          - type: vertical-stack
            cards:
              - type: custom:nspanel-climate-card
                entity: climate.living_room
                title: Living room
                height: 300
              - type: custom:nspanel-sensors-card
                height: 144
                entities:
                  - entity: sensor.outside_temp
                    name: Outside
                  - entity: sensor.outside_hum
                    name: Humidity

          - type: vertical-stack
            cards:
              - type: custom:nspanel-button-card
                height: 300
                columns: 2
                buttons:
                  - entity: script.goodnight
                    name: Goodnight
                    icon: mdi:weather-night
                    confirm: true
                  - entity: script.good_morning
                    name: Good morning
                    icon: mdi:weather-sunset
              - type: custom:nspanel-clock-card
                height: 144
              # not a card - the app's screensaver, configured here so it lives
              # with everything else (see step 6)
              - type: custom:nspanel-screensaver
                after: 300
                image_url: https://example.com/random-photo
```

Change the entity ids to yours and save. Open the dashboard in a browser: you should see the
cards working. Every card and option is documented in the
[cards README](https://github.com/mennovanhout/NSPanel-cards#configuration); the light and
cover cards also have a visual editor (the pencil on a card), and so do the others.

Two things worth knowing at this point:

- **Heights are the panel's pixels.** At stock density the NSPanel Pro is 480×480 and a page
  is 12px padding + cards + 12px gaps. `260 + 184`, `300 + 144` and `444` all fill it exactly.
- **`custom:nspanel-screensaver` renders nothing in the browser.** It is configuration for the
  app. Put it at the end of a vertical stack, not as its own page, or the browser shows a
  blank page.

### 3. Get adb talking to the panel

The app is installed over adb, like any sideloaded Android app. If you have never done this:

1. Install the Android platform tools on your computer (`adb`). On Windows,
   `winget install Google.PlatformTools`; on macOS, `brew install android-platform-tools`.
2. Enable ADB on the panel. It is switched on from the eWeLink app: open the panel, its
   settings, **About**, and tap the version line repeatedly until developer options appear,
   then enable ADB debugging. blakadder's
   [sideloading guide](https://blakadder.com/nspanel-pro-sideload/) has screenshots if that
   does not match your firmware.
3. Find the panel's IP (your router, or the eWeLink app), then:

```bash
adb connect 10.0.0.50:5555
```

`adb devices` should list it as `device`. If it says `unauthorized`, look at the panel — it is
asking you to allow the computer.

### 4. Install the app

Get `app-arm64-v8a-release.apk` — from the
[Actions tab](https://github.com/mennovanhout/nspanelpro-flutter/actions) of the app repo
(every push builds one, under Artifacts), or build it yourself with `flutter build apk
--release --split-per-abi`. The panel is arm64; that is the only one you need.

```bash
adb -s 10.0.0.50:5555 install -r app-arm64-v8a-release.apk
```

Grant it the one permission Android will not give an app by itself, so Home Assistant can
set the screen brightness later:

```bash
adb -s 10.0.0.50:5555 shell appops set nl.mennovanhout.nspanel WRITE_SETTINGS allow
```

### 5. Connect it to Home Assistant

The app needs your Home Assistant URL, a long-lived access token, and which dashboard. A
wall panel is a miserable place to type a 180-character token, so it takes all of that from a
file you push over adb instead.

First make a token: in Home Assistant, click your name (bottom left) → **Security** → scroll
to the bottom → **Create token**. Name it after the panel. Copy it; you only see it once.

Then write `setup.json` on your computer:

```json
{
  "url": "http://10.0.0.2:8123",
  "token": "eyJ...your long-lived token...",
  "dashboard": "nspanel-dining",
  "name": "NSPanel Dining"
}
```

- `url` — where Home Assistant is, as the panel reaches it (an IP is the safe choice).
- `dashboard` — the URL of the dashboard from step 2. `nspanel-dining`, `/nspanel-dining/0`
  or the whole address all work; the app trims it. Empty means the default dashboard.
- `name` — what the panel is called in Home Assistant, once it becomes a device.

Push it and launch the app:

```bash
adb -s 10.0.0.50:5555 push setup.json /sdcard/Android/data/nl.mennovanhout.nspanel/files/setup.json
adb -s 10.0.0.50:5555 shell monkey -p nl.mennovanhout.nspanel -c android.intent.category.LAUNCHER 1
```

The app reads the file once, stores the settings on the panel, and **deletes the file**. Delete
it from your computer too — it has your token in it.

Your dashboard should now be on the panel. Swipe sideways for pages; drag up and down on a
light for brightness. If instead you see a message, it says what is wrong: a rejected token
puts the setup screen back, and a dashboard that cannot be loaded lists the dashboards that do
exist, or tells you to take control of it in Home Assistant.

You can also type all of this on the panel's setup screen. Triple-tap the top-left corner to
get that screen back at any time.

### 6. Make the panel a Home Assistant device

Add your MQTT broker to the same `setup.json` (only the keys you include change; everything
else stays as it was):

```json
{
  "mqtt": { "host": "10.0.0.2", "port": 1883, "username": "mqtt", "password": "..." }
}
```

Push it and relaunch as in step 5. Within a few seconds Settings → Devices shows a new
device with the name from step 5, and these entities:

- **Proximity** and **Presence** (somebody at the panel), **Illuminance** (lux)
- **Screensaver** — a binary sensor for whether the wallpaper is showing, and a switch to put
  the panel to sleep or wake it from an automation
- **Page** (which page is showing; set it to turn the page), **Screen brightness**, **Volume**
- **Announce** — a notify entity: `notify.send_message` with text speaks it through your HA
  TTS engine; a URL is played instead. Plus a **Stop audio** button.
- Wi-Fi signal, SoC temperature, app version, last touch, as diagnostics

The device goes unavailable the moment the panel drops off the network.

If you use Mosquitto from the Home Assistant add-on store, the host is Home Assistant's IP
and the user/password are the ones you created for it. The password goes only into this
file on your computer and into the panel's own storage.

### 7. The screensaver

You already configured it in step 2 — the `custom:nspanel-screensaver` card. After `after`
seconds without a touch the panel shows a photo from `image_url` (any URL that returns an
image; one that returns a random image each time is ideal) with a clock that wanders so
nothing burns in. A touch wakes it, and so does walking up to it: the panel's proximity
sensor is real. If you would rather keep it panel-specific, the same keys go under
`"screensaver": { ... }` in `setup.json`; the dashboard card wins when both exist.

The setup screen shows the live proximity reading, so if the panel does not wake when you
approach, watch the number as you walk up and set `proximity_delta` or an absolute
`proximity_below` / `proximity_above` accordingly.

### 8. Starting on boot

Today the app has to be started: a tap on its icon, or from your desk:

```bash
adb -s 10.0.0.50:5555 shell monkey -p nl.mennovanhout.nspanel -c android.intent.category.LAUNCHER 1
```

It stays up indefinitely and keeps the screen on, but after a power cut you start it again.
Automatic start on boot is on the list.

---

## Part 2: adding a panel

Everything in Part 1 that lives in Home Assistant is done once. Each new panel needs its own
dashboard (usually), its own token, its own name, and the app. In order:

**1. A dashboard for it.** Settings → Dashboards → Add dashboard, URL `nspanel-<room>`,
Take control, paste your layout, change the entities. Or point several panels at the same
dashboard if they should show the same thing — nothing stops you.

**2. A token for it.** Profile → Security → Create token, named after the panel. One token
per panel means you can revoke one panel without touching the others.

**3. adb to it.** Enable ADB on the panel (eWeLink → the panel → About → tap the version line
until developer options appear), then `adb connect <ip>:5555`.

**4. Install and grant:**

```bash
adb -s <ip>:5555 install -r app-arm64-v8a-release.apk
adb -s <ip>:5555 shell appops set nl.mennovanhout.nspanel WRITE_SETTINGS allow
```

**5. One `setup.json` with everything:**

```json
{
  "url": "http://10.0.0.2:8123",
  "token": "eyJ...this panel's token...",
  "dashboard": "nspanel-bedroom",
  "name": "NSPanel Bedroom",
  "mqtt": { "host": "10.0.0.2", "port": 1883, "username": "mqtt", "password": "..." },
  "screensaver": { "after": 600, "image_url": "https://example.com/random-photo" }
}
```

```bash
adb -s <ip>:5555 push setup.json /sdcard/Android/data/nl.mennovanhout.nspanel/files/setup.json
adb -s <ip>:5555 shell monkey -p nl.mennovanhout.nspanel -c android.intent.category.LAUNCHER 1
```

Delete `setup.json` afterwards. The panel appears in Home Assistant as its own device — the
device id is the panel's Android id, so two panels never collide, and `name` is what tells
them apart in the UI.

**Changing a panel later** is the same push with only the keys that change. To re-point a
panel at another dashboard:

```json
{ "dashboard": "nspanel-kitchen" }
```

To update the app on a panel, `adb install -r` the new APK; settings survive.

---

## When something is off

| You see | It means | Do |
| --- | --- | --- |
| "Custom element doesn't exist: nspanel-light-card" in the browser | The resource is not registered, or the browser has the old file | Check Resources (step 1), hard-refresh. On a manual install, bump the `?v=` on the resource URL. |
| The panel says the dashboard could not be loaded and lists names | The `dashboard` value does not match a URL path | Use one of the listed names, or empty for the default. |
| The panel says the dashboard exists but has no saved config | It is still auto-generated | Open it in HA → Edit dashboard → Take control → Save. The panel reloads by itself. |
| "That token was rejected" | Wrong or revoked token | Make a new one, push a `setup.json` with just `token`. |
| A card is drawn as a marked gap saying "Not rendered here" | The dashboard uses a card type the app does not have | Only `nspanel-*` cards, `vertical-stack`, `horizontal-stack` and `grid` render on the panel. |
| No device in Home Assistant | The app cannot reach the broker, or the credentials are wrong | `adb logcat -d \| grep mqtt` on the panel says which. Check host, port, user, password; the MQTT integration must be set up in HA. |
| Announce is silent | No TTS engine, or the panel cannot reach the audio URL | Set `tts_engine` (e.g. `tts.google_en_com`) in `setup.json`; make sure `url` is reachable from the panel. |
| Brightness does not change from HA | The permission was not granted | The `appops` command from step 4. |
| The panel does not wake when you walk up | The sensor's direction or range is not what the default assumes | Triple-tap top-left, watch "Proximity sensor now" as you approach, set `proximity_delta` or `proximity_below` / `proximity_above`. |
| Photos are squashed or the screensaver is dark | Old build | Update the app; the current one fits pictures to the screen on black. |
| Everything is laggy | You are looking at the dashboard in the panel's browser | That is what the app is for. The browser on this hardware is the bottleneck, not the cards. |
