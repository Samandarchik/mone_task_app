package com.uzaidev.mone_task_app

import android.Manifest
import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.PackageManager
import android.util.Rational
import android.view.View
import androidx.camera.core.Camera
import androidx.camera.core.CameraSelector
import androidx.camera.core.Preview
import androidx.camera.core.UseCaseGroup
import androidx.camera.core.ViewPort
import androidx.camera.lifecycle.ProcessCameraProvider
import androidx.camera.video.FallbackStrategy
import androidx.camera.video.FileOutputOptions
import androidx.camera.video.Quality
import androidx.camera.video.QualitySelector
import androidx.camera.video.Recorder
import androidx.camera.video.Recording
import androidx.camera.video.VideoCapture
import androidx.camera.video.VideoRecordEvent
import androidx.camera.view.PreviewView
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import java.io.File

/**
 * Aylana video kamerasi. ViewPort 1:1 bo'lgani uchun video telefonda kvadrat
 * bo'lib yoziladi: aylanada ko'ringan joyning o'zi faylga tushadi.
 *
 * Bitta yozuv bir marta to'xtatiladi: to'xtatish so'rovidan keyin [recording]
 * darhol null bo'ladi, shu sabab kech kelgan pauza xato bermaydi.
 */
class CircleCamera(private val activity: FlutterActivity) : MethodChannel.MethodCallHandler {
    private companion object {
        const val VIDEO_BITRATE = 900_000
    }

    private val executor = ContextCompat.getMainExecutor(activity)
    private var previewView: PreviewView? = null
    private var provider: ProcessCameraProvider? = null
    private var camera: Camera? = null
    private var videoCapture: VideoCapture<Recorder>? = null
    private var recording: Recording? = null

    /** Kech kelgan Finalize keyingi yozuvni tegmasligi uchun: faqat oxirgisi hisob */
    private var recordingToken = 0

    private var wantOpen = false
    private var useFront = false

    private var openResult: MethodChannel.Result? = null
    private var startResult: MethodChannel.Result? = null
    private var stopResult: MethodChannel.Result? = null

