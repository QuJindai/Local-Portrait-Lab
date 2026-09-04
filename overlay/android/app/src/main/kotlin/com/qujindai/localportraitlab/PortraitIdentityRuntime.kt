package com.qujindai.localportraitlab

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Canvas
import android.graphics.Paint
import com.pv.androidfacefusion.FaceDetector
import com.pv.androidfacefusion.FaceEmbedder
import com.pv.androidfacefusion.FaceSwapper
import com.pv.androidfacefusion.ImageUtils
import java.io.File
import java.io.FileOutputStream
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.util.UUID
import java.util.concurrent.ConcurrentHashMap
import kotlin.math.sqrt

/**
 * Fully on-device R11 face identity runtime.
 *
 * QNN/DMD2 remains responsible for full-frame style generation. This runtime
 * only owns identity: SCRFD -> ArcFace -> INSwapper -> ArcFace QA.
 */
class PortraitIdentityRuntime(private val context: Context) {
    private data class Session(
        val embedding: FloatArray,
        val packVersion: String,
    )

    private val sessions = ConcurrentHashMap<String, Session>()
    private val modelPack = PortraitIdentityModelPack(context)

    @Volatile
    private var initialized = false
    private lateinit var detector: FaceDetector
    private lateinit var embedder: FaceEmbedder
    private lateinit var swapper: FaceSwapper

    @Synchronized
    private fun ensureRuntime(): String {
        val packVersion = modelPack.ensureInstalled()
        if (initialized) return packVersion
        detector = FaceDetector(context.applicationContext).also { it.initialize() }
        embedder = FaceEmbedder(context.applicationContext).also { it.initialize() }
        swapper = FaceSwapper(context.applicationContext).also { it.initialize() }
        initialized = true
        return packVersion
    }

    fun status(): Map<String, Any?> = mapOf(
        "initialized" to initialized,
        "activeSessions" to sessions.size,
        "packVersion" to PortraitIdentityModelPack.PACK_VERSION,
    )

    fun prepare(sourcePath: String): Map<String, Any?> {
        val packVersion = ensureRuntime()
        val source = decodeBitmap(sourcePath, "源照片")
        try {
            val face = selectPrimaryFace(detector.detectFaces(source), source.width, source.height)
                ?: throw IllegalStateException("源照片未检测到清晰人脸")
            val aligned = ImageUtils.alignFace(source, face.landmarks, 112)
            val embedding = try {
                embedder.getEmbedding(aligned)
            } finally {
                aligned.recycle()
            }
            if (embedding.size != 512) {
                throw IllegalStateException("ArcFace embedding length=${embedding.size}, expected 512")
            }
            val token = UUID.randomUUID().toString()
            sessions[token] = Session(embedding.copyOf(), packVersion)
            return mapOf(
                "token" to token,
                "packVersion" to packVersion,
                "sourceFaceScore" to face.score.toDouble(),
            )
        } finally {
            source.recycle()
        }
    }

