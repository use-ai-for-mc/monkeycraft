package com.chenweikeng.monkeycraft

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Fired by AlarmManager at the scheduled time. Posts the "ready" alert and clears
 * the ongoing countdown, working whether or not the app is in the foreground.
 */
class TimedNotificationReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getIntExtra(EXTRA_ID, 1)
        val title = intent.getStringExtra(EXTRA_TITLE) ?: "MonkeyCraft"
        val body = intent.getStringExtra(EXTRA_BODY) ?: ""
        val sound = intent.getBooleanExtra(EXTRA_SOUND, true)
        NotificationSupport.cancelCountdown(context)
        NotificationSupport.postAlert(context, id, title, body, sound)
    }

    companion object {
        const val EXTRA_ID = "id"
        const val EXTRA_TITLE = "title"
        const val EXTRA_BODY = "body"
        const val EXTRA_SOUND = "sound"
    }
}
