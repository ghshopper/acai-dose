import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api.dart';

/// Last good copy of what the till needs (login, shop setup, menu), so it opens and sells with no internet.
class Cache {
  static Future<void> put(String key, dynamic value) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('cache_$key', jsonEncode(value));
  }

  static Future<dynamic> get(String key) async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString('cache_$key');
    if (s == null) return null;
    try {
      return jsonDecode(s);
    } catch (_) {
      return null;
    }
  }
}

/// A unique id for a sale or expense made on this device, so sending it twice saves it once.
String newClientId() {
  final r = Random.secure();
  return List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join();
}

/// Device time as the server stores it (the till's clock is on Oman time).
String stamp(DateTime t) {
  String two(int v) => v.toString().padLeft(2, '0');
  return '${t.year}-${two(t.month)}-${two(t.day)} ${two(t.hour)}:${two(t.minute)}:${two(t.second)}';
}

/// Sales and expenses made while offline wait here, in order, and are sent when the internet is back.
class Outbox extends ChangeNotifier {
  Outbox._();
  static final Outbox I = Outbox._();

  /// Each: {id, kind: sale|expense, body, at, label}
  List<Map<String, dynamic>> items = [];
  /// Ones the server refused (shown so staff can tell the owner): {..., error}
  List<Map<String, dynamic>> failed = [];
  bool online = true;
  bool _syncing = false;
  Timer? _timer;
  VoidCallback? onLoggedOut;
  /// Called after something was sent, so screens can refresh today's list.
  final List<VoidCallback> _onSent = [];

  int get waiting => items.length;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    List<Map<String, dynamic>> read(String k) {
      try {
        return ((jsonDecode(p.getString(k) ?? '[]') as List).map((e) => Map<String, dynamic>.from(e as Map))).toList();
      } catch (_) {
        return [];
      }
    }

    items = read('outbox');
    failed = read('outbox_failed');
    _timer ??= Timer.periodic(const Duration(seconds: 20), (_) => sync());
    notifyListeners();
    sync();
  }

  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('outbox', jsonEncode(items));
    await p.setString('outbox_failed', jsonEncode(failed));
  }

  void listen(VoidCallback f) => _onSent.add(f);
  void unlisten(VoidCallback f) => _onSent.remove(f);

  Future<void> add(String kind, Map<String, dynamic> body, String label) async {
    items.add({'id': body['client_id'], 'kind': kind, 'body': body, 'at': body['at'], 'label': label});
    online = false;
    await _save();
    notifyListeners();
  }

  void markOnline(bool v) {
    if (online == v) return;
    online = v;
    notifyListeners();
    if (v) sync();
  }

  Future<void> sync() async {
    if (_syncing || items.isEmpty) return;
    _syncing = true;
    var sent = 0;
    try {
      while (items.isNotEmpty) {
        final it = items.first;
        try {
          await Api.I.post(it['kind'] == 'expense' ? 'pos_expense' : 'pos_sale', Map<String, dynamic>.from(it['body'] as Map));
          items.removeAt(0);
          sent++;
          online = true;
        } on ApiError catch (e) {
          if (e.code == 'network' || e.code.startsWith('http_5') || e.code == 'server_error' || e.code == 'too_many') {
            online = e.code != 'network';
            break;
          }
          if (e.code == 'login_required') {
            onLoggedOut?.call();
            break;
          }
          // Refused for good (e.g. an item deleted from the menu): keep it aside for the owner, carry on with the rest
          failed.add({...it, 'error': e.code});
          items.removeAt(0);
        }
        await _save();
      }
    } finally {
      _syncing = false;
      await _save();
      notifyListeners();
      if (sent > 0) {
        for (final f in List.of(_onSent)) {
          f();
        }
      }
    }
  }

  Future<void> clearFailed() async {
    failed = [];
    await _save();
    notifyListeners();
  }
}
