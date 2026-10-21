package app.pokpok.pos

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Intent
import android.os.Build
import android.Manifest
import android.content.pm.PackageManager
import org.json.JSONObject

class MainActivity : FlutterActivity() {
    private var printer: BluetoothPrinterBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        printer = BluetoothPrinterBridge(this, flutterEngine.dartExecutor.binaryMessenger)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AutoPrintService.CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "start" -> {
                    if (Build.VERSION.SDK_INT >= 31 && checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) != PackageManager.PERMISSION_GRANTED) {
                        result.error("permission", "เลือกเครื่องและอนุญาต Bluetooth ก่อน", null)
                    } else if (AutoPrintService.running) {
                        result.error("busy", "หยุดเครื่องหลักก่อนเปลี่ยนการตั้งค่า", null)
                    } else try {
                        val intent = Intent(this, AutoPrintService::class.java)
                            .putExtra("config", JSONObject(call.arguments as Map<*, *>).toString())
                        if (Build.VERSION.SDK_INT >= 26) startForegroundService(intent) else startService(intent)
                        result.success(null)
                    } catch (_: Exception) {
                        result.error("start", "เริ่มพิมพ์เบื้องหลังไม่ได้ กรุณาเปิดแอพแล้วลองใหม่", null)
                    }
                }
                "stop" -> { stopService(Intent(this, AutoPrintService::class.java)); result.success(null) }
                "state" -> result.success(mapOf("running" to AutoPrintService.running, "status" to AutoPrintService.status, "printerName" to AutoPrintService.printerName))
                else -> result.notImplemented()
            }
        }
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        printer?.onPermissionResult(requestCode)
    }

    override fun onDestroy() {
        printer?.dispose()
        super.onDestroy()
    }
}
