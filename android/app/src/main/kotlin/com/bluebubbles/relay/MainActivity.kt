package com.bluebubbles.relay

import android.content.ActivityNotFoundException
import android.content.ContentResolver
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
    private var resumed = false
    private var pendingInstall: String? = null // an update to open once Relay is back on screen

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
            if (call.method == "appBuild") {
                result.success(appBuild())
                return@setMethodCallHandler
            }
            if (call.method == "appVersion") {
                result.success(appVersion())
                return@setMethodCallHandler
            }
            if (call.method == "installApk") {
                result.success(installApk(call.argument<String>("path") ?: ""))
                return@setMethodCallHandler
            }
            if (call.method == "openFile") {
                result.success(openFile(call.argument<String>("path") ?: "", call.argument<String>("mime")))
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
        // Not after Android restarted Relay or when it's reopened from Recents:
        // those bring back the old share, which was already imported.
        if (savedInstanceState == null && (intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY) == 0) readShare(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        readShare(intent)
    }

    override fun onResume() {
        super.onResume()
        resumed = true
        requestFastestRefreshRate()
        // Ask Android to tell Flutter the current keyboard state again: the
        // keyboard closing while Relay was away can leave its space reserved.
        window.decorView.post { window.decorView.requestApplyInsets() }
        pendingInstall?.let {
            pendingInstall = null
            installApk(it)
        }
    }

    override fun onPause() {
        resumed = false
        super.onPause()
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

    private fun copyToCache(u: Uri): String? {
        // content:// only. A file:// link could make Relay copy its own private files.
        if (u.scheme != ContentResolver.SCHEME_CONTENT) return null
        return try {
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

    // The build number CI stamped on this APK (Relay-<N>.apk), for the update check.
    private fun appBuild(): Long = try {
        val info = if (Build.VERSION.SDK_INT >= 33)
            packageManager.getPackageInfo(packageName, android.content.pm.PackageManager.PackageInfoFlags.of(0))
        else @Suppress("DEPRECATION") packageManager.getPackageInfo(packageName, 0)
        if (Build.VERSION.SDK_INT >= 28) info.longVersionCode else @Suppress("DEPRECATION") info.versionCode.toLong()
    } catch (_: Throwable) {
        0L
    }

    // The version name (pubspec `version`, e.g. 1.1.0) for the Settings footer.
    private fun appVersion(): String = try {
        val info = if (Build.VERSION.SDK_INT >= 33)
            packageManager.getPackageInfo(packageName, android.content.pm.PackageManager.PackageInfoFlags.of(0))
        else @Suppress("DEPRECATION") packageManager.getPackageInfo(packageName, 0)
        info.versionName ?: ""
    } catch (_: Throwable) {
        ""
    }

    // Hands a downloaded update to Android's installer. The first time, Android
    // asks to allow Relay to install apps, then shows the usual Update screen.
    private fun installApk(path: String): String {
        return try {
            val f = File(path)
            if (!f.exists()) return "missing"
            // Android quietly blocks the installer if Relay isn't on screen;
            // open it when Relay comes back instead.
            if (!resumed) {
                pendingInstall = path
                return "ok"
            }
            val uri = androidx.core.content.FileProvider.getUriForFile(this, "$packageName.relay.files", f)
            startActivity(
                Intent(Intent.ACTION_VIEW)
                    .setDataAndType(uri, "application/vnd.android.package-archive")
                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
            )
            "ok"
        } catch (t: Throwable) {
            t.message ?: "failed"
        }
    }

    // Opens a downloaded attachment (saved under cache/open/) in another app.
    // False if no app can open it.
    private fun openFile(path: String, mime: String?): Boolean {
        return try {
            val f = File(path)
            if (!f.exists()) return false
            val uri = androidx.core.content.FileProvider.getUriForFile(this, "$packageName.relay.files", f)
            val type = mime?.takeIf { it.isNotBlank() }
                ?: MimeTypeMap.getSingleton().getMimeTypeFromExtension(f.extension.lowercase())
                ?: "*/*"
            startActivity(
                Intent(Intent.ACTION_VIEW)
                    .setDataAndType(uri, type)
                    .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
            )
            true
        } catch (_: ActivityNotFoundException) {
            false
        } catch (_: Throwable) {
            false // e.g. the file isn't in a folder the FileProvider shares
        }
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
