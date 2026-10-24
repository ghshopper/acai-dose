package com.acaidose.staff

import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** Keeps the screen on and runs the background order alarm for the Flutter app. */
class MainActivity : FlutterActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission("android.permission.POST_NOTIFICATIONS") != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(arrayOf("android.permission.POST_NOTIFICATIONS"), 1)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "acaidose/watch").setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    OrderWatchService.saveCookie(this, call.argument<String>("cookie") ?: "")
                    OrderWatchService.saveShop(this, call.argument<String>("base") ?: "", call.argument<String>("title") ?: "")
                    OrderWatchService.start(this)
                    result.success(null)
                }
                "stop" -> {
                    OrderWatchService.saveCookie(this, "")
                    stopService(Intent(this, OrderWatchService::class.java))
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onResume() {
        super.onResume()
        OrderWatchService.appVisible = true
        OrderWatchService.start(this)   // restarts it if someone pressed Stop on the notification
    }

    override fun onPause() {
        super.onPause()
        OrderWatchService.appVisible = false
    }
}
