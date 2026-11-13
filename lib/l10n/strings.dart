import 'package:flutter/widgets.dart';

/// The languages the panel speaks. English is the fallback for everything
/// else Home Assistant might be set to.
enum Lang { en, nl, de }

/// `nl`, `nl-BE`, `de_AT`, `en-GB` -> the language; anything we do not speak
/// -> null, so the caller can fall through to the next source.
Lang? langFromCode(String? code) {
  final c = (code ?? '').trim().toLowerCase();
  if (c.isEmpty) return null;
  final base = c.split(RegExp('[-_]')).first;
  for (final l in Lang.values) {
    if (l.name == base) return l;
  }
  return null;
}

/// Every word the panel draws, in all three languages side by side, so a
/// missing translation is visible in review rather than at the wall.
///
/// Read it with [L.of] inside a build: that also rebuilds the widget when the
/// language changes. Without an [L] above (widget tests), it is English.
class Strings {
  const Strings(this.lang);
  final Lang lang;

  static const en = Strings(Lang.en);
  static const nl = Strings(Lang.nl);
  static const de = Strings(Lang.de);
  static Strings of(Lang l) => switch (l) {
    Lang.en => en,
    Lang.nl => nl,
    Lang.de => de,
  };

  String _t(String en, String nl, String de) => switch (lang) {
    Lang.en => en,
    Lang.nl => nl,
    Lang.de => de,
  };

  // ---- shared states -------------------------------------------------------

  String get unavailable =>
      _t('Unavailable', 'Niet beschikbaar', 'Nicht verfügbar');
  String get unknown => _t('Unknown', 'Onbekend', 'Unbekannt');
  String get missing => _t('Missing', 'Ontbreekt', 'Fehlt');
  String get on => _t('On', 'Aan', 'An');
  String get off => _t('Off', 'Uit', 'Aus');
  String get turnOn => _t('Turn on', 'Aanzetten', 'Einschalten');
  String get turnOff => _t('Turn off', 'Uitzetten', 'Ausschalten');
  String get stateOpen => _t('Open', 'Open', 'Offen');
  String get stateClosed => _t('Closed', 'Gesloten', 'Geschlossen');
  String get loading => _t('Loading…', 'Laden…', 'Laden…');
  String get connecting => _t('Connecting…', 'Verbinden…', 'Verbinde…');
  String get commandFailed =>
      _t('Command failed', 'Opdracht mislukt', 'Befehl fehlgeschlagen');

  /// An entity state HA sends as a raw id (`not_home`, `above_horizon`):
  /// the common ones translated, the rest as they come, made readable.
  String state(String raw) {
    final hit = switch (raw) {
      'on' => on,
      'off' => off,
      'open' => stateOpen,
      'closed' => stateClosed,
      'opening' => coverOpening,
      'closing' => coverClosing,
      'unavailable' => unavailable,
      'unknown' => unknown,
      'home' => _t('Home', 'Thuis', 'Zuhause'),
      'not_home' => _t('Away', 'Afwezig', 'Abwesend'),
      'locked' => _t('Locked', 'Vergrendeld', 'Verriegelt'),
      'unlocked' => _t('Unlocked', 'Ontgrendeld', 'Entriegelt'),
      'locking' => _t('Locking', 'Vergrendelen', 'Verriegeln'),
      'unlocking' => _t('Unlocking', 'Ontgrendelen', 'Entriegeln'),
      'jammed' => _t('Jammed', 'Geblokkeerd', 'Blockiert'),
      'idle' => _t('Idle', 'Inactief', 'Inaktiv'),
      'playing' => mediaPlaying,
      'paused' => mediaPaused,
      'standby' => _t('Standby', 'Stand-by', 'Standby'),
      'buffering' => _t('Buffering', 'Bufferen', 'Puffern'),
      'cleaning' => _t('Cleaning', 'Schoonmaken', 'Reinigt'),
      'docked' => _t('Docked', 'Gedockt', 'Angedockt'),
      'returning' => _t('Returning', 'Keert terug', 'Kehrt zurück'),
      'charging' => _t('Charging', 'Opladen', 'Lädt'),
      'above_horizon' => _t('Above horizon', 'Boven de horizon', 'Über dem Horizont'),
      'below_horizon' => _t('Below horizon', 'Onder de horizon', 'Unter dem Horizont'),
      _ => null,
    };
    if (hit != null) return hit;
    return raw.isEmpty
        ? raw
        : raw[0].toUpperCase() + raw.substring(1).replaceAll('_', ' ');
  }

