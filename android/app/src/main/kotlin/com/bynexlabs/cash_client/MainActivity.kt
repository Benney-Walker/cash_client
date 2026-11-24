package com.bynexlabs.cash_client

import android.annotation.SuppressLint
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // The phone's own device ID, sent at collector sign-in and refresh: the backend
        // registers one phone per collector (owner decision 2026-11-23, D36). ANDROID_ID needs
        // no permission; on Android 8+ it's fixed per signing key, user and phone, so it
        // survives reinstalling the app but differs on another phone.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "com.bynexlabs.cash_client/device")
            .setMethodCallHandler { call, result ->
                if (call.method == "androidId") {
                    @SuppressLint("HardwareIds")
                    val id = Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID)
                    if (id.isNullOrBlank()) {
                        result.error("unavailable", "No device ID on this phone", null)
                    } else {
                        result.success(id)
                    }
                } else {
                    result.notImplemented()
                }
            }
    }
}
