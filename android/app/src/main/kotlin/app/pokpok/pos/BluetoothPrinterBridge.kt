package app.pokpok.pos

import android.Manifest
import android.app.Activity
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothSocket
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

/** Android Classic Bluetooth SPP only. Pairing stays in the OS settings UI. */
class BluetoothPrinterBridge(private val activity: Activity, messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, "app.pokpok.pos/bluetooth_printer")
    private val main = Handler(Looper.getMainLooper())
    private val worker = Executors.newSingleThreadExecutor()
    private val busy = AtomicBoolean(false)
    private var permissionResult: MethodChannel.Result? = null
    @Volatile private var socket: BluetoothSocket? = null
    @Volatile private var disposed = false

    init { channel.setMethodCallHandler(this) }

    private fun permitted() = Build.VERSION.SDK_INT < 31 ||
        activity.checkSelfPermission(Manifest.permission.BLUETOOTH_CONNECT) == PackageManager.PERMISSION_GRANTED

    private fun adapter(): BluetoothAdapter? = activity.getSystemService(BluetoothManager::class.java)?.adapter

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "openSettings" -> {
                    activity.startActivity(Intent(Settings.ACTION_BLUETOOTH_SETTINGS))
                    result.success(null)
                }
                "pairedDevices" -> {
                    if (!permitted()) {
                        if (permissionResult != null) {
                            result.error("busy", "รอการอนุญาต Bluetooth ก่อน", null)
                        } else {
                            permissionResult = result
                            activity.requestPermissions(arrayOf(Manifest.permission.BLUETOOTH_CONNECT), 5812)
                        }
                    } else listDevices(result)
                }
                "printBytes" -> printBytes(call, result)
                else -> result.notImplemented()
            }
        } catch (_: SecurityException) {
            result.error("permission", "กรุณาอนุญาตอุปกรณ์ใกล้เคียงในการตั้งค่าแอพ", null)
        } catch (_: Exception) {
            result.error("bluetooth", "เปิด Bluetooth ไม่สำเร็จ ลองใหม่ในการตั้งค่ามือถือ", null)
        }
    }

    fun onPermissionResult(code: Int) {
        if (code != 5812) return
        val result = permissionResult ?: return
        permissionResult = null
        if (permitted()) {
            try { listDevices(result) } catch (_: Exception) {
                result.error("bluetooth", "อ่านอุปกรณ์ Bluetooth ไม่สำเร็จ", null)
            }
        } else result.error("permission", "ยังไม่ได้อนุญาตอุปกรณ์ใกล้เคียง เปิดสิทธิ์ในข้อมูลแอพแล้วลองใหม่", null)
    }

    private fun listDevices(result: MethodChannel.Result) {
        val bt = adapter()
        if (bt == null) { result.error("unsupported", "เครื่องนี้ไม่มี Bluetooth", null); return }
        if (!bt.isEnabled) { result.error("disabled", "กรุณาเปิด Bluetooth ในการตั้งค่ามือถือ", null); return }
        result.success(bt.bondedDevices.filter { it.type != BluetoothDevice.DEVICE_TYPE_LE }
            .map { mapOf("name" to (it.name ?: "Bluetooth"), "address" to it.address) })
    }

    private fun printBytes(call: MethodCall, result: MethodChannel.Result) {
        if (!permitted()) { result.error("permission", "เปิดหน้าเลือกเครื่องเพื่ออนุญาต Bluetooth ก่อน", null); return }
        val bt = adapter()
        if (bt == null || !bt.isEnabled) { result.error("disabled", "กรุณาเปิด Bluetooth", null); return }
        val address = call.argument<String>("address") ?: ""
        val data = call.argument<ByteArray>("bytes")
        if (!BluetoothAdapter.checkBluetoothAddress(address) || data == null || data.isEmpty() || data.size > 2_000_000) {
            result.error("invalid", "ข้อมูลเครื่องพิมพ์หรือใบเสร็จไม่ถูกต้อง", null); return
        }
        val device = bt.bondedDevices.firstOrNull { it.address == address }
        if (device == null || device.type == BluetoothDevice.DEVICE_TYPE_LE) {
            result.error("pairing", "จับคู่เครื่องพิมพ์ Bluetooth Classic ในการตั้งค่ามือถือก่อน", null); return
        }
        if (!busy.compareAndSet(false, true)) { result.error("busy", "กำลังส่งงานพิมพ์ กรุณารอ", null); return }
        val finished = AtomicBoolean(false)
        val expired = AtomicBoolean(false)
        val timeout = Runnable {
            expired.set(true)
            try { socket?.close() } catch (_: Exception) { }
            if (finished.compareAndSet(false, true)) result.error("timeout", "ส่งงานนานเกินไป อาจพิมพ์บางส่วนแล้ว ตรวจกระดาษก่อนลองใหม่", null)
        }
        main.postDelayed(timeout, 90_000)
        worker.execute {
            var failure: String? = null
            var wrote = false
            try {
                val connection = device.createRfcommSocketToServiceRecord(UUID.fromString("00001101-0000-1000-8000-00805F9B34FB"))
                socket = connection
                if (disposed || expired.get()) throw IllegalStateException()
                val connectTimeout = Runnable { try { connection.close() } catch (_: Exception) { } }
                main.postDelayed(connectTimeout, 15_000)
                try { connection.connect() } finally { main.removeCallbacks(connectTimeout) }
                val output = connection.outputStream
                var offset = 0
                while (offset < data.size) {
                    if (disposed || expired.get()) throw IllegalStateException()
                    val size = minOf(512, data.size - offset)
                    // Mark before write: an exception can occur after partial delivery.
                    wrote = true
                    output.write(data, offset, size)
                    output.flush()
                    offset += size
                    Thread.sleep(15)
                }
                Thread.sleep(250)
            } catch (_: Exception) {
                failure = if (wrote) "ส่งงานไม่ครบ อาจพิมพ์บางส่วนแล้ว ตรวจใบเดิมก่อนลองใหม่"
                    else "เชื่อมต่อไม่ได้ ตรวจเครื่องพิมพ์และปิดการเชื่อมต่อใน RawBT หรือแอพอื่น แล้วลองใหม่"
            } finally {
                try { socket?.close() } catch (_: Exception) { }
                socket = null
                main.post {
                    main.removeCallbacks(timeout)
                    busy.set(false)
                    if (finished.compareAndSet(false, true)) {
                        if (failure == null) result.success(null)
                        else result.error("print_failed", failure, null)
                    }
                }
            }
        }
    }

    fun dispose() {
        disposed = true
        channel.setMethodCallHandler(null)
        permissionResult?.error("closed", "หน้าการเชื่อมต่อถูกปิด", null)
        permissionResult = null
        try { socket?.close() } catch (_: Exception) { }
        worker.shutdownNow()
    }
}