  // ---- dates ---------------------------------------------------------------

  /// Monday = 0, as `DateTime.weekday - 1`.
  List<String> get daysShort => switch (lang) {
    Lang.en => const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
    Lang.nl => const ['ma', 'di', 'wo', 'do', 'vr', 'za', 'zo'],
    Lang.de => const ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'],
  };
  List<String> get daysLong => switch (lang) {
    Lang.en => const ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'],
    Lang.nl => const ['maandag', 'dinsdag', 'woensdag', 'donderdag', 'vrijdag', 'zaterdag', 'zondag'],
    Lang.de => const ['Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag', 'Sonntag'],
  };
  List<String> get months => switch (lang) {
    Lang.en => const [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December',
    ],
    Lang.nl => const [
      'januari', 'februari', 'maart', 'april', 'mei', 'juni',
      'juli', 'augustus', 'september', 'oktober', 'november', 'december',
    ],
    Lang.de => const [
      'Januar', 'Februar', 'März', 'April', 'Mai', 'Juni',
      'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember',
    ],
  };

  String dayShort(DateTime d) => daysShort[d.weekday - 1];

  /// The clock's date line: `Monday 13 November`, `maandag 13 november`,
  /// `Montag, 13. November`.
  String longDate(DateTime d) {
    final day = daysLong[d.weekday - 1], month = months[d.month - 1];
    return switch (lang) {
      Lang.en || Lang.nl => '$day ${d.day} $month',
      Lang.de => '$day, ${d.day}. $month',
    };
  }

  // ---- light ---------------------------------------------------------------

  String get lightLow => _t('Low', 'Laag', 'Niedrig');
  String get lightMid => _t('Mid', 'Half', 'Mittel');
  String get lightFull => _t('Full', 'Vol', 'Voll');

  // ---- cover ---------------------------------------------------------------

  String get coverOpening => _t('Opening', 'Gaat open', 'Öffnet');
  String get coverClosing => _t('Closing', 'Gaat dicht', 'Schließt');
  String coverPercentOpen(int pct) =>
      _t('$pct% open', '$pct% open', '$pct% offen');
  String get coverOpen => _t('Open', 'Openen', 'Öffnen');
  String get coverStop => _t('Stop', 'Stop', 'Stopp');
  String get coverClose => _t('Close', 'Sluiten', 'Schließen');
  String get coverPresetOpen => _t('Open', 'Open', 'Offen');
  String get coverPresetHalf => _t('Half', 'Half', 'Halb');
  String get coverPresetShut => _t('Shut', 'Dicht', 'Zu');

  // ---- climate -------------------------------------------------------------

  String? hvacMode(String mode) => switch (mode) {
    'off' => off,
    'heat' => _t('Heat', 'Verwarmen', 'Heizen'),
    'cool' => _t('Cool', 'Koelen', 'Kühlen'),
    'heat_cool' || 'auto' => _t('Auto', 'Auto', 'Auto'),
    'dry' => _t('Dry', 'Drogen', 'Trocknen'),
    'fan_only' => _t('Fan', 'Ventilator', 'Lüfter'),
    _ => null,
  };

  /// What the thermostat is doing right now (`hvac_action`).
  String hvacAction(String action) => switch (action) {
    'heating' => _t('Heating', 'Verwarmt', 'Heizt'),
    'cooling' => _t('Cooling', 'Koelt', 'Kühlt'),
    'drying' => _t('Drying', 'Droogt', 'Trocknet'),
    'fan' => _t('Fan', 'Ventileert', 'Lüftet'),
    'idle' => _t('Idle', 'Inactief', 'Leerlauf'),
    'off' => off,
    'preheating' => _t('Preheating', 'Voorverwarmen', 'Vorheizen'),
    'defrosting' => _t('Defrosting', 'Ontdooien', 'Abtauen'),
    _ => state(action),
  };
  String climateNow(String temp) => _t('Now $temp°', 'Nu $temp°', 'Jetzt $temp°');
  String get climateEco => _t('Eco', 'Eco', 'Eco');
  String get climateDay => _t('Day', 'Dag', 'Tag');
  String get climateWarm => _t('Warm', 'Warm', 'Warm');

