package com.bluebubbles.relay

import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.OpenableColumns
import android.webkit.MimeTypeMap
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
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
