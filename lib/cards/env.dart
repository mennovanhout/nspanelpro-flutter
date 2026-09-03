import '../config/settings.dart';
import '../ha/connection.dart';
import '../ha/states.dart';

/// What every card gets handed: the house, the socket, and where HA is.
class PanelEnv {
  const PanelEnv({required this.states, required this.conn, required this.settings, this.play});
  final HaStates states;
  final HaConnection conn;
  final Settings settings;

  /// The panel's speaker, for a card that has a sound to make: takes what an
  /// announcement takes (`sound:armed`, a URL). Null off the panel.
  final void Function(String ref)? play;
}
