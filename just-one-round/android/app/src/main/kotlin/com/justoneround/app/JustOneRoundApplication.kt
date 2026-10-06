package com.justoneround.app

import android.app.Application

class JustOneRoundApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        // FCM may post a background notification before MainActivity exists.
        // Create the channel at process start so cold/background delivery uses
        // the same visible channel as foreground delivery.
        NotificationChannels.ensureSocialChannel(this)
    }
}
