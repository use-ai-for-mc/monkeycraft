package com.chenweikeng.monkeycraft

import android.annotation.SuppressLint
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

/**
 * Shared notification building/posting used by both [NotificationsPlugin] and
 * [TimedNotificationReceiver]. Mirrors the iOS notification + Live Activity surfaces:
 * an immediate/timed alert and an ongoing countdown.
 */
object NotificationSupport {
    const val CHANNEL_ID = "monkeycraft_timed"
    private const val CHANNEL_NAME = "Ride reminders"
    const val COUNTDOWN_NOTIFICATION_ID = 990001

    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = context.getSystemService(NotificationManager::class.java) ?: return
            if (manager.getNotificationChannel(CHANNEL_ID) == null) {
                val channel = NotificationChannel(
                    CHANNEL_ID,
                    CHANNEL_NAME,
                    NotificationManager.IMPORTANCE_HIGH,
                ).apply { description = "Ride countdowns and ready alerts" }
                manager.createNotificationChannel(channel)
            }
        }
    }

    /** A heads-up alert (used for immediate nudges and the timed "ride ready" alarm). */
    fun postAlert(context: Context, id: Int, title: String, body: String, sound: Boolean) {
        ensureChannel(context)
        val builder = baseBuilder(context, title, body)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setAutoCancel(true)
        if (!sound) builder.setSilent(true)
        post(context, id, builder)
    }

    /** An ongoing notification with a live countdown to [fireAtEpochMs] (the Live Activity analog). */
    fun postCountdown(context: Context, fireAtEpochMs: Long, title: String, body: String) {
        ensureChannel(context)
        val builder = baseBuilder(context, title, body)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .setWhen(fireAtEpochMs)
            .setUsesChronometer(true)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            builder.setChronometerCountDown(true)
        }
        post(context, COUNTDOWN_NOTIFICATION_ID, builder)
    }

    fun cancel(context: Context, id: Int) {
        NotificationManagerCompat.from(context).cancel(id)
    }

    fun cancelCountdown(context: Context) {
        NotificationManagerCompat.from(context).cancel(COUNTDOWN_NOTIFICATION_ID)
    }

    private fun baseBuilder(context: Context, title: String, body: String): NotificationCompat.Builder {
        return NotificationCompat.Builder(context, CHANNEL_ID)
            // TODO: swap in a dedicated monochrome notification icon for crisper rendering.
            .setSmallIcon(android.R.drawable.ic_popup_reminder)
            .setContentTitle(title)
            .setContentText(if (body.isEmpty()) title else body)
            .setContentIntent(launchIntent(context))
    }

    @SuppressLint("MissingPermission")
    private fun post(context: Context, id: Int, builder: NotificationCompat.Builder) {
        val manager = NotificationManagerCompat.from(context)
        if (!manager.areNotificationsEnabled()) return
        manager.notify(id, builder.build())
    }

    private fun launchIntent(context: Context): PendingIntent {
        val launch = context.packageManager.getLaunchIntentForPackage(context.packageName)?.apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        } ?: Intent()
        return PendingIntent.getActivity(
            context,
            0,
            launch,
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
    }
}