    fun lock(
        token: String,
        styledPath: String,
        strength: Double,
        minSimilarity: Double,
        minImprovement: Double,
    ): Map<String, Any?> {
        ensureRuntime()
        val session = sessions.remove(token)
            ?: throw IllegalStateException("身份会话已失效，请重新生成")
        val started = System.nanoTime()
        val target = decodeBitmap(styledPath, "风格结果")
        var alignedTarget112: Bitmap? = null
        var alignedTarget128: Bitmap? = null
        var swappedFace: Bitmap? = null
        var weightedFace: Bitmap? = null
        var locked: Bitmap? = null
        var postAligned112: Bitmap? = null
        try {
            val targetFace = selectPrimaryFace(detector.detectFaces(target), target.width, target.height)
                ?: throw IllegalStateException("风格结果未检测到可锁定人脸")

            alignedTarget112 = ImageUtils.alignFace(target, targetFace.landmarks, 112)
            val preEmbedding = embedder.getEmbedding(alignedTarget112)
            val preSimilarity = cosine(session.embedding, preEmbedding)

            alignedTarget128 = ImageUtils.alignFace(target, targetFace.landmarks, 128)
            swappedFace = swapper.swapFace(alignedTarget128, session.embedding, target)
            weightedFace = mixFaces(alignedTarget128, swappedFace, strength.coerceIn(0.0, 1.0))
            locked = ImageUtils.blendFaces(target, weightedFace, targetFace.landmarks, 128)

            val postFace = selectPrimaryFace(detector.detectFaces(locked), locked.width, locked.height)
                ?: throw IllegalStateException("锁脸后未检测到人脸，已拒绝结果")
            postAligned112 = ImageUtils.alignFace(locked, postFace.landmarks, 112)
            val postEmbedding = embedder.getEmbedding(postAligned112)
            val postSimilarity = cosine(session.embedding, postEmbedding)
            val improvement = postSimilarity - preSimilarity
            val passed =
                (postSimilarity >= minSimilarity && improvement >= minImprovement) ||
                    (preSimilarity >= minSimilarity && postSimilarity >= preSimilarity - 0.02)
            val lockMillis = (System.nanoTime() - started) / 1_000_000L

            if (passed) {
                replacePngAtomically(styledPath, locked)
            }

            return mapOf(
                "outputPath" to styledPath,
                "preSimilarity" to preSimilarity,
                "postSimilarity" to postSimilarity,
                "improvement" to improvement,
                "lockMillis" to lockMillis,
                "packVersion" to session.packVersion,
                "passed" to passed,
            )
        } finally {
            postAligned112?.recycle()
            locked?.recycle()
            weightedFace?.recycle()
            swappedFace?.recycle()
            alignedTarget128?.recycle()
            alignedTarget112?.recycle()
            target.recycle()
        }
    }

    fun cancel() {
        sessions.clear()
    }

    private fun decodeBitmap(path: String, label: String): Bitmap {
        val file = File(path)
        if (!file.isFile || file.length() <= 0L) {
            throw IllegalStateException("$label 文件不存在：$path")
        }
        return BitmapFactory.decodeFile(path)
            ?: throw IllegalStateException("$label 无法解码：$path")
    }

    private fun selectPrimaryFace(
        faces: List<FaceDetector.Face>,
        width: Int,
        height: Int,
    ): FaceDetector.Face? {
        if (faces.isEmpty()) return null
        val centerX = width / 2f
        val centerY = height / 2f
        return faces.maxWithOrNull(
            compareBy<FaceDetector.Face> {
                it.bbox.width() * it.bbox.height()
            }.thenBy {
                val dx = it.bbox.centerX() - centerX
                val dy = it.bbox.centerY() - centerY
                -(dx * dx + dy * dy)
            },
        )
    }

    private fun mixFaces(original: Bitmap, swapped: Bitmap, strength: Double): Bitmap {
        val out = Bitmap.createBitmap(128, 128, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(out)
        val basePaint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
        canvas.drawBitmap(original, 0f, 0f, basePaint)
        val swapPaint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG).apply {
            alpha = (255.0 * strength).toInt().coerceIn(0, 255)
        }
        canvas.drawBitmap(swapped, 0f, 0f, swapPaint)
        return out
    }

    private fun cosine(a: FloatArray, b: FloatArray): Double {
        if (a.size != b.size || a.isEmpty()) return -1.0
        var dot = 0.0
        var na = 0.0
        var nb = 0.0
        for (i in a.indices) {
            dot += a[i] * b[i]
            na += a[i] * a[i]
            nb += b[i] * b[i]
        }
        val denominator = sqrt(na) * sqrt(nb)
        return if (denominator > 1e-12) dot / denominator else -1.0
    }

    private fun replacePngAtomically(path: String, bitmap: Bitmap) {
        val target = File(path)
        val temp = File(target.parentFile, target.name + ".r11.part")
        FileOutputStream(temp).buffered().use { output ->
            if (!bitmap.compress(Bitmap.CompressFormat.PNG, 100, output)) {
                throw IllegalStateException("身份锁定结果 PNG 编码失败")
            }
        }
        try {
            Files.move(
                temp.toPath(),
                target.toPath(),
                StandardCopyOption.REPLACE_EXISTING,
                StandardCopyOption.ATOMIC_MOVE,
            )
        } catch (_: Exception) {
            Files.move(
                temp.toPath(),
                target.toPath(),
                StandardCopyOption.REPLACE_EXISTING,
            )
        }
    }
}
