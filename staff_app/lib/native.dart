import 'package:flutter/services.dart';

import 'api.dart';

/// Talks to the Android side: the background service that rings for new orders.
class Native {
  static const MethodChannel _ch = MethodChannel('acaidose/watch');

  static Future<void> startWatch(String cookie, Shop shop) async {
    try {
      await _ch.invokeMethod('start', {'cookie': cookie, 'base': shop.base, 'title': shop.name});
    } catch (_) {}
  }

  static Future<void> stopWatch() async {
    try {
      await _ch.invokeMethod('stop');
    } catch (_) {}
  }
}