  // ---- media ---------------------------------------------------------------

  String get mediaNothing => _t('Nothing playing', 'Er speelt niets', 'Keine Wiedergabe');
  String get mediaPaused => _t('Paused', 'Gepauzeerd', 'Pausiert');
  String get mediaPlaying => _t('Playing', 'Speelt af', 'Wiedergabe');
  String get mediaPrevious => _t('Previous', 'Vorige', 'Zurück');
  String get mediaPause => _t('Pause', 'Pauze', 'Pause');
  String get mediaPlay => _t('Play', 'Afspelen', 'Abspielen');
  String get mediaNext => _t('Next', 'Volgende', 'Weiter');
  String get mediaStop => _t('Stop', 'Stop', 'Stopp');

  // ---- status --------------------------------------------------------------

  String get detected => _t('Detected', 'Gedetecteerd', 'Erkannt');
  String get clear => _t('Clear', 'Vrij', 'Frei');
  String get wet => _t('Wet', 'Nat', 'Nass');
  String get dry => _t('Dry', 'Droog', 'Trocken');
  String get problem => _t('Problem', 'Probleem', 'Problem');
  String get ok => _t('OK', 'OK', 'OK');
  String get allClear => _t('All clear', 'Alles in orde', 'Alles in Ordnung');

  // ---- buttons, camera -----------------------------------------------------

  String get tapAgain => _t('Tap again', 'Tik nogmaals', 'Erneut tippen');
  String get run => _t('Run', 'Uitvoeren', 'Ausführen');
  String get cameraUnavailable =>
      _t('Camera unavailable', 'Camera niet beschikbaar', 'Kamera nicht verfügbar');
  String get noPicture => _t('No picture', 'Geen beeld', 'Kein Bild');

  // ---- alarm ---------------------------------------------------------------

  String alarmMode(String key) => switch (key) {
    'home' => _t('Home', 'Thuis', 'Zuhause'),
    'away' => _t('Away', 'Afwezig', 'Abwesend'),
    'night' => _t('Night', 'Nacht', 'Nacht'),
    'custom_bypass' => _t('Bypass', 'Overbruggen', 'Überbrücken'),
    'vacation' => _t('Vacation', 'Vakantie', 'Urlaub'),
    _ => state(key),
  };

  /// The keypad title for arming in a mode: `Arm away`, `Afwezig
  /// inschakelen`, `Abwesend aktivieren`.
  String armIn(String key) {
    final m = alarmMode(key);
    return _t('Arm ${m.toLowerCase()}', '$m inschakelen', '$m aktivieren');
  }

  String get disarm => _t('Disarm', 'Uitschakelen', 'Deaktivieren');
  String get disarmed => _t('Disarmed', 'Uitgeschakeld', 'Deaktiviert');
  String get armedHome => _t('Armed home', 'Ingeschakeld thuis', 'Aktiviert zuhause');
  String get armedAway => _t('Armed away', 'Ingeschakeld afwezig', 'Aktiviert abwesend');
  String get armedNight => _t('Armed night', 'Ingeschakeld nacht', 'Aktiviert Nacht');
  String get armedVacation =>
      _t('Armed vacation', 'Ingeschakeld vakantie', 'Aktiviert Urlaub');
  String get armedBypass =>
      _t('Armed (bypass)', 'Ingeschakeld (overbrugd)', 'Aktiviert (überbrückt)');
  String get arming => _t('Arming…', 'Inschakelen…', 'Aktiviere…');
  String get disarming => _t('Disarming…', 'Uitschakelen…', 'Deaktiviere…');
  String get pending => _t('Pending…', 'In afwachting…', 'Ausstehend…');
  String get triggered => _t('TRIGGERED', 'ALARM', 'ALARM');
  String changedBy(String who) => _t('by $who', 'door $who', 'von $who');
  String get enterCode => _t('Enter the code', 'Voer de code in', 'Code eingeben');
  String get wrongCode => _t('Wrong code', 'Verkeerde code', 'Falscher Code');

