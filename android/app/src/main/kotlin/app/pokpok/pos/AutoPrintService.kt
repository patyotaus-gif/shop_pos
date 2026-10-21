package app.pokpok.pos

import android.app.*
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.*
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

/** User-started print station. A dedicated engine survives Activity destruction.
 * No boot receiver or silent restart: unacknowledged spool jobs require review. */
class AutoPrintService : Service() {
    companion object {
        const val CHANNEL = "app.pokpok.pos/auto_print"
        const val STOP = "app.pokpok.pos.STOP_AUTO_PRINT"
        @Volatile var running = false
        @Volatile var status = "หยุดพิมพ์อัตโนมัติ"
        @Volatile var printerName = ""
    }
    private var engine: FlutterEngine? = null
    private var printer: BluetoothPrinterBridge? = null
    private var wakeLock: PowerManager.WakeLock? = null
    private var config: Map<String, Any?> = emptyMap()
    private val handler = Handler(Looper.getMainLooper())
    private val startupTimeout = Runnable { status = "เริ่มเครื่องหลักไม่สำเร็จ เปิดแอพแล้วลองใหม่"; stopSelf() }

    override fun onBind(intent: Intent?) = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == STOP || intent?.getStringExtra("config") == null) {
            stopSelf(); return START_NOT_STICKY
        }
        if (engine != null) return START_NOT_STICKY
        try {
            val json = JSONObject(intent.getStringExtra("config")!!)
            config = json.keys().asSequence().associateWith { json.get(it) }
            printerName = config["name"] as? String ?: ""
            val manager = getSystemService(NotificationManager::class.java)
            if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(
                NotificationChannel("auto_print", "เครื่องหลักพิมพ์อัตโนมัติ", NotificationManager.IMPORTANCE_LOW))
            status = "กำลังเริ่มเครื่องหลัก"
            if (Build.VERSION.SDK_INT >= 29) startForeground(5813, notification(), ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE)
            else startForeground(5813, notification())
            running = true
            wakeLock = (getSystemService(POWER_SERVICE) as PowerManager)
                .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "Pokpok:AutoPrint").also { it.acquire() }
            val loader = FlutterInjector.instance().flutterLoader()
            loader.startInitialization(this)
            loader.ensureInitializationComplete(this, null)
            val worker = FlutterEngine(this)
            engine = worker
            printer = BluetoothPrinterBridge(this, worker.dartExecutor.binaryMessenger)
            MethodChannel(worker.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
                when (call.method) {
                    "configuration" -> result.success(config)
                    "status" -> {
                        handler.removeCallbacks(startupTimeout)
                        status = call.argument<String>("text") ?: "รอออเดอร์"
                        manager.notify(5813, notification())
                        result.success(null)
                    }
                    "stop" -> { result.success(null); stopSelf() }
                    else -> result.notImplemented()
                }
            }
            handler.postDelayed(startupTimeout, 60_000)
            worker.dartExecutor.executeDartEntrypoint(DartExecutor.DartEntrypoint(loader.findAppBundlePath(), "autoPrintMain"))
        } catch (_: Exception) {
            status = "เริ่มเครื่องหลักไม่สำเร็จ ตรวจสิทธิ์ Bluetooth แล้วลองใหม่"
            stopSelf()
        }
        return START_NOT_STICKY
    }

    private fun notification(): Notification {
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val stop = PendingIntent.getService(this, 0, Intent(this, AutoPrintService::class.java).setAction(STOP), PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this, "auto_print") else Notification.Builder(this)
        return builder.setSmallIcon(android.R.drawable.stat_notify_more)
            .setContentTitle("Pokpok • เครื่องหลักพิมพ์อัตโนมัติ")
            .setContentText(status).setContentIntent(open).setOngoing(true)
            .setOnlyAlertOnce(true).setVisibility(Notification.VISIBILITY_PRIVATE)
            .addAction(android.R.drawable.ic_media_pause, "หยุด", stop).build()
    }

    override fun onDestroy() {
        running = false
        handler.removeCallbacks(startupTimeout)
        printer?.dispose()
        engine?.destroy()
        engine = null
        if (wakeLock?.isHeld == true) wakeLock?.release()
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }
}
