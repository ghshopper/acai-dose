import 'dart:async';

import 'package:flutter/foundation.dart';

import 'api.dart';

/// Polls the website orders every 5 seconds for the whole app (orders screen + POS banner).
class OrdersController extends ChangeNotifier {
  OrdersController({required this.onLoggedOut});
  final VoidCallback onLoggedOut;

  List<Map<String, dynamic>> orders = [];
  bool online = true;
  Timer? _timer;
  bool _busy = false;

  int get newCount => orders.where((o) => o['status'] == 'new').length;
  int get arrivedCount => orders.where((o) => isArrived(o)).length;

  static bool isArrived(Map<String, dynamic> o) {
    final a = o['arrived_at'];
    return a is String && a.isNotEmpty;
  }

  void start() {
    poll();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> poll() async {
    if (_busy) return;
    _busy = true;
    try {
      final r = await Api.I.get('active_orders');
      orders = (r as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();
      online = true;
    } on ApiError catch (e) {
      online = false;
      if (e.code == 'login_required') onLoggedOut();
    } finally {
      _busy = false;
    }
    notifyListeners();
  }

  /// Returns null when it worked, otherwise an error message.
  Future<String?> setStatus(int id, String status, {String? payment}) async {
    try {
      final body = <String, dynamic>{'id': id, 'status': status};
      if (payment != null) body['payment'] = payment;
      await Api.I.post('order_status', body);
      await poll();
      return null;
    } catch (e) {
      return errText(e);
    }
  }
}
