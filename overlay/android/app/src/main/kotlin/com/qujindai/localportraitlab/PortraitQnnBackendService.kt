package com.qujindai.localportraitlab

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import java.io.File
import java.io.IOException
import java.net.InetSocketAddress
import java.net.Socket
import java.util.concurrent.Executors
import java.util.concurrent.Future
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean

/**
 * R8 standalone QNN backend controller.
 *
 * This mirrors Local Dream's proven BackendService process boundary while
 * binding the native server only to localhost on a dedicated Portrait Lab port
 * (8082). The native binary/runtime are third-party CC BY-NC components bundled
 * only in the R8 research/test build; see THIRD_PARTY_DREAM_QNN_NONCOMMERCIAL.md.
 */
class PortraitQnnBackendService : Service() {
    private val executor = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "portrait-qnn-control")
    }
    private var worker: Future<*>? = null

    @Volatile
    private var process: Process? = null

    private val stopping = AtomicBoolean(false)

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        startForeground(NOTIFICATION_ID, notification("本机 QNN 后端准备中"))
        when (intent?.action) {
            ACTION_STOP -> stopBackendAsync()
            ACTION_START -> {
                val modelId = intent.getStringExtra(EXTRA_MODEL_ID)
                val modelDirectory = intent.getStringExtra(EXTRA_MODEL_DIRECTORY)
                val backendType = intent.getStringExtra(EXTRA_BACKEND_TYPE) ?: "sdxl"
                val generationSize = intent.getIntExtra(EXTRA_GENERATION_SIZE, 1024)
                if (modelId.isNullOrBlank() || modelDirectory.isNullOrBlank()) {
                    publish(
                        Snapshot(
                            state = "error",
                            modelId = modelId,
                            message = "本机 QNN 启动参数不完整",
                        ),
                    )
                    stopForeground(STOP_FOREGROUND_REMOVE)
                    stopSelf()
                } else {
                    startBackendAsync(
                        modelId = modelId,
                        modelDirectory = modelDirectory,
                        backendType = backendType,
                        generationSize = generationSize,
                    )
                }
            }
        }
        return START_NOT_STICKY
    }

    private fun startBackendAsync(
        modelId: String,
        modelDirectory: String,
        backendType: String,
        generationSize: Int,
    ) {
        worker?.cancel(true)
        worker = executor.submit {
            stopping.set(true)
            stopProcess()
            stopping.set(false)
            publish(Snapshot(state = "starting", modelId = modelId))

            try {
                val modelDir = File(modelDirectory)
                validateModelDirectory(modelDir)
                val runtimeDir = prepareRuntimeDir()
                val executable = File(applicationInfo.nativeLibraryDir, EXECUTABLE_NAME)
                if (!executable.exists() || executable.length() <= 0L) {
                    throw IOException("缺少 $EXECUTABLE_NAME")
                }
                executable.setReadable(true, true)
                executable.setExecutable(true, true)

                val command = mutableListOf(
                    executable.absolutePath,
                    "--type",
                    backendType,
                    "--model_dir",
                    modelDir.absolutePath,
                    "--port",
                    PORT.toString(),
                    "--lib_dir",
                    runtimeDir.absolutePath,
                )
                if (backendType == "sdxl" || backendType == "anima") {
                    command += "--lowram"
                }

                val processBuilder = ProcessBuilder(command).apply {
                    directory(File(applicationInfo.nativeLibraryDir))
                    redirectErrorStream(true)
                    environment()["LD_LIBRARY_PATH"] = listOf(
                        runtimeDir.absolutePath,
                        "/system/lib64",
                        "/vendor/lib64",
                        "/vendor/lib64/egl",
                    ).joinToString(":")
                    environment()["DSP_LIBRARY_PATH"] = runtimeDir.absolutePath
                }

                Log.i(TAG, "starting standalone QNN model=$modelId type=$backendType size=$generationSize")
                val started = processBuilder.start()
                process = started
                monitorProcess(started, modelId)
                waitForReady(started)

                publish(
                    Snapshot(
                        state = "running",
                        modelId = modelId,
                        port = PORT,
                    ),
                )
                notificationManager().notify(
                    NOTIFICATION_ID,
                    notification("本机 QNN · $modelId"),
                )
            } catch (error: Exception) {
                Log.e(TAG, "standalone QNN start failed", error)
                if (!stopping.get()) {
                    publish(
                        Snapshot(
                            state = "error",
                            modelId = modelId,
                            message = error.message ?: error.javaClass.simpleName,
                        ),
                    )
                }
                stopProcess()
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
        }
    }

    private fun stopBackendAsync() {
        stopping.set(true)
        worker?.cancel(true)
        executor.submit {
            stopProcess()
            publish(Snapshot(state = "idle"))
            stopping.set(false)
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
        }
    }

    private fun validateModelDirectory(modelDir: File) {
        if (!modelDir.isDirectory) {
            throw IOException("QNN 模型目录不存在：${modelDir.absolutePath}")
        }
        for (name in REQUIRED_MODEL_FILES) {
            val file = File(modelDir, name)
            if (!file.exists() || file.length() <= 0L) {
                throw IOException("QNN 模型缺少必需文件：$name")
            }
        }
    }

    private fun prepareRuntimeDir(): File {
        val runtimeDir = File(filesDir, RUNTIME_DIR).apply {
            if (!exists()) mkdirs()
        }
        val names = assets.list(QNN_ASSET_DIR)
            ?: throw IOException("APK 中缺少 $QNN_ASSET_DIR")
        if (names.isEmpty()) throw IOException("APK 中 QNN runtime 为空")

        names.forEach { fileName ->
            val target = File(runtimeDir, fileName)
            val needsCopy = if (!target.exists()) {
                true
            } else {
                assets.open("$QNN_ASSET_DIR/$fileName").use { asset ->
                    target.length() != asset.available().toLong()
                }
            }
            if (needsCopy) {
                assets.open("$QNN_ASSET_DIR/$fileName").use { input ->
                    target.outputStream().buffered().use { output -> input.copyTo(output) }
                }
            }
            target.setReadable(true, true)
            target.setExecutable(true, true)
        }
        runtimeDir.setReadable(true, true)
        runtimeDir.setExecutable(true, true)
        return runtimeDir
    }

    private fun waitForReady(proc: Process) {
        val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(START_TIMEOUT_SECONDS)
        while (System.nanoTime() < deadline) {
            if (Thread.currentThread().isInterrupted || stopping.get()) {
                throw InterruptedException("QNN backend start cancelled")
            }
            if (!proc.isAlive) {
                throw IOException("QNN backend 在就绪前退出，code=${proc.exitValue()}")
            }
            try {
                Socket().use { socket ->
                    socket.connect(InetSocketAddress("127.0.0.1", PORT), 300)
                    return
                }
            } catch (_: IOException) {
                Thread.sleep(250)
            }
        }
        throw IOException("QNN backend ${START_TIMEOUT_SECONDS}s 内未监听 127.0.0.1:$PORT")
    }

    private fun monitorProcess(proc: Process, modelId: String) {
        Thread {
            try {
                proc.inputStream.bufferedReader().useLines { lines ->
                    lines.forEach { line ->
                        if (line.isNotBlank()) Log.i(TAG, "native: $line")
                    }
                }
                val exit = proc.waitFor()
                if (!stopping.get() && process === proc) {
                    publish(
                        Snapshot(
                            state = "error",
                            modelId = modelId,
                            message = "QNN backend 退出，code=$exit",
                        ),
                    )
                }
            } catch (error: Exception) {
                if (!stopping.get() && process === proc) {
                    publish(
                        Snapshot(
                            state = "error",
                            modelId = modelId,
                            message = "QNN backend monitor: ${error.message}",
                        ),
                    )
                }
            }
        }.apply {
            name = "portrait-qnn-monitor"
            isDaemon = true
            start()
        }
    }

    private fun stopProcess() {
        val proc = process ?: return
        try {
            proc.destroy()
            if (!proc.waitFor(5, TimeUnit.SECONDS)) {
                proc.destroyForcibly()
                proc.waitFor(2, TimeUnit.SECONDS)
            }
        } catch (error: Exception) {
            Log.w(TAG, "stop QNN backend failed: ${error.message}")
        } finally {
            if (process === proc) process = null
        }
    }

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "本机 QNN 推理",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Portrait Lab Snapdragon QNN/HTP 本地生成后端"
        }
        notificationManager().createNotificationChannel(channel)
    }

    private fun notification(text: String): Notification {
        val launchIntent = packageManager.getLaunchIntentForPackage(packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_NEW_TASK
        }
        val pendingIntent = launchIntent?.let {
            PendingIntent.getActivity(
                this,
                0,
                it,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Portrait Lab · NPU")
            .setContentText(text)
            .setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setContentIntent(pendingIntent)
            .setOnlyAlertOnce(true)
            .setOngoing(true)
            .build()
    }

    private fun notificationManager(): NotificationManager =
        getSystemService(NOTIFICATION_SERVICE) as NotificationManager

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        stopping.set(true)
        worker?.cancel(true)
        stopProcess()
        executor.shutdownNow()
        super.onDestroy()
    }

    data class Snapshot(
        val state: String,
        val modelId: String? = null,
        val message: String? = null,
        val port: Int? = null,
    ) {
        fun toMap(): Map<String, Any?> = mapOf(
            "state" to state,
            "modelId" to modelId,
            "message" to message,
            "port" to port,
        )
    }

    companion object {
        private const val TAG = "PortraitQnnBackend"
        private const val EXECUTABLE_NAME = "libstable_diffusion_core.so"
        private const val RUNTIME_DIR = "qnn_runtime"
        private const val QNN_ASSET_DIR = "qnnlibs"
        private const val PORT = 8082
        private const val START_TIMEOUT_SECONDS = 90L
        private const val CHANNEL_ID = "portrait_qnn_backend"
        private const val NOTIFICATION_ID = 2002

        const val ACTION_START = "com.qujindai.localportraitlab.QNN_BACKEND_START"
        const val ACTION_STOP = "com.qujindai.localportraitlab.QNN_BACKEND_STOP"
        const val EXTRA_MODEL_ID = "model_id"
        const val EXTRA_MODEL_DIRECTORY = "model_directory"
        const val EXTRA_BACKEND_TYPE = "backend_type"
        const val EXTRA_GENERATION_SIZE = "generation_size"

        private val REQUIRED_MODEL_FILES = listOf(
            "config.json",
            "tokenizer.json",
            "clip.mnn",
            "pos_emb.bin",
            "token_emb.bin",
            "clip_2.mnn",
            "pos_emb_2.bin",
            "token_emb_2.bin",
            "unet.bin",
            "vae_encoder.bin",
            "vae_decoder.bin",
        )

        @Volatile
        private var snapshot = Snapshot(state = "idle")

        private fun publish(value: Snapshot) {
            snapshot = value
        }

        fun snapshotMap(): Map<String, Any?> = snapshot.toMap()
    }
}
