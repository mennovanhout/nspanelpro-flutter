# UI guidelines

## Native UI conventions

New controls should reuse `ControlSheet`, `SheetButton`, `SheetMetrics` and the
`Ns` palette instead of introducing Material sliders, pills or theme-derived
button colours. These conventions are extracted from the existing light, cover
and climate sheets in `lib/ui/sheet.dart`, the cards in `lib/ui/fill_card.dart`,
and the corresponding web bundle. Native measurements below are the reference;
the web sheet has some different radii and text sizes.

- Preserve context: the sheet is transparent over a 72% ground-colour scrim,
  with a 180 ms fade. Title/state stay at the upper left, Close at the upper
  right, the main control in the centre and actions along the bottom.
- Use large rounded rectangles: cards have radius 22, level surfaces 20 and
  sheet buttons 18. Secondary buttons use `Ns.surface` (`#16191F`) with
  `Ns.text` (`#F2F4F7`); a primary action uses the card accent with dark text.
  Selected secondary actions may use a 16% accent tint.
- Keep the hierarchy: title 22/700, state 15/500 in `Ns.muted` (`#98A1B0`),
  level 44/700 with tabular digits. Action labels are 14/600 with 24px icons;
  step icons are 34px. Use `Ns.danger` (`#F87171`) for command errors.
- Levels use the full vertical fill surface, with large plus/minus controls
  to its right. Dragging updates locally; release commits one command. A tap
  sets an absolute level; plus/minus advance one supported step. Cancellation,
  opening, closing and browsing choices never actuate a device. Keep local
  echo while awaiting state, and roll back rejected commands.
- Offer one contextual power action, not an On/Off pair. Successful power or
  preset selection closes the dialog; failure stays visible for retry. Show
  only supported controls and disable unavailable or pending actions.
- Keep at most four equal-width bottom actions. Additional choices open an
  explicit chooser with two columns of 76px-high tiles, a fixed Back action
  and the same Close button. Scroll the choices, never shrink their hitboxes.

### Colour rules (initial)

This is the starting colour vocabulary for new controls and reviews. The tables
record the current palette and native component behaviour; rules for new work
are stated separately from known gaps. Tokens live in [`Ns`](lib/ui/theme.dart);
the shared web base colours live in `BASE_CSS` in the NSPanel-cards bundle.
Reuse those tokens rather than adding almost-identical hex values per widget.

| Token | Hex | Role / current default use |
| --- | --- | --- |
| `ground` | `#0B0D10` | Screen background; dark foreground on filled primary actions |
| `surface` | `#16191F` | Cards, sheet level track and secondary sheet buttons |
| `surface2` | `#1E232B` | Nested neutral tiles and opaque card chips |
| `text` | `#F2F4F7` | Main labels, values and icons on dark surfaces |
| `muted` | `#98A1B0` | Supporting text and inactive icons on dark surfaces |
| `amber` | `#FFB74A` | Light, switch and fan default accent |
| `sky` | `#7CC4FF` | Cover, sensor and weather default accent |
| `ember` | `#FF8A65` | Climate default accent |
| `violet` | `#A78BFA` | Media default accent |
| `mint` | `#8DDBA4` | Button/action and disarmed-alarm default accent |
| `gold` | `#F0A03C` | Status-card default accent |
| `danger` | `#F87171` | Command error/offline emphasis; also existing armed/triggered alarm states |

**Meaning and precedence.** Keep one entity's accent consistent between its card
and detail sheet. A valid configured `accent` takes precedence over the default.
Lights without an explicit accent may use their reported RGB colour while on
when `follow_color` is enabled (the default),
passed through `readableTint`; otherwise they fall back to amber. Sensor severity
and alarm states have their own explicit state colour mappings. Error feedback
must remain distinguishable even when an entity has a custom accent.

