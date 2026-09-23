package com.chenweikeng.monkeycraft

import android.content.Context
import android.content.Intent
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class AudioBackgroundPlugin(
    private val context: Context,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, "monkeycraft/audio_background")
    private val serviceLease = AudioBackgroundServiceLease()

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> {
                try {
                    ContextCompat.startForegroundService(context, Intent(context, AudioPlaybackService::class.java))
                    serviceLease.markStarted()
                    result.success(null)
                } catch (error: RuntimeException) {
                    result.error("audio_background_start", error.message, null)
                }
            }
            "stop" -> {
                context.stopService(Intent(context, AudioPlaybackService::class.java))
                serviceLease.clear()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        if (serviceLease.clear()) {
            context.stopService(Intent(context, AudioPlaybackService::class.java))
        }
    }
}

internal class AudioBackgroundServiceLease {
    private var started = false

    fun markStarted() {
        started = true
    }

    fun clear(): Boolean {
        val wasStarted = started
        started = false
        return wasStarted
    }
}
