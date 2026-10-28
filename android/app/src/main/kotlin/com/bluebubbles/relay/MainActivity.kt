package com.bluebubbles.relay

import android.content.Intent
import android.graphics.Bitmap
import android.media.MediaMetadataRetriever
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

// FragmentActivity so the fingerprint prompt can show.
class MainActivity : FlutterFragmentActivity() {
    private var channel: MethodChannel? = null
    private var pending: Map<String, Any?>? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "relay/share").also { ch ->
            ch.setMethodCallHandler { call, result ->
                if (call.method == "initial") {
                    result.success(pending)
                    pending = null
                } else result.notImplemented()
            }
        }
        // Video thumbnails: grab a frame from a video (on the Mac or on the phone).
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "relay/media").setMethodCallHandler { call, result ->
            if (call.method == "openUrl") {
                result.success(openUrl(call.argument<String>("url") ?: ""))
                return@setMethodCallHandler
            }
            if (call.method != "videoThumb") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val src = call.argument<String>("src") ?: ""
            val out = call.argument<String>("out") ?: ""
            val headers = call.argument<Map<String, String>>("headers") ?: emptyMap()
            Thread {
                var reply: Map<String, Any>? = null
                val r = MediaMetadataRetriever()
                try {
                    if (src.startsWith("/")) r.setDataSource(src) else r.setDataSource(src, headers)
                    val bmp = if (Build.VERSION.SDK_INT >= 27)
                        r.getScaledFrameAtTime(300_000, MediaMetadataRetriever.OPTION_CLOSEST_SYNC, 720, 720)
                    else r.getFrameAtTime(300_000, MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                    val dur = r.extractMetadata(MediaMetadataRetriever.METADATA_KEY_DURATION)?.toLongOrNull() ?: 0L
                    if (bmp != null) {
                        File(out).apply { parentFile?.mkdirs() }.outputStream().use { bmp.compress(Bitmap.CompressFormat.JPEG, 82, it) }
                        reply = mapOf("path" to out, "duration" to dur, "w" to bmp.width, "h" to bmp.height)
                    }
                } catch (_: Throwable) {
                } finally {
                    try { r.release() } catch (_: Throwable) {}
                }
                runOnUiThread { result.success(reply) }
            }.start()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestFastestRefreshRate()
        readShare(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        readShare(intent)
    }

    override fun onResume() {
        super.onResume()
        requestFastestRefreshRate()
    }

    // Photos, videos, files and text sent here from other apps' Share menu.
    private fun readShare(i: Intent?) {
        if (i == null) return
        if (i.action != Intent.ACTION_SEND && i.action != Intent.ACTION_SEND_MULTIPLE) return
        val text = i.getStringExtra(Intent.EXTRA_TEXT)
        val uris = ArrayList<Uri>()
        @Suppress("DEPRECATION")
        if (i.action == Intent.ACTION_SEND) {
            (i.getParcelableExtra<Uri>(Intent.EXTRA_STREAM))?.let { uris.add(it) }
        } else {
            i.getParcelableArrayListExtra<Uri>(Intent.EXTRA_STREAM)?.let { uris.addAll(it) }
        }
        i.action = Intent.ACTION_MAIN // don't re-read this share on a later resume
        Thread {
            val paths = uris.mapNotNull { copyToCache(it) }
            runOnUiThread {
                val m = mapOf("paths" to paths, "text" to text)
                val ch = channel
                if (ch != null) ch.invokeMethod("shared", m) else pending = m
            }
        }.start()
    }

    private fun copyToCache(u: Uri): String? = try {
        var name: String? = null
        contentResolver.query(u, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
            if (c.moveToFirst()) name = c.getString(0)
        }
        if (name.isNullOrBlank()) {
            val ext = MimeTypeMap.getSingleton().getExtensionFromMimeType(contentResolver.getType(u)) ?: "bin"
            name = "shared.$ext"
        }
        val dir = File(cacheDir, "shared").apply { mkdirs() }
        val out = File(dir, "${System.currentTimeMillis()}_${name!!.replace('/', '_')}")
        contentResolver.openInputStream(u)?.use { input -> out.outputStream().use { input.copyTo(it) } }
        out.absolutePath
    } catch (_: Throwable) {
        null
    }

    // Links open in their own app (TikTok, YouTube, Instagram…) when it's installed,
    // otherwise the browser, always as a separate app. Without NEW_TASK the other
    // app's screen gets stacked inside Relay, and you're stuck in it until you back out.
    private fun openUrl(url: String): Boolean {
        if (url.isBlank()) return false
        val uri = Uri.parse(url)
        fun start(flags: Int): Boolean = try {
            startActivity(Intent(Intent.ACTION_VIEW, uri).addCategory(Intent.CATEGORY_BROWSABLE).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or flags))
            true
        } catch (_: Throwable) {
            false
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R && start(Intent.FLAG_ACTIVITY_REQUIRE_NON_BROWSER)) return true
        return start(0)
    }

    // Samsung keeps most apps at 60 Hz unless they ask for the screen's fastest
    // mode. Ask for it, so scrolling and animations run at 120 Hz.
    private fun requestFastestRefreshRate() {
        try {
            @Suppress("DEPRECATION")
            val d = (if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) display else windowManager.defaultDisplay) ?: return
            val current = d.mode
            val best = d.supportedModes
                .filter { it.physicalWidth == current.physicalWidth && it.physicalHeight == current.physicalHeight }
                .maxByOrNull { it.refreshRate } ?: return
            val lp = window.attributes
            if (lp.preferredDisplayModeId != best.modeId) {
                lp.preferredDisplayModeId = best.modeId
                window.attributes = lp
            }
        } catch (_: Throwable) {
        }
    }
}
