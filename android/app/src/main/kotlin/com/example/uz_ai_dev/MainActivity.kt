package com.uzaidev.mone_task_app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        createDemandChannel()
    }

    // Android 8+: ovoz va ekranda ko'rinish kanal darajasida belgilanadi.
    // Nomi backend/push.go dagi demandPushChannel bilan bir xil.
    private fun createDemandChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            "task_demands",
            "Требования ревизора",
            NotificationManager.IMPORTANCE_HIGH,
        )
        getSystemService(NotificationManager::class.java)
            .createNotificationChannel(channel)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val circleCamera = CircleCamera(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "circle_camera")
            .setMethodCallHandler(circleCamera)
        flutterEngine.platformViewsController.registry
            .registerViewFactory("circle_camera_preview", CirclePreviewFactory(circleCamera))
    }
}
