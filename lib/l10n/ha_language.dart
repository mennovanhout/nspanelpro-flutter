import '../ha/connection.dart';

/// The language Home Assistant speaks to this token's user: their profile
/// choice when they made one, else the system language. [onLanguage] hears
/// it now and again whenever the profile changes; the result unsubscribes.
///
/// HA keeps the profile choice in the frontend's per-user data under
/// `language` ({language, number_format, time_format}), null until the user
/// picks one - the browser's language is used then, and a panel has none, so
/// the system language from get_config stands in. An HA without per-user
/// data gets the system language once and no subscription (null).
Future<Future<void> Function()?> followHaLanguage(
  HaConnection conn,
  void Function(String code) onLanguage,
) async {
  String? system;
  try {
    final cfg = await conn.send({'type': 'get_config'});
    if (cfg is Map) system = cfg['language']?.toString();
  } catch (_) {
    // a dropped socket: whatever was known stands
  }
  void take(dynamic event) {
    final v = event is Map ? event['value'] : null;
    final profile = v is Map ? v['language']?.toString() : null;
    final code = (profile != null && profile.isNotEmpty) ? profile : system;
    if (code != null && code.isNotEmpty) onLanguage(code);
  }

  try {
    return await conn.subscribe({
      'type': 'frontend/subscribe_user_data',
      'key': 'language',
    }, take);
  } catch (_) {
    take(null);
    return null;
  }
}
