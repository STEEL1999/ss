package com.tuempresa.vidbrowser

import android.os.Handler
import android.os.Looper
import com.chaquo.python.PyObject
import com.chaquo.python.Python
import com.chaquo.python.android.AndroidPlatform
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {

    private val METHOD_CHANNEL = "vidbrowser/ytdlp"
    private val EVENT_CHANNEL = "vidbrowser/ytdlp_progress"

    private val executor = Executors.newCachedThreadPool()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var eventSink: EventChannel.EventSink? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        if (!Python.isStarted()) {
            Python.start(AndroidPlatform(this))
        }
        val py = Python.getInstance()
        val downloaderModule: PyObject = py.getModule("downloader")

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL)
            .setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(args: Any?, sink: EventChannel.EventSink?) {
                    eventSink = sink
                }

                override fun onCancel(args: Any?) {
                    eventSink = null
                }
            })

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "probeInfo" -> {
                        val url = call.argument<String>("url") ?: ""
                        executor.execute {
                            try {
                                val info = downloaderModule.callAttr("probe_info", url)
                                val map = pyDictToMap(info)
                                mainHandler.post { result.success(map) }
                            } catch (e: Exception) {
                                mainHandler.post { result.error("PROBE_ERROR", e.message, null) }
                            }
                        }
                    }

                    "customExtract" -> {
                        val domain = call.argument<String>("domain") ?: ""
                        val url = call.argument<String>("url") ?: ""
                        executor.execute {
                            try {
                                val res = downloaderModule.callAttr("custom_extract", domain, url)
                                val map = pyDictToMap(res)
                                mainHandler.post { result.success(map) }
                            } catch (e: Exception) {
                                mainHandler.post { result.error("EXTRACT_ERROR", e.message, null) }
                            }
                        }
                    }

                    "startDownload" -> {
                        val id = call.argument<String>("id") ?: ""
                        val url = call.argument<String>("url") ?: ""
                        val saveDir = call.argument<String>("saveDir") ?: ""
                        val title = call.argument<String>("title") ?: "video"
                        val format = call.argument<String>("format") ?: "bestvideo+bestaudio/best"

                        executor.execute {
                            val callback = ProgressCallback(id)
                            try {
                                downloaderModule.callAttr(
                                    "start_download", id, url, saveDir, title, format, callback
                                )
                            } catch (e: Exception) {
                                mainHandler.post {
                                    eventSink?.success(
                                        mapOf(
                                            "id" to id,
                                            "type" to "finished",
                                            "success" to false,
                                            "message" to (e.message ?: "Error desconocido")
                                        )
                                    )
                                }
                            }
                        }
                        result.success(null)
                    }

                    "pauseDownload" -> {
                        val id = call.argument<String>("id") ?: ""
                        downloaderModule.callAttr("pause_download", id)
                        result.success(null)
                    }

                    "resumeDownload" -> {
                        val id = call.argument<String>("id") ?: ""
                        downloaderModule.callAttr("resume_download", id)
                        result.success(null)
                    }

                    "cancelDownload" -> {
                        val id = call.argument<String>("id") ?: ""
                        downloaderModule.callAttr("cancel_download", id)
                        result.success(null)
                    }

                    else -> result.notImplemented()
                }
            }
    }

    /** Convierte un dict de Python a un Map de Kotlin (para result.success). */
    private fun pyDictToMap(obj: PyObject?): Map<String, Any?>? {
        if (obj == null || obj.toString() == "None") return null
        return obj.asMap().entries.associate { (k, v) -> k.toString() to v.toString() }
    }

    /** Callback que Python invoca (progress_callback.onProgress / onFinished)
     * y que reenvía el evento a Flutter por el EventChannel. */
    inner class ProgressCallback(private val downloadId: String) {
        fun onProgress(percent: Int, speed: String) {
            mainHandler.post {
                eventSink?.success(
                    mapOf(
                        "id" to downloadId,
                        "type" to "progress",
                        "percent" to percent,
                        "speed" to speed
                    )
                )
            }
        }

        fun onFinished(success: Boolean, message: String) {
            mainHandler.post {
                eventSink?.success(
                    mapOf(
                        "id" to downloadId,
                        "type" to "finished",
                        "success" to success,
                        "message" to message
                    )
                )
            }
        }
    }
}
