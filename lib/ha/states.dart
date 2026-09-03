import 'package:flutter/foundation.dart';

/// One entity's state, as Home Assistant reports it.
class HaState {
  const HaState({required this.entityId, required this.state, required this.attributes});

  factory HaState.fromJson(Map<String, dynamic> j) => HaState(
        entityId: j['entity_id'] as String,
        state: (j['state'] ?? '').toString(),
        attributes: (j['attributes'] as Map?)?.cast<String, dynamic>() ?? const {},
      );

  final String entityId;
  final String state;
  final Map<String, dynamic> attributes;

  String get domain => entityId.split('.').first;
  T? attr<T>(String key) {
    final v = attributes[key];
    return v is T ? v : null;
  }

  /// A number if the state is one, otherwise null - which is the difference
  /// between "22.4" and "unavailable" everywhere.
  num? get numeric => num.tryParse(state);
  String get unit => attr<String>('unit_of_measurement') ?? '';
  String? get deviceClass => attr<String>('device_class');
  bool get isBroken => state == 'unavailable' || state == 'unknown';
  bool get isOn => state == 'on';
  int get supportedFeatures => (attributes['supported_features'] as num?)?.toInt() ?? 0;
  bool supports(int bit) => (supportedFeatures & bit) != 0;
  double? numAttr(String key) => (attributes[key] as num?)?.toDouble();
}

/// friendly_name, or the entity id with the underscores taken out.
String friendlyName(HaState? s, String entityId) {
  final n = s?.attr<String>('friendly_name');
  if (n != null && n.isNotEmpty) return n;
  final tail = entityId.contains('.') ? entityId.split('.').last : entityId;
  return tail.replaceAll('_', ' ');
}

/// The house, with one notifier per entity that anyone has asked about.
///
/// This is the equivalent of the web cards' `prev.states[id] === hass.states[id]`
/// diff: a card listens to exactly the entities it draws, and a state change
/// anywhere else in the house does not touch it. `ValueNotifier` compares by
/// identity and every update is a new HaState, so a changed entity always
/// notifies and an untouched one never does.
class HaStates {
  final Map<String, HaState> _all = {};
  final Map<String, ValueNotifier<HaState?>> _notifiers = {};

  HaState? get(String id) => _all[id];
  Iterable<String> get ids => _all.keys;

  ValueNotifier<HaState?> listen(String id) =>
      _notifiers.putIfAbsent(id, () => ValueNotifier<HaState?>(_all[id]));

  void replaceAll(Map<String, HaState> states) {
    _all
      ..clear()
      ..addAll(states);
    for (final e in _notifiers.entries) {
      e.value.value = _all[e.key];
    }
  }

  void update(String id, HaState? s) {
    if (s == null) {
      _all.remove(id);
    } else {
      _all[id] = s;
    }
    _notifiers[id]?.value = s;
  }
}
