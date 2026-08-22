package com.wearables.app

import android.Manifest
import android.bluetooth.BluetoothDevice
import android.bluetooth.le.ScanResult
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import com.oudmon.ble.base.bluetooth.BleAction
import com.oudmon.ble.base.bluetooth.BleOperateManager
import com.oudmon.ble.base.communication.entity.BleStepTotal
import com.oudmon.ble.base.communication.ICommandResponse
import com.oudmon.ble.base.communication.rsp.StartHeartRateRsp
import com.oudmon.ble.base.scan.BleScannerHelper
import com.oudmon.ble.base.scan.ScanRecord
import com.oudmon.ble.base.scan.ScanWrapperCallback
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Bridges Dart calls to the QRing SDK's BleOperateManager / BleScannerHelper.
 *
 * `core/permissions.dart` is where Bluetooth permission is actually gated,
 * on the Dart side, before every entry point that reaches this class. This
 * class checks again anyway (see [hasBluetoothPermission]) as a second
 * line of defence: the QRing SDK itself never checks Android runtime
 * permissions and never catches SecurityException anywhere in its source -
 * confirmed by reading the whole decompiled SDK - so a permission slip
 * that somehow reaches this far returns a normal error to Dart instead of
 * crashing the app.
 */
class QRingBridge(private val context: Context) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    private var eventSink: EventChannel.EventSink? = null
    private val mainHandler = Handler(Looper.getMainLooper())
    private var scanTimeoutRunnable: Runnable? = null

    private val connectionReceiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context, intent: Intent) {
            when (intent.action) {
                BleAction.BLE_GATT_CONNECTED ->
                    emit(mapOf("type" to "connectionState", "state" to "connected"))
                BleAction.BLE_GATT_DISCONNECTED ->
                    emit(mapOf("type" to "connectionState", "state" to "disconnected"))
            }
        }
    }

    private val scanCallback = object : ScanWrapperCallback {
        override fun onStart() {}
        override fun onStop() {}
        override fun onScanFailed(errorCode: Int) {}
        override fun onBatchScanResults(results: MutableList<ScanResult>?) {}
        override fun onParsedData(device: BluetoothDevice?, scanRecord: ScanRecord?) {}

        override fun onLeScan(device: BluetoothDevice?, rssi: Int, scanRecord: ByteArray?) {
            if (device == null) return
            val name = try {
                if (hasBluetoothPermission()) device.name ?: "" else ""
            } catch (e: SecurityException) {
                ""
            }
            emit(
                mapOf(
                    "type" to "scanResult",
                    "name" to name,
                    "address" to device.address,
                    "rssi" to rssi,
                ),
            )
        }
    }

    init {
        ContextCompat.registerReceiver(
            context,
            connectionReceiver,
            BleAction.getIntentFilter(),
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )
    }

    private fun hasBluetoothPermission(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        return ContextCompat.checkSelfPermission(context, Manifest.permission.BLUETOOTH_CONNECT) ==
            PackageManager.PERMISSION_GRANTED
    }

    private fun emit(payload: Map<String, Any?>) {
        mainHandler.post { eventSink?.success(payload) }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (!hasBluetoothPermission()) {
            result.error(
                "PERMISSION_DENIED",
                "BLUETOOTH_CONNECT not granted - request it from Dart (BluetoothGate) before calling ${call.method}",
                null,
            )
            return
        }
        try {
            when (call.method) {
                "startScan" -> {
                    val timeoutMs = (call.argument<Int>("timeoutMs") ?: 8000).toLong()
                    BleScannerHelper.getInstance().scanDevice(context, null, scanCallback)
                    scanTimeoutRunnable?.let { mainHandler.removeCallbacks(it) }
                    val stopRunnable = Runnable { BleScannerHelper.getInstance().stopScan(context) }
                    scanTimeoutRunnable = stopRunnable
                    mainHandler.postDelayed(stopRunnable, timeoutMs)
                    result.success(null)
                }
                "stopScan" -> {
                    scanTimeoutRunnable?.let { mainHandler.removeCallbacks(it) }
                    BleScannerHelper.getInstance().stopScan(context)
                    result.success(null)
                }
                "connect" -> {
                    val address = call.argument<String>("address")
                    if (address == null) {
                        result.error("BAD_ARGS", "address is required", null)
                        return
                    }
                    BleOperateManager.getInstance().connectDirectly(address)
                    result.success(true)
                }
                "disconnect" -> {
                    BleOperateManager.getInstance().unBindDevice()
                    result.success(null)
                }
                "isConnected" -> {
                    result.success(BleOperateManager.getInstance().isConnected)
                }
                "startLiveHeartRate" -> {
                    BleOperateManager.getInstance().manualModeHeart(
                        ICommandResponse<StartHeartRateRsp> { rsp ->
                            if (rsp.errCode.toInt() == 0) {
                                emit(
                                    mapOf(
                                        "type" to "heartRate",
                                        "bpm" to rsp.heartRate,
                                        // Rides along in the same response frame as heart
                                        // rate - a real sensor-reported byte from the ring's
                                        // own firmware, not something calculated app-side
                                        // (unlike blood pressure - see QRingBridge notes).
                                        "stress" to rsp.stress,
                                        "timestamp" to System.currentTimeMillis(),
                                    ),
                                )
                            }
                        },
                        false,
                    )
                    result.success(null)
                }
                "stopLiveHeartRate" -> {
                    BleOperateManager.getInstance().manualModeHeart(ICommandResponse<StartHeartRateRsp> {}, true)
                    result.success(null)
                }
                "syncTodayStats" -> {
                    // Pull-based: the ring counts steps/sleep on its own hardware and
                    // stores daily totals - there's no live push stream for this in
                    // the SDK (unlike heart rate), so "sync" means read-the-stored-
                    // total, not a continuous feed.
                    BleOperateManager.getInstance().getTodayStepTotal(
                        object : BleOperateManager.HealthDataCallback<BleStepTotal> {
                            override fun onSuccess(t: BleStepTotal) {
                                mainHandler.post {
                                    result.success(
                                        mapOf(
                                            "steps" to t.totalSteps,
                                            // Raw firmware units, not kcal/meters directly - the
                                            // vendor's own (commented-out) sample code confirms
                                            // this: `it.calorie / 1000f` and `it.distance / 1000f`.
                                            "calories" to t.calorie / 1000.0,
                                            "distanceMeters" to t.walkDistance / 1000.0,
                                            "sleepMinutes" to t.sleepDuration,
                                        ),
                                    )
                                }
                            }

                            override fun onError(errorCode: Int, errorMsg: String?) {
                                mainHandler.post {
                                    result.error(
                                        "SYNC_FAILED",
                                        errorMsg ?: "Sync failed (code $errorCode) - is the ring connected?",
                                        null,
                                    )
                                }
                            }
                        },
                    )
                }
                else -> result.notImplemented()
            }
        } catch (e: SecurityException) {
            // This is exactly the crash this bridge exists to prevent. The
            // QRing SDK never catches SecurityException itself, so we do,
            // and hand Dart a recoverable error instead of letting it take
            // the app down.
            result.error("SECURITY_EXCEPTION", e.message, null)
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }
}
