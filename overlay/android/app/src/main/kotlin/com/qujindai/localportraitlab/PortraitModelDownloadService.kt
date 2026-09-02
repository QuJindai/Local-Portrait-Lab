package com.qujindai.localportraitlab

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.util.Log
import androidx.core.app.NotificationCompat
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.io.IOException
import java.util.concurrent.Executors
import java.util.concurrent.Future
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.zip.ZipInputStream
import okhttp3.Call
import okhttp3.OkHttpClient
import okhttp3.Request

/**
 * Large-model downloader intentionally implemented on Android rather than Dart.
 *
 * The transport/install pattern follows the proven Local Dream architecture:
 * foreground service + OkHttp + buffered file IO + content-length guard +
 * ZipInputStream extraction. This avoids Flutter/Dart owning a multi-GB HTTP
 * redirect/Xet transfer.
 */
class PortraitModelDownloadService : Service() {
    private val executor = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "portrait-model-download")
    }
    private val cancelled = AtomicBoolean(false)
    private var worker: Future<*>? = null
    private var activeCall: Call? = null

    private val client = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(30, TimeUnit.SECONDS)
        .followRedirects(true)
        .followSslRedirects(true)
        .retryOnConnectionFailure(true)
        .build()

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_CANCEL -> cancelDownload()
            ACTION_START -> startDownload(intent)
        }
        return START_NOT_STICKY
    }

    private fun startDownload(intent: Intent) {
        val modelId = intent.getStringExtra(EXTRA_MODEL_ID) ?: return
        val modelName = intent.getStringExtra(EXTRA_MODEL_NAME) ?: modelId
        val url = intent.getStringExtra(EXTRA_URL) ?: return
        val fileName = intent.getStringExtra(EXTRA_FILE_NAME) ?: return
        val destinationRoot = intent.getStringExtra(EXTRA_DESTINATION_ROOT) ?: return
        val isArchive = intent.getBooleanExtra(EXTRA_IS_ARCHIVE, false)
        val requiredFiles = intent.getStringArrayListExtra(EXTRA_REQUIRED_FILES) ?: arrayListOf()

        worker?.cancel(true)
        activeCall?.cancel()
        cancelled.set(false)
        publish(Snapshot(state = "starting", modelId = modelId))
        startForeground(NOTIFICATION_ID, createProgressNotification(modelName, 0f, false))

        worker = executor.submit {
            runDownload(
                modelId = modelId,
                modelName = modelName,
                url = url,
                fileName = fileName,
                destinationRoot = destinationRoot,
                isArchive = isArchive,
                requiredFiles = requiredFiles,
            )
        }
    }

    private fun runDownload(
        modelId: String,
        modelName: String,
        url: String,
        fileName: String,
        destinationRoot: String,
        isArchive: Boolean,
        requiredFiles: List<String>,
    ) {
        var downloadedBytes = 0L
        var totalBytes = 0L
        val root = File(destinationRoot)
        val tempDir = File(root, ".native_download")
        val tempFile = File(tempDir, "$modelId.tmp")
        val stagingDir = File(root, "$modelId.installing")

        try {
            if (tempDir.exists()) tempDir.deleteRecursively()
            tempDir.mkdirs()
            root.mkdirs()

            val request = Request.Builder().url(url).build()
            val call = client.newCall(request)
            activeCall = call

            call.execute().use { response ->
                if (!response.isSuccessful) {
                    throw IOException("下载服务器返回 HTTP ${response.code}")
                }
                val body = response.body ?: throw IOException("下载响应为空")
                totalBytes = body.contentLength()
                var lastUpdateAt = 0L

                BufferedOutputStream(FileOutputStream(tempFile)).use { output ->
                    body.byteStream().buffered().use { input ->
                        val buffer = ByteArray(32 * 1024)
                        while (true) {
                            if (cancelled.get() || Thread.currentThread().isInterrupted) {
                                throw DownloadCancelledException()
                            }
                            val count = input.read(buffer)
                            if (count == -1) break
                            output.write(buffer, 0, count)
                            downloadedBytes += count

                            val now = System.currentTimeMillis()
                            if (now - lastUpdateAt >= 500L ||
                                (totalBytes > 0 && downloadedBytes == totalBytes)
                            ) {
                                lastUpdateAt = now
                                val progress = if (totalBytes > 0) {
                                    downloadedBytes.toFloat() / totalBytes.toFloat()
                                } else {
                                    0f
                                }
                                publish(
                                    Snapshot(
                                        state = "downloading",
                                        modelId = modelId,
                                        downloadedBytes = downloadedBytes,
                                        totalBytes = totalBytes,
                                    ),
                                )
                                notificationManager().notify(
                                    NOTIFICATION_ID,
                                    createProgressNotification(modelName, progress, false),
                                )
                            }
                        }
                        output.flush()
                    }
                }
            }
            activeCall = null

            if (totalBytes > 0 && downloadedBytes != totalBytes) {
                throw IOException("下载不完整：$downloadedBytes/$totalBytes")
            }
            if (!tempFile.exists() || tempFile.length() <= 0L) {
                throw IOException("下载文件为空")
            }

            val installedPath = if (isArchive) {
                publish(
                    Snapshot(
                        state = "extracting",
                        modelId = modelId,
                        downloadedBytes = downloadedBytes,
                        totalBytes = totalBytes,
                    ),
                )
                notificationManager().notify(
                    NOTIFICATION_ID,
                    createProgressNotification(modelName, 0f, true),
                )

                if (stagingDir.exists()) stagingDir.deleteRecursively()
                stagingDir.mkdirs()
                unzipFlat(tempFile, stagingDir)
                validateRequiredFiles(stagingDir, requiredFiles)

                val finalDir = File(root, modelId)
                if (finalDir.exists()) finalDir.deleteRecursively()
                if (!stagingDir.renameTo(finalDir)) {
                    if (!stagingDir.copyRecursively(finalDir, overwrite = true)) {
                        throw IOException("模型目录安装失败")
                    }
                    stagingDir.deleteRecursively()
                }
                File(finalDir, "v3").createNewFile()
                finalDir.absolutePath
            } else {
                val target = File(root, fileName)
                if (target.exists()) target.delete()
                moveFile(tempFile, target)
                target.absolutePath
            }

            tempFile.delete()
            tempDir.deleteRecursively()
            publish(
                Snapshot(
                    state = "success",
                    modelId = modelId,
                    downloadedBytes = downloadedBytes,
                    totalBytes = totalBytes,
                    path = installedPath,
                ),
            )
            notificationManager().notify(
                NOTIFICATION_ID,
                createTerminalNotification("下载完成", modelName, false),
            )
            stopForeground(STOP_FOREGROUND_DETACH)
        } catch (_: DownloadCancelledException) {
            publish(
                Snapshot(
                    state = "cancelled",
                    modelId = modelId,
                    downloadedBytes = downloadedBytes,
                    totalBytes = totalBytes,
                ),
            )
            cleanup(tempFile, stagingDir, tempDir)
            stopForeground(STOP_FOREGROUND_REMOVE)
        } catch (error: Exception) {
            if (cancelled.get()) {
                publish(
                    Snapshot(
                        state = "cancelled",
                        modelId = modelId,
                        downloadedBytes = downloadedBytes,
                        totalBytes = totalBytes,
                    ),
                )
            } else {
                Log.e(TAG, "Model download failed", error)
                publish(
                    Snapshot(
                        state = "error",
                        modelId = modelId,
                        downloadedBytes = downloadedBytes,
                        totalBytes = totalBytes,
                        message = error.message ?: error.javaClass.simpleName,
                    ),
                )
                notificationManager().notify(
                    NOTIFICATION_ID,
                    createTerminalNotification(
                        "下载失败",
                        error.message ?: modelName,
                        true,
                    ),
                )
            }
            cleanup(tempFile, stagingDir, tempDir)
            stopForeground(STOP_FOREGROUND_REMOVE)
        } finally {
            activeCall = null
            stopSelf()
        }
    }

    private fun unzipFlat(zipFile: File, destination: File) {
        ZipInputStream(BufferedInputStream(FileInputStream(zipFile))).use { zip ->
            while (true) {
                val entry = zip.nextEntry ?: break
                if (!entry.isDirectory) {
                    val name = entry.name.substringAfterLast('/')
                    if (name.isNotEmpty() &&
                        !name.startsWith('.') &&
                        name != "__MACOSX"
                    ) {
                        val outputFile = File(destination, name)
                        BufferedOutputStream(FileOutputStream(outputFile)).use { output ->
                            val buffer = ByteArray(32 * 1024)
                            while (true) {
                                if (cancelled.get() || Thread.currentThread().isInterrupted) {
                                    throw DownloadCancelledException()
                                }
                                val count = zip.read(buffer)
                                if (count == -1) break
                                output.write(buffer, 0, count)
                            }
                        }
                    }
                }
                zip.closeEntry()
            }
        }
    }

    private fun validateRequiredFiles(directory: File, requiredFiles: List<String>) {
        for (name in requiredFiles) {
            val file = File(directory, name)
            if (!file.exists() || file.length() <= 0L) {
                throw IOException("QNN 模型包缺少必需文件：$name")
            }
        }
    }

    private fun moveFile(source: File, target: File) {
        target.parentFile?.mkdirs()
        if (source.renameTo(target)) return
        source.inputStream().use { input ->
            target.outputStream().buffered().use { output -> input.copyTo(output) }
        }
        source.delete()
    }

    private fun cleanup(vararg paths: File) {
        paths.forEach { path ->
            try {
                if (path.isDirectory) path.deleteRecursively() else path.delete()
            } catch (_: Exception) {
            }
        }
    }

    private fun cancelDownload() {
        cancelled.set(true)
        activeCall?.cancel()
        worker?.cancel(true)
        val current = snapshot
        publish(
            current.copy(
                state = "cancelled",
                message = null,
            ),
        )
        stopForeground(STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            NOTIFICATION_CHANNEL_ID,
            "模型下载",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Portrait Lab 本地模型下载"
        }
        notificationManager().createNotificationChannel(channel)
    }

    private fun createProgressNotification(
        modelName: String,
        progress: Float,
        extracting: Boolean,
    ): Notification {
        val title = if (extracting) "正在解压模型" else "正在下载 $modelName"
        return NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
            .setContentTitle(title)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setProgress(100, (progress.coerceIn(0f, 1f) * 100).toInt(), extracting)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setContentIntent(openAppPendingIntent())
            .build()
    }

    private fun createTerminalNotification(
        title: String,
        text: String,
        isError: Boolean,
    ): Notification = NotificationCompat.Builder(this, NOTIFICATION_CHANNEL_ID)
        .setContentTitle(title)
        .setContentText(text)
        .setSmallIcon(
            if (isError) android.R.drawable.stat_notify_error
            else android.R.drawable.stat_sys_download_done,
        )
        .setOngoing(false)
        .setContentIntent(openAppPendingIntent())
        .build()

    private fun openAppPendingIntent(): PendingIntent? {
        val intent = packageManager.getLaunchIntentForPackage(packageName) ?: return null
        intent.flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_NEW_TASK
        return PendingIntent.getActivity(
            this,
            0,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun notificationManager(): NotificationManager =
        getSystemService(NOTIFICATION_SERVICE) as NotificationManager

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        activeCall?.cancel()
        worker?.cancel(true)
        executor.shutdownNow()
        super.onDestroy()
    }

    private class DownloadCancelledException : Exception()

    data class Snapshot(
        val state: String,
        val modelId: String? = null,
        val downloadedBytes: Long = 0L,
        val totalBytes: Long = 0L,
        val path: String? = null,
        val message: String? = null,
    ) {
        fun toMap(): Map<String, Any?> = mapOf(
            "state" to state,
            "modelId" to modelId,
            "downloadedBytes" to downloadedBytes,
            "totalBytes" to totalBytes,
            "path" to path,
            "message" to message,
        )
    }

    companion object {
        private const val TAG = "PortraitModelDownload"
        private const val NOTIFICATION_CHANNEL_ID = "portrait_model_download"
        private const val NOTIFICATION_ID = 2001

        const val ACTION_START = "com.qujindai.localportraitlab.MODEL_DOWNLOAD_START"
        const val ACTION_CANCEL = "com.qujindai.localportraitlab.MODEL_DOWNLOAD_CANCEL"
        const val EXTRA_MODEL_ID = "model_id"
        const val EXTRA_MODEL_NAME = "model_name"
        const val EXTRA_URL = "url"
        const val EXTRA_FILE_NAME = "file_name"
        const val EXTRA_DESTINATION_ROOT = "destination_root"
        const val EXTRA_IS_ARCHIVE = "is_archive"
        const val EXTRA_REQUIRED_FILES = "required_files"

        @Volatile
        private var snapshot = Snapshot(state = "idle")

        private fun publish(value: Snapshot) {
            snapshot = value
        }

        fun snapshotMap(): Map<String, Any?> = snapshot.toMap()
    }
}
