package app.keepr.chat

import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.pm.ServiceInfo
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.work.CoroutineWorker
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ForegroundInfo
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import io.flutter.embedding.engine.dart.DartExecutor
import kotlinx.coroutines.delay
import java.util.concurrent.TimeUnit

/**
 * Every 15 minutes: if the phone has stopped Keepr (some phones do when it's
 * swiped away), start it again in the background for half a minute with a
 * short "Checking for new messages" notification, so messages still arrive.
 * Does nothing while Keepr is already running.
 */
class VibeCheckWorker(ctx: Context, params: WorkerParameters) :
    CoroutineWorker(ctx, params) {

    override suspend fun doWork(): Result {
        val app = applicationContext
        val prefs = app.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        val mode = prefs.getString("flutter.chat.keepr.push_mode", "direct")
        if (mode != "direct" && mode != "builtin") return Result.success()
        val eng = MainActivity.provideEngine(app)
        if (eng.dartExecutor.isExecutingDart) return Result.success()
        try {
            setForeground(info(app))
        } catch (_: Throwable) {
            // not allowed right now: still check, just without the notice
        }
        try {
            eng.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint.createDefault(),
                listOf("vibe-boot"),
            )
        } catch (_: Throwable) {
            return Result.success()
        }
        // time to connect, fetch new messages and show their notifications
        delay(30_000)
        return Result.success()
    }

    private fun info(app: Context): ForegroundInfo {
        val nm = app.getSystemService(NotificationManager::class.java)
        nm.createNotificationChannel(
            NotificationChannel(CHANNEL, "Checking for messages", NotificationManager.IMPORTANCE_MIN),
        )
        val n = NotificationCompat.Builder(app, CHANNEL)
            .setSmallIcon(R.drawable.vibe_notification)
            .setContentTitle("Keepr")
            .setContentText("Checking for new messages")
            .setOngoing(true)
            .setSilent(true)
            .build()
        return if (Build.VERSION.SDK_INT >= 34) {
            ForegroundInfo(ID, n, ServiceInfo.FOREGROUND_SERVICE_TYPE_SHORT_SERVICE)
        } else {
            ForegroundInfo(ID, n)
        }
    }

    companion object {
        private const val CHANNEL = "keepr_check"
        private const val ID = 7301

        fun schedule(ctx: Context) {
            try {
                WorkManager.getInstance(ctx).enqueueUniquePeriodicWork(
                    "keepr-check",
                    ExistingPeriodicWorkPolicy.KEEP,
                    PeriodicWorkRequestBuilder<VibeCheckWorker>(15, TimeUnit.MINUTES).build(),
                )
            } catch (_: Throwable) {
            }
        }
    }
}
