package au.glob.notificationbridge

import android.app.Notification
import android.app.NotificationManager
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.PowerManager
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

class BridgeListenerService : NotificationListenerService() {
    private val forwarded = mutableSetOf<String>()
    private val prefs by lazy { Prefs(this) }
    private val forwarder by lazy { Forwarder.get(this) }

    override fun onNotificationPosted(sbn: StatusBarNotification, rankingMap: RankingMap) {
        if (isNoise(sbn, rankingMap)) return
        prefs.markSeen(sbn.packageName)
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

    override fun onNotificationRemoved(sbn: StatusBarNotification, rankingMap: RankingMap, reason: Int) {
        if (forwarded.remove(sbn.key)) {
            forwarder.removed(sbn.key)
        }
    }

    private fun isNoise(sbn: StatusBarNotification, rankingMap: RankingMap): Boolean {
        if (sbn.packageName == packageName) return true
        val flags = sbn.notification.flags
        val ignored = Notification.FLAG_ONGOING_EVENT or Notification.FLAG_FOREGROUND_SERVICE or
            Notification.FLAG_GROUP_SUMMARY
        if (flags and ignored != 0) return true
        val ranking = Ranking()
        return rankingMap.getRanking(sbn.key, ranking) && ranking.importance < NotificationManager.IMPORTANCE_LOW
    }

    /** screen off and plugged in; not "charging", which is false once battery protection holds at 80-85% */
    private fun isUnattended(): Boolean {
        if (getSystemService(PowerManager::class.java).isInteractive) return false
        val battery = registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED)) ?: return false
        return battery.getIntExtra(BatteryManager.EXTRA_PLUGGED, 0) != 0
    }
}
