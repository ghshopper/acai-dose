import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// The ordering site; the app uses the same API as the web pages.
const String kSite = 'https://order.acaiee.com';

/// The two shops this app can run. Karak Dose lives under /karak on the same site with its own menu, staff and sales.
class Shop {
  const Shop(this.id, this.base, this.name, this.cookieName);
  final String id; // acai | karak
  final String base; // '' or '/karak'
  final String name;
  final String cookieName;
  static const acai = Shop('acai', '', 'Açaí Dose', 'acai_sid');
  static const karak = Shop('karak', '/karak', 'Karak Dose', 'kd_sid');
  static Shop byId(String? id) => id == 'karak' ? karak : acai;
  bool get isKarak => id == 'karak';
}

/// What the server says about this shop after login: delivery apps, menu sections, size names.
class ShopConfig {
  ShopConfig({this.channels = const [], this.cats = const [], this.sizes = const {}});
  final List<Map<String, dynamic>> channels; // [{k, en, ar}]
  final List<Map<String, dynamic>> cats; // [{k, en, ar}]
  final Map<String, Map<String, dynamic>> sizes; // small -> {en, ar}
  static ShopConfig I = ShopConfig();

  static Future<void> load() async {
    try {
      final r = Map<String, dynamic>.from(await Api.I.get('pos_config') as Map);
      List<Map<String, dynamic>> list(dynamic v) => ((v as List?) ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      I = ShopConfig(
        channels: list(r['channels']),
        cats: list(r['cats']),
        sizes: ((r['sizes'] as Map?) ?? {}).map((k, v) => MapEntry('$k', Map<String, dynamic>.from(v as Map))),
      );
    } catch (_) {
      // Older server: the three delivery apps it always had
      I = ShopConfig(channels: [
        {'k': 'talabat', 'en': 'Talabat', 'ar': 'طلبات'},
        {'k': 'snoonu', 'en': 'Snoonu', 'ar': 'سنونو'},
        {'k': 'khedmah', 'en': 'Khedmah', 'ar': 'خدمة'},
      ]);
    }
  }

  String channelName(String k) {
    for (final c in channels) {
      if (c['k'] == k) return '${c['en']}';
    }
    return k;
  }

  String sizeName(String? k) => k == null ? '' : '${sizes[k]?['en'] ?? k}';
}

class ApiError implements Exception {
  ApiError(this.code);
  final String code;
  @override
  String toString() => code;
}

/// Small client for api/api.php that keeps the login session cookie.
class Api {
  Api._();
  static final Api I = Api._();

  String? _cookie;
  String? get cookie => _cookie;
  /// Fixed when the app is built: the Açaí Dose app and the Karak Dose app are separate installs.
  final Shop shop = Shop.byId(const String.fromEnvironment('SHOP', defaultValue: 'acai'));

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    _cookie = p.getString('cookie');
  }

  Future<void> clearSession() async {
    _cookie = null;
    final p = await SharedPreferences.getInstance();
    await p.remove('cookie');
  }

  Future<void> _keepCookie(http.Response r) async {
    final sc = r.headers['set-cookie'];
    if (sc == null) return;
    final m = RegExp('${shop.cookieName}=([^;,]*)').firstMatch(sc);
    if (m == null) return;
    final v = m.group(1) ?? '';
    final p = await SharedPreferences.getInstance();
    if (v.isEmpty || v == 'deleted') {
      _cookie = null;
      await p.remove('cookie');
    } else {
      _cookie = '${shop.cookieName}=$v';
      await p.setString('cookie', _cookie!);
    }
  }

  Future<dynamic> get(String action, [Map<String, String>? query]) => _send(action, null, query);

  Future<dynamic> post(String action, Map<String, dynamic> body) => _send(action, body, null);

  Future<dynamic> _send(String action, Map<String, dynamic>? body, Map<String, String>? query) async {
    final params = <String, String>{'a': action};
    if (query != null) params.addAll(query);
    final uri = Uri.parse('$kSite${shop.base}/api/api.php').replace(queryParameters: params);
    final headers = <String, String>{'User-Agent': 'AcaiDoseApp/2.0'};
    if (_cookie != null) headers['Cookie'] = _cookie!;
    http.Response r;
    try {
      if (body == null) {
        r = await http.get(uri, headers: headers).timeout(const Duration(seconds: 12));
      } else {
        headers['Content-Type'] = 'application/json';
        r = await http.post(uri, headers: headers, body: jsonEncode(body)).timeout(const Duration(seconds: 12));
      }
    } catch (_) {
      throw ApiError('network');
    }
    await _keepCookie(r);
    dynamic data;
    try {
      data = jsonDecode(utf8.decode(r.bodyBytes));
    } catch (_) {
      data = null;
    }
    if (r.statusCode >= 400) {
      final err = (data is Map && data['error'] is String) ? data['error'] as String : 'http_${r.statusCode}';
      throw ApiError(err);
    }
    return data;
  }
}

String money(dynamic v) => ((v as num?) ?? 0).toDouble().toStringAsFixed(3);

const Map<String, String> kErrors = {
  'bad_login': 'Wrong username or password',
  'too_many': 'Too many attempts, wait a minute',
  'network': 'No internet connection',
  'login_required': 'Please log in again',
  'forbidden': 'No permission',
  'void_window': 'You can only void your own sale within 15 minutes',
  'invalid_phone': 'Customer mobile must be 8 digits',
  'no_free_cup': 'This customer has no free cup',
  'sold_out': 'An item in this sale is sold out',
  'invalid_car': 'Write the car plate',
};

String errText(Object e) => kErrors[e.toString()] ?? 'Something went wrong, try again';
