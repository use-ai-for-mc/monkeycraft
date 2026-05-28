package com.chenweikeng.monkeycraft

import android.app.Activity
import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.RingtoneManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class NotificationsPlugin(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, "monkeycraft/notifications")
    private val context: Context get() = activity
    private var pendingPermissionResult: MethodChannel.Result? = null
    private var immediateIdCounter = 2000

    init {
        channel.setMethodCallHandler(this)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        pendingPermissionResult = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "requestPermission" -> requestPermission(result)
            "scheduleTimed" -> {
                val fireAt = call.argument<Number>("fireAtEpochMs")?.toLong()
                if (fireAt == null) {
                    result.error("bad_args", "Missing fireAtEpochMs", null)
                    return
                }
                scheduleTimed(
                    id = call.argument<Int>("id") ?: 1,
                    fireAtEpochMs = fireAt,
                    title = call.argument<String>("title") ?: "MonkeyCraft",
                    body = call.argument<String>("body") ?: "",
                    sound = call.argument<Boolean>("sound") ?: true,
                )
                result.success(null)
            }
            "cancelTimed" -> {
                cancelTimed(call.argument<Int>("id") ?: 1)
                result.success(null)
            }
            "showImmediate" -> {
                NotificationSupport.postAlert(
                    context,
                    ++immediateIdCounter,
                    call.argument<String>("title") ?: "MonkeyCraft",
                    call.argument<String>("body") ?: "",
                    call.argument<Boolean>("sound") ?: true,
                )
                result.success(null)
            }
            "startCountdown", "updateCountdown" -> {
                val fireAt = call.argument<Number>("fireAtEpochMs")?.toLong()
                if (fireAt == null) {
                    result.error("bad_args", "Missing fireAtEpochMs", null)
                    return
                }
                NotificationSupport.postCountdown(
                    context,
                    fireAt,
                    call.argument<String>("countDownText") ?: "",
                )
                result.success(null)
            }
            "cancelCountdown" -> {
                NotificationSupport.cancelCountdown(context)
                result.success(null)
            }
            "playNotificationSound" -> {
                try {
                    val uri = RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
                    val ringtone = RingtoneManager.getRingtone(context, uri)
                    ringtone.play()
                    result.success(null)
                } catch (e: Exception) {
                    result.error("sound_failed", e.message, null)
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun requestPermission(result: MethodChannel.Result) {
        NotificationSupport.ensureChannel(context)
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success(NotificationManagerCompat.from(context).areNotificationsEnabled())
            return
        }
        val granted = ContextCompat.checkSelfPermission(
            context,
            android.Manifest.permission.POST_NOTIFICATIONS,
        ) == PackageManager.PERMISSION_GRANTED
        if (granted) {
            result.success(true)
            return
        }
        if (pendingPermissionResult != null) {
            // A prompt is already in flight; don't double-prompt.
            result.success(false)
            return
        }
        pendingPermissionResult = result
        ActivityCompat.requestPermissions(
            activity,
            arrayOf(android.Manifest.permission.POST_NOTIFICATIONS),
            PERMISSION_REQUEST_CODE,
        )
    }

    /** Forwarded from MainActivity. Returns true if it handled the result. */
    fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != PERMISSION_REQUEST_CODE) return false
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        pendingPermissionResult?.success(granted)
        pendingPermissionResult = null
        return true
    }

    private fun scheduleTimed(id: Int, fireAtEpochMs: Long, title: String, body: String, sound: Boolean) {
        NotificationSupport.ensureChannel(context)
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
        val intent = Intent(context, TimedNotificationReceiver::class.java).apply {
            putExtra(TimedNotificationReceiver.EXTRA_ID, id)
            putExtra(TimedNotificationReceiver.EXTRA_TITLE, title)
            putExtra(TimedNotificationReceiver.EXTRA_BODY, body)
            putExtra(TimedNotificationReceiver.EXTRA_SOUND, sound)
        }
        val pendingIntent = pendingIntentFor(id, intent)
        val canExact = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            alarmManager.canScheduleExactAlarms()
        } else {
            true
        }
        when {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && canExact ->
                alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, fireAtEpochMs, pendingIntent)
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.M ->
                // Exact alarms not permitted (API 31+ without SCHEDULE_EXACT_ALARM); fall back.
                alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, fireAtEpochMs, pendingIntent)
            else ->
                alarmManager.setExact(AlarmManager.RTC_WAKEUP, fireAtEpochMs, pendingIntent)
        }
    }

    private fun cancelTimed(id: Int) {
        val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager
        val intent = Intent(context, TimedNotificationReceiver::class.java)
        alarmManager?.cancel(pendingIntentFor(id, intent))
        NotificationSupport.cancel(context, id)
    }

    private fun pendingIntentFor(id: Int, intent: Intent): PendingIntent {
        return PendingIntent.getBroadcast(
            context,
            id,
            intent,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }

    companion object {
        private const val PERMISSION_REQUEST_CODE = 9201
    }
}