Category accents are not universal status signals: sky does not mean selected,
mint does not prove success, and amber/gold do not inherently mean warning.
A primary button identifies an action, not the current entity state: an amber
"Turn off" button is still an action. Keep a state label/icon alongside colour;
use an explicit check mark or label for selection and readable text for errors.
For new controls, reserve danger emphasis for errors or attention states rather
than decoration. The existing alarm's red armed state is a documented exception
to treating red as a fault; its label must distinguish armed from triggered.

| State / role | Native convention to reuse |
| --- | --- |
| Off / idle | Neutral surface; main label remains readable; muted icon/state. Off is not disabled. |
| On / active switch | Accent at 16% alpha for the tile background; accent icon/label plus On state. |
| Selected secondary choice | Accent at 16% alpha plus an explicit selection cue; do not rely on tint alone. |
| Primary sheet action | Solid accent background with `ground` text/icons; verify custom accent contrast. |
| Secondary sheet action | `surface` background with `text` foreground. |
| Disabled action | Existing sheet buttons/chips use 35% whole-control opacity and block input. |
| Unavailable entity | Existing cards use 45% whole-card opacity plus Unavailable/OFFLINE or an alert icon; block device actions. |
| Command failure | `danger` message, dialog remains open; restore the confirmed value after failed optimistic changes. |

Alpha values are **opacity**, not colour lightness. Composite them over the actual
surface before judging the result. Reuse the component's treatment: dashboard
fills use 62%/34% accent gradient stops and an accent level line; the native sheet
fill uses solid accent/62% stops. The sheet scrim is 72% `ground`. Those different
roles should not be replaced with one universal opacity. Web components retain
some different tint strengths; shared base hex values do not imply pixel parity.

**Readability rules for new work.** Use light text on neutral dark surfaces and
dark text on bright solid action fills. Check every custom accent and the actual
composited background, including the full range of a fill, selected states and
disabled controls. Prefer a stable dark label backing when a value can cross a
bright or variable fill. Preserve status text independently of disabled action
opacity. Colour, opacity and text shadow alone must not carry essential meaning.
Any contrast fix to a shared component should cover all its consumers together.

For reference, calculated sRGB contrast ratios for opaque token pairs are about
16.0:1 (`text` on `surface`), 6.8:1 (`muted` on `surface`), and 11.2:1 (`ground`
on amber). `text` on solid amber is only about **1.6:1**. These pair calculations
are not a contrast audit of the complete rendered screen. In particular, the
existing sheet's white percentage over a bright fill and its shadow remain a
review item. `readableTint` is an RGB brightness heuristic, not proof of contrast
compliance, and custom dark accents can weaken dark primary-action text.

**Next review items.** Check percentage labels across all standard/custom fills,
selected-but-disabled preset readability and full-card unavailable opacity on the
panel. Decide semantic success/warning tokens only with a concrete use case;
there is no global success/warning mapping yet. Future colour pickers should
separate the device colour preview from selection/error indicators. This initial
rulebook changes documentation only; it does not claim those gaps are fixed.

### Touch geometry

Sizes are **logical pixels**, not icon sizes. At the tested Pro 86 configuration
(480×480 pixels, Android density 160) they also equal physical pixel counts.
Insets and larger accessibility text can change the available content area.
The figures below describe a 480×480 viewport with no SafeArea inset, normal
text size and one bottom action row. Widget tests compare the actual light
hit rectangles, including a tap near a button corner.

| Element | Touch area / geometry |
| --- | --- |
| Sheet outer padding | 16 on all sides; usable width 448 |
| Close | 56 × 56; icon only 26 |
| Main vertical level surface | 338 × 288; entire rectangle is interactive |
| Plus and minus | each 96 × 137, separated vertically by 14 |
| Bottom action row | height 76; 8 between buttons |
| One / two / three / four bottom actions | width 448 / 220 / 144 / 106 each |
| Preset chooser tile | 220 × 76; 8 between columns and rows |
| Existing card preset chip | height 56; width shares the row; 8 between chips |
| Existing switch/button tile | entire tile is the target; configured height/columns and 10px grid gaps determine size |

