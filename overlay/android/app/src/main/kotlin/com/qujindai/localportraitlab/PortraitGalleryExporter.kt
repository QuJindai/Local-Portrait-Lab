package com.qujindai.localportraitlab

import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import java.io.File
import java.io.FileNotFoundException
import java.io.IOException

/**
 * Exports an already-encoded generated image to Android MediaStore.
 *
 * This deliberately mirrors Local Dream's mature saveImageFromFile pattern:
 * the app-private PNG/JPEG is copied directly to Pictures without re-encoding.
 * Android 10+ uses scoped-storage RELATIVE_PATH and IS_PENDING so Gallery only
 * sees the item after the write completed successfully.
 */
object PortraitGalleryExporter {
    private const val RELATIVE_PATH = "Pictures/Portrait Lab"

    fun export(context: Context, sourcePath: String): Map<String, String> {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            throw IOException(
                "Portrait Lab 不申请旧版广域存储权限；系统相册自动保存需要 Android 10 或更高版本。",
            )
        }

        val source = File(sourcePath)
        if (!source.exists() || !source.isFile || source.length() <= 0L) {
            throw FileNotFoundException("生成结果文件不存在或为空：$sourcePath")
        }

        val extension = source.extension.lowercase().ifEmpty { "png" }
        val mimeType = when (extension) {
            "jpg", "jpeg" -> "image/jpeg"
            "webp" -> "image/webp"
            else -> "image/png"
        }
        val safeExtension = when (mimeType) {
            "image/jpeg" -> "jpg"
            "image/webp" -> "webp"
            else -> "png"
        }
        val displayName = "portrait_${System.currentTimeMillis()}.$safeExtension"
        val resolver = context.contentResolver
        val values = ContentValues().apply {
            put(MediaStore.Images.Media.DISPLAY_NAME, displayName)
            put(MediaStore.Images.Media.MIME_TYPE, mimeType)
            put(MediaStore.Images.Media.RELATIVE_PATH, RELATIVE_PATH)
            put(MediaStore.Images.Media.IS_PENDING, 1)
        }
        val uri = resolver.insert(
            MediaStore.Images.Media.EXTERNAL_CONTENT_URI,
            values,
        ) ?: throw IOException("MediaStore 无法创建系统相册记录。")

        try {
            source.inputStream().buffered().use { input ->
                val output = resolver.openOutputStream(uri, "w")
                    ?: throw IOException("MediaStore 无法打开输出流。")
                output.buffered().use { target ->
                    input.copyTo(target, 64 * 1024)
                    target.flush()
                }
            }
            val publish = ContentValues().apply {
                put(MediaStore.Images.Media.IS_PENDING, 0)
            }
            if (resolver.update(uri, publish, null, null) <= 0) {
                throw IOException("MediaStore 写入完成但公开图片失败。")
            }
        } catch (error: Exception) {
            try {
                resolver.delete(uri, null, null)
            } catch (_: Exception) {
            }
            throw error
        }

        return mapOf(
            "uri" to uri.toString(),
            "displayName" to displayName,
            "relativePath" to RELATIVE_PATH,
            "mimeType" to mimeType,
        )
    }

    fun open(context: Context, uriString: String, mimeType: String) {
        val uri = Uri.parse(uriString)
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, mimeType.ifBlank { "image/*" })
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        if (intent.resolveActivity(context.packageManager) == null) {
            throw IOException("系统没有可打开该图片的相册或图片查看器。")
        }
        context.startActivity(intent)
    }
}
