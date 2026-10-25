package au.glob.notificationbridge

import android.app.Notification
import android.app.NotificationManager
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

class BridgeListenerService : NotificationListenerService() {
    private val forwarded = mutableSetOf<String>()
    private val deferred = mutableMapOf<String, Runnable>()
    private val handler = Handler(Looper.getMainLooper())
    private val prefs by lazy { Prefs(this) }
    private val forwarder by lazy { Forwarder.get(this) }

    override fun onNotificationPosted(sbn: StatusBarNotification, rankingMap: RankingMap) {
        val ranking = ranking(sbn, rankingMap)
        if (isNoise(sbn, ranking)) {
            cancelDeferred(sbn.key)
            return
        }
        prefs.markSeen(sbn.packageName)
        if (ranking?.importance == NotificationManager.IMPORTANCE_LOW && sbn.key !in forwarded) {
            defer(sbn.key)
            return
        }
        cancelDeferred(sbn.key)
        forward(sbn)
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification, rankingMap: RankingMap, reason: Int) {
        cancelDeferred(sbn.key)
        if (forwarded.remove(sbn.key)) {
            forwarder.removed(sbn.key)
        }
    }

    override fun onListenerDisconnected() {
        handler.removeCallbacksAndMessages(null)
        deferred.clear()
    }

    /** silent notifications are often short-lived status (eg. backups) that turn ongoing or vanish within seconds */
    private fun defer(key: String) {
        if (key in deferred) return
        val runnable = Runnable {
            deferred.remove(key)
            val sbn = getActiveNotifications(arrayOf(key)).firstOrNull() ?: return@Runnable
            if (!isNoise(sbn, ranking(sbn, currentRanking))) forward(sbn)
        }
        deferred[key] = runnable
        handler.postDelayed(runnable, DEFER_MS)
    }

    private fun cancelDeferred(key: String) {
        deferred.remove(key)?.let(handler::removeCallbacks)
    }

    private fun forward(sbn: StatusBarNotification) {
        if (sbn.packageName in prefs.deniedPackages || !isUnattended()) return

        val notification = sbn.notification
        if (notification.flags and Notification.FLAG_ONLY_ALERT_ONCE != 0 && sbn.key in forwarded) return

        val extras = notification.extras
        val title = (extras.getCharSequence(Notification.EXTRA_TITLE_BIG)
            ?: extras.getCharSequence(Notification.EXTRA_TITLE))?.toString().orEmpty()
        val text = (extras.getCharSequence(Notification.EXTRA_BIG_TEXT)
            ?: extras.getCharSequence(Notification.EXTRA_TEXT))?.toString().orEmpty()
        if (title.isEmpty() && text.isEmpty()) return

        forwarded += sbn.key
        forwarder.posted(sbn.key, sbn.packageName, appLabel(this, sbn.packageName), title, text)
    }

    private fun ranking(sbn: StatusBarNotification, rankingMap: RankingMap): Ranking? =
        Ranking().takeIf { rankingMap.getRanking(sbn.key, it) }

    private fun isNoise(sbn: StatusBarNotification, ranking: Ranking?): Boolean {
        if (sbn.packageName == packageName) return true
        val flags = sbn.notification.flags
        val ignored = Notification.FLAG_ONGOING_EVENT or Notification.FLAG_FOREGROUND_SERVICE or
            Notification.FLAG_GROUP_SUMMARY
        if (flags and ignored != 0) return true
        return ranking != null && ranking.importance < NotificationManager.IMPORTANCE_LOW
    }

    /** screen off and plugged in; not "charging", which is false once battery protection holds at 80-85% */
    private fun isUnattended(): Boolean {
        if (getSystemService(PowerManager::class.java).isInteractive) return false
        val battery = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED)) ?: return false
        return battery.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) != 0
    }

    companion object {
        private const val DEFER_MS = 5000L
    }
}