    /** Yozuv o'zicha tugagan (kamera uzilgan), to'xtatish so'rovi hali kelmagan */
    private var finishedFile: File? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "open" -> {
                useFront = call.argument<Boolean>("front") ?: false
                wantOpen = true
                openResult?.success(null)
                openResult = result
                bind()
            }
            "close" -> {
                close()
                result.success(null)
            }
            "start" -> start(result)
            "stop" -> stop(result)
            "pause" -> {
                recording?.pause()
                result.success(null)
            }
            "resume" -> {
                recording?.resume()
                result.success(null)
            }
            "setZoom" -> {
                camera?.cameraControl?.setZoomRatio(
                    (call.argument<Double>("zoom") ?: 1.0).toFloat(),
                )
                result.success(null)
            }
            "zoomRange" -> {
                val zoom = camera?.cameraInfo?.zoomState?.value
                result.success(
                    listOf(
                        (zoom?.minZoomRatio ?: 1f).toDouble(),
                        (zoom?.maxZoomRatio ?: 4f).toDouble(),
                    ),
                )
            }
            else -> result.notImplemented()
        }
    }

    fun attach(view: PreviewView) {
        previewView = view
        bind()
    }

    fun detach(view: PreviewView) {
        if (previewView === view) previewView = null
    }

    private fun bind() {
        val view = previewView ?: return
        if (!wantOpen) return
        val cameraProvider = provider
        if (cameraProvider == null) {
            val future = ProcessCameraProvider.getInstance(activity)
            future.addListener({
                try {
                    provider = future.get()
                    bind()
                } catch (e: Exception) {
                    failOpen(e)
                }
            }, executor)
            return
        }

        try {
            cameraProvider.unbindAll()
            val preview = Preview.Builder().build().also {
                it.surfaceProvider = view.surfaceProvider
            }
            val recorder = Recorder.Builder()
                .setQualitySelector(
                    QualitySelector.from(
                        Quality.SD,
                        FallbackStrategy.lowerQualityOrHigherThan(Quality.SD),
                    ),
                )
                .setTargetVideoEncodingBitRate(VIDEO_BITRATE)
                .build()
            val capture = VideoCapture.withOutput(recorder)
            @Suppress("DEPRECATION")
            val rotation = activity.windowManager.defaultDisplay.rotation
            capture.targetRotation = rotation
            val group = UseCaseGroup.Builder()
                .setViewPort(ViewPort.Builder(Rational(1, 1), rotation).build())
                .addUseCase(preview)
                .addUseCase(capture)
                .build()
            val selector = if (useFront) {
                CameraSelector.DEFAULT_FRONT_CAMERA
            } else {
                CameraSelector.DEFAULT_BACK_CAMERA
            }
            camera = cameraProvider.bindToLifecycle(activity, selector, group)
            videoCapture = capture
            openResult?.success(null)
            openResult = null
            startResult?.let { pending ->
                startResult = null
                start(pending)
            }
        } catch (e: Exception) {
            failOpen(e)
        }
    }

    private fun failOpen(e: Exception) {
        openResult?.error("camera_open_failed", e.message, null)
        openResult = null
        startResult?.error("camera_open_failed", e.message, null)
        startResult = null
    }

    @SuppressLint("MissingPermission")
    private fun start(result: MethodChannel.Result) {
        if (recording != null) {
            result.error("already_recording", "Запись уже идёт", null)
            return
        }
        val capture = videoCapture
        if (capture == null) {
            // Kamera ulanishi tugagach bind() o'zi boshlaydi
            startResult = result
            return
        }
        finishedFile = null
        val file = File(activity.cacheDir, "circle_${System.currentTimeMillis()}.mp4")
        var pending = capture.output.prepareRecording(
            activity,
            FileOutputOptions.Builder(file).build(),
        )
        if (ContextCompat.checkSelfPermission(activity, Manifest.permission.RECORD_AUDIO) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            pending = pending.withAudioEnabled()
        }
        startResult = result
        val token = ++recordingToken
        recording = pending.start(executor) { event ->
            if (token != recordingToken) return@start
            when (event) {
                is VideoRecordEvent.Start -> {
                    startResult?.success(null)
                    startResult = null
                }
                is VideoRecordEvent.Finalize -> onFinalized(event, file)
            }
        }
    }

    private fun stop(result: MethodChannel.Result) {
        val active = recording
        if (active == null) {
            val finished = finishedFile
            finishedFile = null
            if (finished != null) {
                result.success(finished.path)
            } else {
                result.error("no_recording", "Запись не идёт", null)
            }
            return
        }
        stopResult = result
        recording = null
        active.stop()
    }

    private fun onFinalized(event: VideoRecordEvent.Finalize, file: File) {
        recording = null
        // ERROR_SOURCE_INACTIVE kabi xatolarda ham fayl odatda yaroqli
        val saved = file.exists() && file.length() > 0 &&
            event.error != VideoRecordEvent.Finalize.ERROR_NO_VALID_DATA
        startResult?.error("record_failed", "Запись не началась (${event.error})", null)
        startResult = null
        val pending = stopResult
        stopResult = null
        when {
            pending == null -> if (saved) finishedFile = file
            saved -> pending.success(file.path)
            else -> pending.error("record_failed", "Видео не сохранено (${event.error})", null)
        }
    }

    private fun close() {
        wantOpen = false
        recordingToken++
        startResult?.error("camera_closed", "Камера закрыта", null)
        startResult = null
        stopResult?.error("camera_closed", "Камера закрыта", null)
        stopResult = null
        recording?.stop()
        recording = null
        finishedFile = null
        videoCapture = null
        camera = null
        provider?.unbindAll()
    }
}

class CirclePreviewFactory(private val circleCamera: CircleCamera) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        // COMPATIBLE: TextureView, Flutter aylana kesimi ishlashi uchun
        val view = PreviewView(context).apply {
            implementationMode = PreviewView.ImplementationMode.COMPATIBLE
            scaleType = PreviewView.ScaleType.FILL_CENTER
        }
        circleCamera.attach(view)
        return object : PlatformView {
            override fun getView(): View = view
            override fun dispose() = circleCamera.detach(view)
        }
    }
}
