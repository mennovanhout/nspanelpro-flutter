# Light control captures

These are unedited 480×480 captures from a real NSPanel Pro 86 running the
combined development build, with simulated Home Assistant entities only.
The light controllers, colour tracks and value-memory implementation match this
focused contribution. Unrelated local display and fan features are not included
in the contribution.

- `dimmer.png`: 50% brightness.
- `tw.png`: 3500 K target colour at 50% brightness; no visible temperature scale.
- `rgb.png`: hue 180°, saturation 70%, brightness 50%; the last completed hue
  interaction selects the plus/minus target.
- `effects.png`: Rainbow remembered and selected while the light is off.
- `last-values.png`: RGB details after restarting the application while the
  simulated server reports only off states with missing colour/brightness values.

The SONOFF floating back button was temporarily disabled during capture; the
screen contents were not retouched. Its original setting was restored afterward.
