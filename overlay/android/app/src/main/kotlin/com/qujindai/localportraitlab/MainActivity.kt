package com.qujindai.localportraitlab

import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val galleryExecutor = Executors.newSingleThreadExecutor()
    private val qnnExecutor = Executors.newSingleThreadExecutor()
    private val identityExecutor = Executors.newSingleThreadExecutor()
    private val identityRuntime by lazy { PortraitIdentityRuntime(applicationContext) }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        configureModelDownloadChannel(flutterEngine)
        configureQnnBackendChannel(flutterEngine)
        configureIdentityLockChannel(flutterEngine)
        configureGalleryChannel(flutterEngine)
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
                    val requestToken = call.argument<String>("requestToken")
                    if (modelId.isNullOrBlank() ||
                        modelDirectory.isNullOrBlank() ||
                        requestToken.isNullOrBlank()
                    ) {
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
                        putExtra(
                            PortraitQnnBackendService.EXTRA_REQUEST_TOKEN,
                            requestToken,
                        )
                    }
                    startAsForegroundService(intent)
                    result.success(null)
                }

                "status" -> result.success(PortraitQnnBackendService.snapshotMap())

                "health" -> {
                    val modelId = call.argument<String>("modelId")
                    qnnExecutor.execute {
                        val healthy = try {
                            PortraitQnnBackendService.health(modelId)
                        } catch (_: Exception) {
                            false
                        }
                        runOnUiThread { result.success(healthy) }
                    }
                }

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

    private fun configureIdentityLockChannel(flutterEngine: FlutterEngine) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            IDENTITY_LOCK_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "status" -> result.success(identityRuntime.status())

                "prepareModels" -> identityExecutor.execute {
                    try {
                        // prepare() performs installation and real source identity extraction;
                        // model-only prewarming is intentionally not exposed as fake readiness.
                        runOnUiThread { result.success(identityRuntime.status()) }
                    } catch (error: Exception) {
                        runOnUiThread {
                            result.error("IDENTITY_PREPARE_FAILED", error.message, null)
                        }
                    }
                }

                "prepare" -> {
                    val sourcePath = call.argument<String>("sourcePath")
                    if (sourcePath.isNullOrBlank()) {
                        result.error("BAD_ARGS", "身份分析缺少源照片", null)
                        return@setMethodCallHandler
                    }
                    identityExecutor.execute {
                        try {
                            val payload = identityRuntime.prepare(sourcePath)
                            runOnUiThread { result.success(payload) }
                        } catch (error: Exception) {
                            runOnUiThread {
                                result.error(
                                    "IDENTITY_PREPARE_FAILED",
                                    error.message ?: error.javaClass.simpleName,
                                    null,
                                )
                            }
                        }
                    }
                }

                "lock" -> {
                    val token = call.argument<String>("token")
                    val styledPath = call.argument<String>("styledPath")
                    val strength = call.argument<Number>("strength")?.toDouble() ?: 0.88
                    val minSimilarity =
                        call.argument<Number>("minSimilarity")?.toDouble() ?: 0.40
                    val minImprovement =
                        call.argument<Number>("minImprovement")?.toDouble() ?: 0.08
                    if (token.isNullOrBlank() || styledPath.isNullOrBlank()) {
                        result.error("BAD_ARGS", "身份锁定参数不完整", null)
                        return@setMethodCallHandler
                    }
                    identityExecutor.execute {
                        try {
                            val payload = identityRuntime.lock(
                                token = token,
                                styledPath = styledPath,
                                strength = strength,
                                minSimilarity = minSimilarity,
                                minImprovement = minImprovement,
                            )
                            runOnUiThread { result.success(payload) }
                        } catch (error: Exception) {
                            runOnUiThread {
                                result.error(
                                    "IDENTITY_LOCK_FAILED",
                                    error.message ?: error.javaClass.simpleName,
                                    null,
                                )
                            }
                        }
                    }
                }

                "cancel" -> identityExecutor.execute {
                    identityRuntime.cancel()
                    runOnUiThread { result.success(null) }
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun configureGalleryChannel(flutterEngine: FlutterEngine) {
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            GALLERY_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "export" -> {
                    val sourcePath = call.argument<String>("sourcePath")
                    if (sourcePath.isNullOrBlank()) {
                        result.error("BAD_ARGS", "系统相册导出路径为空", null)
                        return@setMethodCallHandler
                    }
                    galleryExecutor.execute {
                        try {
                            val receipt = PortraitGalleryExporter.export(this, sourcePath)
                            runOnUiThread { result.success(receipt) }
                        } catch (error: Exception) {
                            runOnUiThread {
                                result.error(
                                    "GALLERY_EXPORT_FAILED",
                                    error.message ?: error.javaClass.simpleName,
                                    null,
                                )
                            }
                        }
                    }
                }

                "open" -> {
                    val uri = call.argument<String>("uri")
                    val mimeType = call.argument<String>("mimeType") ?: "image/*"
                    if (uri.isNullOrBlank()) {
                        result.error("BAD_ARGS", "系统相册 URI 为空", null)
                        return@setMethodCallHandler
                    }
                    try {
                        PortraitGalleryExporter.open(this, uri, mimeType)
                        result.success(null)
                    } catch (error: Exception) {
                        result.error(
                            "GALLERY_OPEN_FAILED",
                            error.message ?: error.javaClass.simpleName,
                            null,
                        )
                    }
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

    override fun onDestroy() {
        identityRuntime.cancel()
        identityExecutor.shutdownNow()
        qnnExecutor.shutdownNow()
        galleryExecutor.shutdownNow()
        super.onDestroy()
    }

    companion object {
        private const val MODEL_DOWNLOAD_CHANNEL =
            "com.qujindai.localportraitlab/model_download"
        private const val QNN_BACKEND_CHANNEL =
            "com.qujindai.localportraitlab/qnn_backend"
        private const val IDENTITY_LOCK_CHANNEL =
            "com.qujindai.localportraitlab/identity_lock"
        private const val GALLERY_CHANNEL =
            "com.qujindai.localportraitlab/gallery"
    }
}
