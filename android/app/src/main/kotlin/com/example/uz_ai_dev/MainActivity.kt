package com.uzaidev.mone_task_app

import android.content.Intent
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val telegramPackages = listOf(
        "org.telegram.messenger",
        "org.telegram.messenger.web",
        "org.thunderdog.challegram",
    )

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // Hisobot faylini to'g'ridan-to'g'ri Telegram'ga yuborish
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "mone/telegram_share")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isInstalled" -> result.success(installedTelegram() != null)
                    "shareFile" -> {
                        val path = call.argument<String>("path")
                        val text = call.argument<String>("text")
                        val mime = call.argument<String>("mime") ?: "*/*"
                        val pkg = installedTelegram()
                        if (path == null || pkg == null) {
                            result.success(false)
                            return@setMethodCallHandler
                        }
                        try {
                            val uri = FileProvider.getUriForFile(
                                this, "$packageName.report_provider", File(path)
                            )
                            val intent = Intent(Intent.ACTION_SEND).apply {
                                type = mime
                                setPackage(pkg)
                                putExtra(Intent.EXTRA_STREAM, uri)
                                if (text != null) putExtra(Intent.EXTRA_TEXT, text)
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }
                            startActivity(intent)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("share_failed", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun installedTelegram(): String? = telegramPackages.firstOrNull {
        try {
            packageManager.getPackageInfo(it, 0)
            true
        } catch (_: Exception) {
            false
        }
    }
}
