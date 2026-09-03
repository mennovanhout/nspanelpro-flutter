import '../config/settings.dart';
import '../ha/connection.dart';
import '../ha/states.dart';

/// What every card gets handed: the house, the socket, and where HA is.
class PanelEnv {
  const PanelEnv({required this.states, required this.conn, required this.settings});
  final HaStates states;
  final HaConnection conn;
  final Settings settings;
}
