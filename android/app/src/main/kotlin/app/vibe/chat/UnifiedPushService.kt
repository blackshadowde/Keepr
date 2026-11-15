package app.keepr.chat

import android.content.Context
import io.flutter.embedding.engine.FlutterEngine

// Replaces the UnifiedPush plugin's service so a push doesn't start an
// engine (and isolate) of its own but uses the app's.
class UnifiedPushService : org.unifiedpush.flutter.connector.UnifiedPushService() {
    override fun getEngine(context: Context): FlutterEngine {
        return MainActivity.provideRunningEngine(applicationContext)
    }
}