The sheet body height is `H − safeInsets − 32 − 56 − 14 − (76 + 14)` when
there are bottom actions; without them the body gets the additional 90px.
Its level width is `W − safeInsets − 32 − 96 − 14`. Each step button gets
`(bodyHeight − 14) / 2`. The 52×52 card icon box is decoration inside a larger
card target, not a separate small button.

For new panel controls, preserve **at least 56×56** as the project touch-target
floor, and retain the larger 76px action rows and 96px step column wherever the
existing sheet uses them. This is a convention derived from this UI, not a claim
that every historical configurable layout enforces a universal minimum. Measure
actual targets at the intended viewport; a large glyph alone does not establish
a large target. Disabled targets are visibly subdued and must not forward a tap
to the dashboard. Keep feedback governed by the panel's existing settings.


### Light colour dialogs

Light sheets keep horizontal padding 16, radius 20 tracks, radius 18 buttons,
56px Close and 76px actions. Vertical padding is 12 and gaps above/below the body
are 8, making the body **308px** high at 480×480. Other sheets keep their existing
288px bodies. The right step column stays 96px wide; each button grows to 147px.
Within the remaining 338px use one brightness track, two 162px tracks for TW, or
three 103⅓px tracks for hue/saturation/brightness, with 14px gaps.

Keep tracks visually unlabelled: no Kelvin or RGB numbers, separate control tabs,
or circular thumbs. Mark the position with a full-width soft shadow, without
an opaque coloured line or outline. Use a transparent 3px marker, 5px for the
selected `last_used` target, with a black 45% shadow (0/−1 offset, blur 4, no spread), weaker below.
Clip the shadow out of the marker itself: its crisp central strip shows the
unmodified gradient, with soft shadow only outside, matching CSS box-shadow. Follow the target light colour
for the brightness fill at full colour, including live colour/white previews.
Place the brightness marker inside the top of its fill so the crisp centre
shows the target colour. Gradient markers remain just above their position.
Clamp every marker inside the track at either end. Colour is
a preview, not selection or success. Only brightness has embedded percentage text.
Keep the percentage centred with its existing 44px digits (scaled down only
when necessary), with a half-size 22px/600 percent sign on the same baseline.
Like the cards, use a consistently light `text` foreground with
the existing shadow. Add a fine 1px `ground` shadow contour to keep the glyphs
legible over bright target fills. Never split the number into light and dark
regions at the fill boundary. Paint it above the position line. No label box.
Colour gradients and brightness target fill use full opacity, independently of
category accents. While off, the power action uses the neutral `surface` background
and `text` foreground, like the other actions. While on, it uses a readable tint
of the target colour; explicit `accent` and `follow_color: false` still override
that tint. Remembered colours do not mark an off action as active. Existing card
colours remain unchanged.

Effects and light presets use the two-column 220×76 chooser convention, with fixed Back and Close. Configured effects are explicitly checked against
capabilities and selection has a check mark. Semantic slider names, values and
increase/decrease actions are retained even though the visual scales are absent.

An active effect choice stays at full opacity even though repeating the command
is blocked. Use the existing 16% accent tint composited over opaque `surface`,
an inset 2px `text` outline and a check mark. The outline does not change the
220×76 hit area. Keep light text on this dark background; selection must remain
clear even with a dark custom accent. Only actual unavailability or an unsupported
effect uses disabled dimming. Expose selection to accessibility as well.

Light controls keep their normal opacity during a drag and while a command is
pending. Temporary input locks must not fade neighbouring sliders, steps, actions
or choices. Unavailable devices, unsupported choices and range limits still use
the disabled treatment; input and accessibility guards remain in force.

### Remembered light values

Off-state light details may show last confirmed levels and colours. Keep the
normal geometry and percentage typography; mark the existing status line as
`Off · last values`. Dashboard tiles remain off. Do not imply availability or
restore capabilities from memory. In the effect chooser a remembered selection
keeps its check mark, but remains actionable while off so it can turn the light
on. Opening details or the plain power action never restores cached parameters.
