import 'fmt.dart';

/// What HA's condition ids mean in a sentence. Anything not listed reads
/// fine with its dashes turned into spaces.
const _conditionLabels = {
  'partlycloudy': 'Partly cloudy',
  'clear-night': 'Clear',
  'lightning-rainy': 'Thunder, rain',
  'snowy-rainy': 'Sleet',
  'windy-variant': 'Windy',
  'pouring': 'Heavy rain',
  'exceptional': 'Severe',
};

String conditionLabel(String state) =>
    _conditionLabels[state] ?? capitalise(state.replaceAll('-', ' '));

/// The rain in one forecast entry, as short as a forecast tile allows:
/// `80% · 1.2mm`, `3% · 0mm`, and just the half the provider sends when it
/// sends one. No space before the unit: five tiles across leave ~73 px. The amount is always shown when it is known, dry hours too:
/// the chance alone cannot tell a drizzle from a downpour, and a missing
/// amount looks like a missing feature. Null when the provider sends neither.
/// [wet] is "worth noticing": a real chance, or any amount at all.
({String text, bool wet})? rainOf(
  Map<dynamic, dynamic> f, {
  String unit = 'mm',
}) {
  final p = f['precipitation_probability'];
  final a = f['precipitation'];
  final prob = p is num ? p : null;
  final amount = a is num ? a : null;
  if (prob == null && amount == null) return null;
  final parts = <String>[
    if (prob != null) '${prob.round()}%',
    if (amount != null)
      amount > 0 ? '${fmt(amount, amount < 10 ? 1 : 0)}$unit' : '0$unit',
  ];
  return (text: parts.join(' · '), wet: (prob ?? 0) >= 30 || (amount ?? 0) > 0);
}

/// Home Assistant's own `weather-forecast` card, read as an nspanel weather
/// card, so a dashboard that already has one renders on the panel without
/// being rewritten. Its options map across where they mean the same thing;
/// the rest (`show_current`, `theme`, `secondary_info_attribute`) have no
/// counterpart and are ignored.
Map<String, dynamic> weatherConfigFromHa(Map<String, dynamic> c) => {
  'type': 'custom:nspanel-weather-card',
  'entity': c['entity'],
  if (c['name'] != null) 'title': c['name'],
  'show_forecast': c['show_forecast'] is bool ? c['show_forecast'] : true,
  'forecast_type': c['forecast_type'] ?? 'daily',
  'forecast_count': (c['forecast_slots'] as num?)?.toInt() ?? 5,
  // HA's card sizes itself; ours needs a height, and room for the rain line
  'height': c['height'] ?? (c['show_precipitation'] == true ? 280 : 240),
  for (final k in ['show_precipitation', 'icon', 'accent'])
    if (c.containsKey(k)) k: c[k],
};
