import 'dart:convert';

import 'package:flutter/services.dart';

/// Offline Indian states + districts (from assets JSON).
class IndiaLocations {
  IndiaLocations._();

  static List<String>? _states;
  static Map<String, List<String>>? _districtsByState;
  static Future<void>? _loading;

  static Future<void> ensureLoaded() {
    if (_states != null) return Future.value();
    return _loading ??= _load();
  }

  static Future<void> _load() async {
    final raw = await rootBundle.loadString(
      'assets/data/india_states_districts.json',
    );
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    final rows = decoded['states'] as List<dynamic>? ?? const [];
    final states = <String>[];
    final map = <String, List<String>>{};
    for (final row in rows) {
      if (row is! Map) continue;
      final name = row['state']?.toString().trim() ?? '';
      if (name.isEmpty) continue;
      final districts = (row['districts'] as List<dynamic>? ?? const [])
          .map((e) => e.toString().trim())
          .where((e) => e.isNotEmpty)
          .toList()
        ..sort();
      states.add(name);
      map[name] = districts;
    }
    states.sort();
    _states = states;
    _districtsByState = map;
  }

  static List<String> get states => List.unmodifiable(_states ?? const []);

  static List<String> districtsFor(String state) {
    final key = _resolveStateKey(state);
    if (key == null) return const [];
    return List.unmodifiable(_districtsByState![key] ?? const []);
  }

  static List<String> filterStates(String query) {
    final q = query.trim().toLowerCase();
    final all = states;
    if (q.isEmpty) return all;
    return all.where((s) => s.toLowerCase().contains(q)).toList();
  }

  static List<String> filterDistricts(String state, String query) {
    final q = query.trim().toLowerCase();
    final all = districtsFor(state);
    if (q.isEmpty) return all;
    return all.where((d) => d.toLowerCase().contains(q)).toList();
  }

  static String? _resolveStateKey(String state) {
    final trimmed = state.trim();
    if (trimmed.isEmpty || _districtsByState == null) return null;
    if (_districtsByState!.containsKey(trimmed)) return trimmed;
    final lower = trimmed.toLowerCase();
    for (final key in _districtsByState!.keys) {
      if (key.toLowerCase() == lower) return key;
    }
    return null;
  }
}
