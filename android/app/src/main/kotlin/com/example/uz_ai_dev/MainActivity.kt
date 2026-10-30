package com.uzaidev.mone_task_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val circleCamera = CircleCamera(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "circle_camera")
            .setMethodCallHandler(circleCamera)
        flutterEngine.platformViewsController.registry
            .registerViewFactory("circle_camera_preview", CirclePreviewFactory(circleCamera))
    }
}
