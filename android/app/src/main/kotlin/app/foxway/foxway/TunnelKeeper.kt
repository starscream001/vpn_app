package app.foxway.foxway

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.IBinder

/** Keeps the AWG userspace process foreground while the system VPN service owns TUN. */
class TunnelKeeper : Service() {
    override fun onCreate() {
        super.onCreate()
        getSystemService(NotificationManager::class.java).createNotificationChannel(
            NotificationChannel("foxway_vpn", "VPN-подключение", NotificationManager.IMPORTANCE_LOW))
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
        startForeground(42, Notification.Builder(this, "foxway_vpn")
            .setContentTitle("FoxWay VPN")
            .setContentText("AmneziaWG активен • Открыть для отключения")
            .setSmallIcon(android.R.drawable.ic_lock_lock).setContentIntent(open).setOngoing(true).build())
    }
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int) = START_NOT_STICKY
    override fun onBind(intent: Intent?): IBinder? = null
}
