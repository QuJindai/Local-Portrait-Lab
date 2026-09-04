package com.qujindai.localportraitlab

import android.content.Context
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.io.FileInputStream
import java.io.FileOutputStream
import java.security.MessageDigest
import java.util.concurrent.TimeUnit

/**
 * R11 identity model pack.
 *
 * The public APK/repository contains no InsightFace/INSwapper weights. The first
 * identity-locked generation downloads the research-use pack over HTTPS into
 * app-private storage, verifies exact SHA-256 digests, and then works offline.
 */
class PortraitIdentityModelPack(context: Context) {
    private val appContext = context.applicationContext
    private val root = appContext.filesDir
    private val marker = File(root, ".portrait_identity_$PACK_VERSION.ok")
    private val client = OkHttpClient.Builder()
        .connectTimeout(20, TimeUnit.SECONDS)
        .readTimeout(0, TimeUnit.MILLISECONDS)
        .retryOnConnectionFailure(true)
        .followRedirects(true)
        .followSslRedirects(true)
        .build()

    fun ensureInstalled(): String {
        if (marker.isFile && specs.all { File(root, it.fileName).isFile }) {
            return PACK_VERSION
        }
        marker.delete()
        specs.forEach(::ensureFile)
        marker.writeText(PACK_VERSION)
        return PACK_VERSION
    }

    private fun ensureFile(spec: ModelSpec) {
        val target = File(root, spec.fileName)
        if (target.isFile && target.length() > 0L && sha256(target) == spec.sha256) {
            return
        }
        target.delete()
        var lastError: Exception? = null
        for (url in spec.urls) {
            try {
                downloadVerified(url, target, spec.sha256)
                return
            } catch (error: Exception) {
                lastError = error
            }
        }
        throw IllegalStateException(
            "身份模型 ${spec.fileName} 下载或校验失败：${lastError?.message ?: "unknown"}",
            lastError,
        )
    }

    private fun downloadVerified(url: String, target: File, expectedSha256: String) {
        val part = File(target.absolutePath + ".part")
        var existing = if (part.isFile) part.length() else 0L
        val requestBuilder = Request.Builder().url(url)
        if (existing > 0L) requestBuilder.header("Range", "bytes=$existing-")

        client.newCall(requestBuilder.build()).execute().use { response ->
            if (!response.isSuccessful) {
                throw IllegalStateException("HTTP ${response.code} for ${target.name}")
            }
            val append = existing > 0L && response.code == 206
            if (!append) {
                part.delete()
                existing = 0L
            }
            val body = response.body ?: throw IllegalStateException("empty body for ${target.name}")
            FileOutputStream(part, append).buffered().use { output ->
                body.byteStream().buffered().use { input ->
                    val buffer = ByteArray(256 * 1024)
                    while (true) {
                        val read = input.read(buffer)
                        if (read < 0) break
                        output.write(buffer, 0, read)
                    }
                }
            }
        }

        val digest = sha256(part)
        if (digest != expectedSha256) {
            part.delete()
            throw IllegalStateException(
                "${target.name} SHA-256 不匹配：$digest",
            )
        }
        if (target.exists()) target.delete()
        if (!part.renameTo(target)) {
            part.copyTo(target, overwrite = true)
            part.delete()
        }
    }

    private fun sha256(file: File): String {
        val digest = MessageDigest.getInstance("SHA-256")
        FileInputStream(file).buffered().use { input ->
            val buffer = ByteArray(1024 * 1024)
            while (true) {
                val read = input.read(buffer)
                if (read < 0) break
                digest.update(buffer, 0, read)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    private data class ModelSpec(
        val fileName: String,
        val sha256: String,
        val urls: List<String>,
    )

    companion object {
        const val PACK_VERSION = "insightface-r11-v1"

        private val specs = listOf(
            ModelSpec(
                fileName = "det_10g.onnx",
                sha256 = "5838f7fe053675b1c7a08b633df49e7af5495cee0493c7dcf6697200b85b5b91",
                urls = listOf(
                    "https://huggingface.co/leonelhs/insightface/resolve/main/det_10g.onnx",
                ),
            ),
            ModelSpec(
                fileName = "w600k_r50.onnx",
                sha256 = "4c06341c33c2ca1f86781dab0e829f88ad5b64be9fba56e56bc9ebdefc619e43",
                urls = listOf(
                    "https://huggingface.co/leonelhs/insightface/resolve/main/w600k_r50.onnx",
                ),
            ),
            ModelSpec(
                fileName = "inswapper_128.onnx",
                sha256 = "e4a3f08c753cb72d04e10aa0f7dbe3deebbf39567d4ead6dce08e98aa49e16af",
                urls = listOf(
                    "https://huggingface.co/leonelhs/insightface/resolve/main/inswapper_128.onnx",
                    "https://huggingface.co/ezioruan/inswapper_128.onnx/resolve/main/inswapper_128.onnx",
                ),
            ),
            ModelSpec(
                fileName = "emap.bin",
                sha256 = "5fe266f2006172a07f83644e1978f05dd589e263b5a83c0d4e2e8e4902dae061",
                urls = listOf(
                    "https://raw.githubusercontent.com/Parasaran-Python/android-face-fusion/f38a70e4bacaab4132538421c471f9d4d3ccac00/app/src/main/assets/emap.bin",
                ),
            ),
        )
    }
}
