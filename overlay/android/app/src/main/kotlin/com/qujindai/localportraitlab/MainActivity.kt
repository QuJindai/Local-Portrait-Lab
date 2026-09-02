package com.qujindai.localportraitlab

import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        configureModelDownloadChannel(flutterEngine)
        configureQnnBackendChannel(flutterEngine)
    }

    private fun configureModelDownloadChannel(flutterEngine: FlutterEngine) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            MODEL_DOWNLOAD_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val modelId = call.argument<String>("modelId")
                    val modelName = call.argument<String>("modelName")
                    val url = call.argument<String>("url")
                    val fileName = call.argument<String>("fileName")
                    val destinationRoot = call.argument<String>("destinationRoot")
                    val isArchive = call.argument<Boolean>("isArchive") ?: false
                    val requiredFiles = call.argument<List<String>>("requiredFiles")

                    if (modelId.isNullOrBlank() ||
                        modelName.isNullOrBlank() ||
                        url.isNullOrBlank() ||
                        fileName.isNullOrBlank() ||
                        destinationRoot.isNullOrBlank()
                    ) {
                        result.error("BAD_ARGS", "模型下载参数不完整", null)
                        return@setMethodCallHandler
                    }

                    val intent = Intent(this, PortraitModelDownloadService::class.java).apply {
                        action = PortraitModelDownloadService.ACTION_START
                        putExtra(PortraitModelDownloadService.EXTRA_MODEL_ID, modelId)
                        putExtra(PortraitModelDownloadService.EXTRA_MODEL_NAME, modelName)
                        putExtra(PortraitModelDownloadService.EXTRA_URL, url)
                        putExtra(PortraitModelDownloadService.EXTRA_FILE_NAME, fileName)
                        putExtra(
                            PortraitModelDownloadService.EXTRA_DESTINATION_ROOT,
                            destinationRoot,
                        )
                        putExtra(PortraitModelDownloadService.EXTRA_IS_ARCHIVE, isArchive)
                        putStringArrayListExtra(
                            PortraitModelDownloadService.EXTRA_REQUIRED_FILES,
                            ArrayList(requiredFiles ?: emptyList()),
                        )
                    }
                    startAsForegroundService(intent)
                    result.success(null)
                }

                "status" -> result.success(PortraitModelDownloadService.snapshotMap())

                "cancel" -> {
                    startService(
                        Intent(this, PortraitModelDownloadService::class.java).apply {
                            action = PortraitModelDownloadService.ACTION_CANCEL
                        },
                    )
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun configureQnnBackendChannel(flutterEngine: FlutterEngine) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            QNN_BACKEND_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    val modelId = call.argument<String>("modelId")
                    val modelDirectory = call.argument<String>("modelDirectory")
                    val backendType = call.argument<String>("backendType") ?: "sdxl"
                    val generationSize = call.argument<Int>("generationSize") ?: 1024
                    if (modelId.isNullOrBlank() || modelDirectory.isNullOrBlank()) {
                        result.error("BAD_ARGS", "本机 QNN 启动参数不完整", null)
                        return@setMethodCallHandler
                    }

                    val intent = Intent(this, PortraitQnnBackendService::class.java).apply {
                        action = PortraitQnnBackendService.ACTION_START
                        putExtra(PortraitQnnBackendService.EXTRA_MODEL_ID, modelId)
                        putExtra(
                            PortraitQnnBackendService.EXTRA_MODEL_DIRECTORY,
                            modelDirectory,
                        )
                        putExtra(PortraitQnnBackendService.EXTRA_BACKEND_TYPE, backendType)
                        putExtra(
                            PortraitQnnBackendService.EXTRA_GENERATION_SIZE,
                            generationSize,
                        )
                    }
                    startAsForegroundService(intent)
                    result.success(null)
                }

                "status" -> result.success(PortraitQnnBackendService.snapshotMap())

                "stop" -> {
                    startService(
                        Intent(this, PortraitQnnBackendService::class.java).apply {
                            action = PortraitQnnBackendService.ACTION_STOP
                        },
                    )
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun startAsForegroundService(intent: Intent) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            startForegroundService(intent)
        } else {
            startService(intent)
        }
    }

    companion object {
        private const val MODEL_DOWNLOAD_CHANNEL =
            "com.qujindai.localportraitlab/model_download"
        private const val QNN_BACKEND_CHANNEL =
            "com.qujindai.localportraitlab/qnn_backend"
    }
}
