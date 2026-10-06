package com.justoneround.app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.os.Build

object NotificationChannels {
    const val SOCIAL_ID = "social_notifications"

    fun ensureSocialChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return

        val channel = NotificationChannel(
            SOCIAL_ID,
            context.getString(R.string.social_notifications_channel_name),
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = context.getString(R.string.social_notifications_channel_description)
        }
        context.getSystemService(NotificationManager::class.java)
            .createNotificationChannel(channel)
    }
}
