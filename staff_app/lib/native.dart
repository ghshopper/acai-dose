import 'package:flutter/services.dart';

/// Talks to the Android side: the background service that rings for new orders.
class Native {
  static const MethodChannel _ch = MethodChannel('acaidose/watch');

  static Future<void> startWatch(String cookie) async {
    try {
      await _ch.invokeMethod('start', {'cookie': cookie});
    } catch (_) {}
  }

  static Future<void> stopWatch() async {
    try {
      await _ch.invokeMethod('stop');
    } catch (_) {}
  }
}
