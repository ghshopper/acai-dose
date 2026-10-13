import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// The ordering site; the app uses the same API as the web pages.
const String kSite = 'https://order.acaiee.com';

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
    final m = RegExp(r'acai_sid=([^;,]*)').firstMatch(sc);
    if (m == null) return;
    final v = m.group(1) ?? '';
    final p = await SharedPreferences.getInstance();
    if (v.isEmpty || v == 'deleted') {
      _cookie = null;
      await p.remove('cookie');
    } else {
      _cookie = 'acai_sid=$v';
      await p.setString('cookie', _cookie!);
    }
  }

  Future<dynamic> get(String action, [Map<String, String>? query]) => _send(action, null, query);

  Future<dynamic> post(String action, Map<String, dynamic> body) => _send(action, body, null);

  Future<dynamic> _send(String action, Map<String, dynamic>? body, Map<String, String>? query) async {
    final params = <String, String>{'a': action};
    if (query != null) params.addAll(query);
    final uri = Uri.parse('$kSite/api/api.php').replace(queryParameters: params);
    final headers = <String, String>{'User-Agent': 'AcaiDoseOwner/1.0'};
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
  'bad_login': 'اسم المستخدم أو كلمة السر غلط',
  'too_many': 'محاولات كثيرة، انتظر شوي وجرب',
  'network': 'ما فيه اتصال بالإنترنت',
  'login_required': 'لازم تسجل دخول',
  'forbidden': 'هذا الحساب مب حساب صاحب المحل',
  'invalid_phone': 'رقم الجوال غلط',
  'customer_exists': 'هذا الرقم مسجل من قبل',
  'bad_name': 'اكتب الاسم',
  'not_found': 'ما لقيته، حدّث الصفحة',
  'invalid_items': 'فيه شي غلط في البيانات',
  'need_price': 'حط السعر قبل لا تشغل الصنف',
  'no_stamps': 'ما يمدي تنقص أكثر، الأختام صفر',
  'bad_delta': 'عدد الأختام غلط',
  'bad_amount': 'المبلغ غلط',
  'bad_pct': 'النسبة لازم بين 0 و 100',
  'bad_need': 'عدد الأختام لازم بين 2 و 30',
  'bad_username': 'اسم المستخدم إنجليزي بدون مسافات (٣ حروف أو أكثر)',
  'short_password': 'كلمة السر ٦ حروف أو أكثر',
  'username_taken': 'اسم المستخدم مأخوذ',
  'cannot_change_self': 'ما تقدر تغير حسابك من هنا',
  'server_error': 'مشكلة في السيرفر، جرب بعد شوي',
};

String errText(Object e) => kErrors[e.toString()] ?? 'صار خطأ، جرب مرة ثانية';

String ymd(DateTime d) => '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
