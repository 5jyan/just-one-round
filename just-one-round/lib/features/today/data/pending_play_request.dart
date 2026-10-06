import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

abstract interface class PendingPlayRequestStore {
  Future<String?> load(DateTime playDate);
  Future<void> save(DateTime playDate, String requestId);
  Future<void> remove(DateTime playDate, String requestId);
}

class SharedPreferencesPendingPlayRequestStore
    implements PendingPlayRequestStore {
  SharedPreferencesPendingPlayRequestStore()
    : _preferences = SharedPreferences.getInstance();

  static const storageKey = 'pending_play_request_v1';
  final Future<SharedPreferences> _preferences;

  @override
  Future<String?> load(DateTime playDate) async {
    final preferences = await _preferences;
    final raw = preferences.getString(storageKey);
    if (raw == null) return null;
    try {
      final value = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      if (value['play_date'] != _dateKey(playDate)) {
        await preferences.remove(storageKey);
        return null;
      }
      return value['request_id'] as String?;
    } catch (_) {
      await preferences.remove(storageKey);
      return null;
    }
  }

  @override
  Future<void> save(DateTime playDate, String requestId) async {
    final preferences = await _preferences;
    await preferences.setString(
      storageKey,
      jsonEncode({'play_date': _dateKey(playDate), 'request_id': requestId}),
    );
  }

  @override
  Future<void> remove(DateTime playDate, String requestId) async {
    final preferences = await _preferences;
    final saved = await load(playDate);
    if (saved == requestId) await preferences.remove(storageKey);
  }

  String _dateKey(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}
