package com.bluebubbles.relay

import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        requestFastestRefreshRate()
    }

    override fun onResume() {
        super.onResume()
        requestFastestRefreshRate()
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