  // ---- weather -------------------------------------------------------------

  /// HA's condition ids in a sentence. Anything not listed reads fine with
  /// its dashes turned into spaces.
  String condition(String id) => switch (id) {
    'clear-night' => _t('Clear', 'Helder', 'Klar'),
    'cloudy' => _t('Cloudy', 'Bewolkt', 'Bewölkt'),
    'exceptional' => _t('Severe', 'Extreem weer', 'Unwetter'),
    'fog' => _t('Fog', 'Mist', 'Nebel'),
    'hail' => _t('Hail', 'Hagel', 'Hagel'),
    'lightning' => _t('Lightning', 'Onweer', 'Gewitter'),
    'lightning-rainy' => _t('Thunder, rain', 'Onweer, regen', 'Gewitter, Regen'),
    'partlycloudy' => _t('Partly cloudy', 'Half bewolkt', 'Teilweise bewölkt'),
    'pouring' => _t('Heavy rain', 'Stortregen', 'Starkregen'),
    'rainy' => _t('Rainy', 'Regen', 'Regen'),
    'snowy' => _t('Snowy', 'Sneeuw', 'Schnee'),
    'snowy-rainy' => _t('Sleet', 'Natte sneeuw', 'Schneeregen'),
    'sunny' => _t('Sunny', 'Zonnig', 'Sonnig'),
    'windy' || 'windy-variant' => _t('Windy', 'Winderig', 'Windig'),
    _ => state(id.replaceAll('-', ' ')),
  };
  String get night => _t('Night', 'Nacht', 'Nacht');

  /// The screensaver's rain line: `80% · 1.2mm rain`.
  String rainLine(String rain) => _t('$rain rain', '$rain regen', '$rain Regen');

  // ---- dashboard messages --------------------------------------------------

  String get tokenRejected => _t(
    'That token was rejected. Paste a new one.',
    'Dat token is geweigerd. Plak een nieuw token.',
    'Dieser Token wurde abgelehnt. Füge einen neuen ein.',
  );
  String noCards(String dashboard) => _t(
    'The dashboard "$dashboard" has no cards this app can draw. It needs custom:nspanel-* cards.',
    'Het dashboard "$dashboard" heeft geen kaarten die deze app kan tekenen. Het heeft custom:nspanel-* kaarten nodig.',
    'Das Dashboard "$dashboard" hat keine Karten, die diese App zeichnen kann. Es braucht custom:nspanel-* Karten.',
  );
  String get defaultDashboardShort => _t('default', 'standaard', 'Standard');
  String get theDefaultDashboard =>
      _t('the default dashboard', 'het standaarddashboard', 'das Standard-Dashboard');
  String couldNotLoad(String name, Object e) => _t(
    'Could not load $name: $e',
    'Kon $name niet laden: $e',
    '$name konnte nicht geladen werden: $e',
  );
  String notTakenOver(String path) => _t(
    'Dashboard "$path" exists but has no saved config yet - it is still the '
        'auto-generated one. In Home Assistant open it, then ⋮ → Edit dashboard → '
        'Take control, add the nspanel cards and save. This panel reloads on its own.',
    'Dashboard "$path" bestaat, maar heeft nog geen opgeslagen configuratie - het is '
        'nog het automatisch gegenereerde. Open het in Home Assistant, dan ⋮ → Dashboard '
        'bewerken → Overnemen, voeg de nspanel-kaarten toe en sla op. Dit paneel laadt '
        'vanzelf opnieuw.',
    'Das Dashboard "$path" existiert, hat aber noch keine gespeicherte Konfiguration - '
        'es ist noch das automatisch erzeugte. Öffne es in Home Assistant, dann ⋮ → '
        'Dashboard bearbeiten → Kontrolle übernehmen, füge die nspanel-Karten hinzu und '
        'speichere. Dieses Panel lädt von selbst neu.',
  );
  String get emptyForDefault => _t(
    '(empty) for the default dashboard',
    '(leeg) voor het standaarddashboard',
    '(leer) für das Standard-Dashboard',
  );
  String get dashboardsHere => _t(
    'Dashboards on this Home Assistant:',
    'Dashboards in deze Home Assistant:',
    'Dashboards in diesem Home Assistant:',
  );
  String get howToChange => _t(
    'Hold two fingers on the screen to change it.',
    'Houd twee vingers op het scherm om dit te wijzigen.',
    'Halte zwei Finger auf den Bildschirm, um das zu ändern.',
  );

