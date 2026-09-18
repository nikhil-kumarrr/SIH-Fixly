package com.example.fixly

import android.media.AudioManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private val CHANNEL = "com.example.fixly/audio"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                val audioManager = getSystemService(AUDIO_SERVICE) as AudioManager
                when (call.method) {
                    "muteSystemSounds" -> {
                        try {
                            audioManager.adjustStreamVolume(
                                AudioManager.STREAM_SYSTEM,
                                AudioManager.ADJUST_MUTE,
                                0   // no flags → silent
                            )
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("MUTE_FAILED", e.message, null)
                        }
                    }
                    "unmuteSystemSounds" -> {
                        try {
                            audioManager.adjustStreamVolume(
                                AudioManager.STREAM_SYSTEM,
                                AudioManager.ADJUST_UNMUTE,
                                0
                            )
                            result.success(null)
                        } catch (e: Exception) {
                            result.error("UNMUTE_FAILED", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
    }
}