  // ---- setup screen --------------------------------------------------------

  String get setupTitle =>
      _t('Connect to Home Assistant', 'Verbinden met Home Assistant', 'Mit Home Assistant verbinden');
  String get setupIntro => _t(
    'Create a long-lived access token under your profile, Security, at the '
        'bottom. It is stored on this panel only.',
    'Maak onderaan je profiel, onder Beveiliging, een langlevend toegangstoken aan. '
        'Het wordt alleen op dit paneel bewaard.',
    'Erstelle unten in deinem Profil unter Sicherheit einen langlebigen '
        'Zugangstoken. Er wird nur auf diesem Panel gespeichert.',
  );
  String get setupBothNeeded => _t(
    'Both the URL and a token are needed.',
    'Zowel de URL als een token is nodig.',
    'Sowohl die URL als auch ein Token werden benötigt.',
  );
  String get setupUrl => _t('Home Assistant URL', 'Home Assistant-URL', 'Home Assistant-URL');
  String get setupToken =>
      _t('Long-lived access token', 'Langlevend toegangstoken', 'Langlebiger Zugangstoken');
  String get setupNewToken => _t(
    'New token (leave empty to keep the current one)',
    'Nieuw token (leeg laten om het huidige te houden)',
    'Neuer Token (leer lassen, um den aktuellen zu behalten)',
  );
  String get setupDashboard => _t(
    'Dashboard (url path, empty = default)',
    'Dashboard (url-pad, leeg = standaard)',
    'Dashboard (URL-Pfad, leer = Standard)',
  );
  String get setupExample => _t('e.g.', 'bijv.', 'z. B.');
  String get setupDeviceName => _t(
    'Device name in Home Assistant',
    'Apparaatnaam in Home Assistant',
    'Gerätename in Home Assistant',
  );
  String get setupMqtt => _t(
    'MQTT broker (host or host:port, empty = no device)',
    'MQTT-broker (host of host:poort, leeg = geen apparaat)',
    'MQTT-Broker (Host oder Host:Port, leer = kein Gerät)',
  );
  String get setupMqttUser => _t('MQTT user', 'MQTT-gebruiker', 'MQTT-Benutzer');
  String get setupMqttPass => _t('MQTT password', 'MQTT-wachtwoord', 'MQTT-Passwort');
  String get setupPassKept =>
      _t('password (kept)', 'wachtwoord (bewaard)', 'Passwort (beibehalten)');
  String setupTextSize(int min, int max) => _t(
    'Text size in % ($min-$max)',
    'Tekstgrootte in % ($min-$max)',
    'Textgröße in % ($min-$max)',
  );
  String get setupConnect => _t('Connect', 'Verbinden', 'Verbinden');
  String get setupNoProximity => _t(
    'No proximity sensor on this device.',
    'Geen nabijheidssensor op dit apparaat.',
    'Kein Näherungssensor auf diesem Gerät.',
  );
  String setupProximityNow(String v) => _t(
    'Proximity sensor now: $v',
    'Nabijheidssensor nu: $v',
    'Näherungssensor jetzt: $v',
  );
  String get setupApp => _t('App', 'App', 'App');
  String setupUpdateTo(String v) => _t('Update to $v', 'Bijwerken naar $v', 'Auf $v aktualisieren');
  String get setupCheckUpdates =>
      _t('Check for updates', 'Zoeken naar updates', 'Nach Updates suchen');
}

/// The panel's language, for every widget under it. Sits above the navigator
/// and the screensaver overlay, so sheets and the saver clock follow too.
class L extends InheritedNotifier<ValueNotifier<Strings>> {
  const L({super.key, required ValueNotifier<Strings> strings, required super.child})
    : super(notifier: strings);

  /// The strings, and a rebuild of the caller when the language changes.
  static Strings of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<L>()?.notifier?.value ??
      Strings.en;
}
