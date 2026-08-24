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
import com.oudmon.ble.base.communication.bigData.BloodOxygenEntity
import com.oudmon.ble.base.communication.CommandHandle
import com.oudmon.ble.base.communication.ICommandResponse
import com.oudmon.ble.base.communication.req.BloodOxygenSettingReq
import com.oudmon.ble.base.communication.req.ReadHeartRateReq
import com.oudmon.ble.base.communication.req.SetTimeReq
import com.oudmon.ble.base.communication.rsp.BloodOxygenSettingRsp
import com.oudmon.ble.base.communication.rsp.ReadHeartRateRsp
import com.oudmon.ble.base.communication.rsp.SetTimeRsp
import com.oudmon.ble.base.communication.rsp.StartHeartRateRsp
import com.oudmon.ble.base.scan.BleScannerHelper
import com.oudmon.ble.base.scan.ScanRecord
import java.util.TimeZone
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
                "syncClock" -> {
                    // Sets the ring's onboard clock from the phone's current time.
                    // Day-indexed health queries (getHeartRate, getTodayStepTotal,
                    // etc.) work by the PHONE computing a "day start" timestamp
                    // and asking the ring for data inside that window - they
                    // never ask the ring what day it thinks it is. If the ring's
                    // clock was never set, that window doesn't line up with what
                    // the ring has stored, so queries come back empty rather than
                    // erroring. Grounded in the vendor sample's
                    // BaseFunctionActivity.refreshSupportCache(), which every one
                    // of its health-feature screens calls before reading data.
                    //
                    // Dart-callable and awaited (not fire-and-forget on connect
                    // like the first version of this fix) so there's no race
                    // between this completing and a data sync starting - the app
                    // now explicitly awaits this right after connecting, before
                    // treating the ring as ready for anything else.
                    CommandHandle.getInstance().executeReqCmd(
                        SetTimeReq(0),
                        ICommandResponse<SetTimeRsp> { rsp ->
                            mainHandler.post {
                                result.success(mapOf("status" to rsp.status.toInt()))
                            }
                        },
                    )
                }
                "enableSpO2AutoSampling" -> {
                    // The vendor sample's BloodOxygenActivity explicitly writes this
                    // setting (enable=true, interval=2) before periodic SpO2 data
                    // becomes available to read - unlike heart rate, which this
                    // ring appears to auto-sample out of the box. Grounded in
                    // BloodOxygenActivity.writeBloodOxygenSetting(), which uses the
                    // identical interval value. Idempotent - harmless to call on
                    // every connection even if already enabled.
                    CommandHandle.getInstance().executeReqCmd(
                        BloodOxygenSettingReq.getWriteInstance(true, 2.toByte()),
                        ICommandResponse<BloodOxygenSettingRsp> { rsp ->
                            mainHandler.post {
                                result.success(mapOf("status" to rsp.status.toInt()))
                            }
                        },
                    )
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
                "syncHeartRate" -> {
                    // Rewritten after decompiling HFTX AI (a rebrand of the vendor's
                    // own sample app) directly - its real, working "Data Sync" flow
                    // (HeartRateActivity.syncHeartRateData()) does NOT call
                    // getTodayHeartRate()/getHeartRate(dayIndex) at all. It builds
                    // the request manually with the CURRENT moment as the query
                    // anchor, not day-start/midnight:
                    //   val nowTime = System.currentTimeMillis()/1000L + tzOffsetSeconds
                    //   CommandHandle.getInstance().executeReqCmd(ReadHeartRateReq(nowTime), ...)
                    // getTodayHeartRate() internally passes getDayStartUnixSeconds(0)
                    // (midnight) as that same parameter instead - a different query
                    // this ring's firmware doesn't answer the same way. This is the
                    // second attempt at this specific bug: the first (clock sync
                    // alone) was necessary but not sufficient. This replicates the
                    // exact proven call, not another inference from behavior.
                    var resolved = false
                    lateinit var timeoutRunnable: Runnable
                    timeoutRunnable = Runnable {
                        if (!resolved) {
                            resolved = true
                            result.error("SYNC_FAILED", "Heart rate sync timed out", null)
                        }
                    }
                    mainHandler.postDelayed(timeoutRunnable, 15000L)

                    val offsetSeconds = TimeZone.getDefault().getOffset(System.currentTimeMillis()) / 1000L
                    val nowTime = System.currentTimeMillis() / 1000L + offsetSeconds
                    CommandHandle.getInstance().executeReqCmd(
                        ReadHeartRateReq(nowTime),
                        ICommandResponse<ReadHeartRateRsp> { t ->
                            if (!resolved) {
                                resolved = true
                                mainHandler.removeCallbacks(timeoutRunnable)
                                mainHandler.post {
                                    val samples = t.getmHeartRateArray() ?: ByteArray(0)
                                    var latestIndex = -1
                                    for (i in samples.indices.reversed()) {
                                        if ((samples[i].toInt() and 0xFF) > 0) {
                                            latestIndex = i
                                            break
                                        }
                                    }
                                    if (latestIndex == -1) {
                                        result.error(
                                            "NO_DATA",
                                            "No heart rate samples yet today (queried from " +
                                                "utcTime=${t.getmUtcTime()}, arraySize=${samples.size}, " +
                                                "range=${t.range}min) - the ring auto-samples " +
                                                "periodically, give it a few minutes",
                                            null,
                                        )
                                    } else {
                                        val bpm = samples[latestIndex].toInt() and 0xFF
                                        val timestampSeconds = t.getmUtcTime() + (latestIndex * t.range * 60)
                                        result.success(
                                            mapOf(
                                                "bpm" to bpm,
                                                "timestampSeconds" to timestampSeconds,
                                            ),
                                        )
                                    }
                                }
                            }
                        },
                    )
                }
                "syncSpO2" -> {
                    // Pull-based, same shape as steps: BloodOxygenEntity has clean
                    // decoded getters (min/max arrays across the day), unlike HRV's
                    // "today" endpoint which only hands back a raw undecoded byte
                    // stream - that's why HRV below uses the live-measurement path
                    // instead.
                    BleOperateManager.getInstance().getTodayBloodOxygen(
                        object : BleOperateManager.HealthDataCallback<BloodOxygenEntity> {
                            override fun onSuccess(t: BloodOxygenEntity) {
                                mainHandler.post {
                                    val maxList = t.maxArray ?: emptyList()
                                    val minList = t.minArray ?: emptyList()
                                    if (maxList.isEmpty()) {
                                        result.error(
                                            "NO_DATA",
                                            "No SpO2 reading recorded today (queried from " +
                                                "unix_time=${t.unix_time}, dateStr=${t.dateStr})",
                                            null,
                                        )
                                    } else {
                                        result.success(
                                            mapOf(
                                                "latest" to maxList.last(),
                                                "dayMin" to (minList.minOrNull() ?: maxList.last()),
                                                "timestampSeconds" to t.unix_time,
                                            ),
                                        )
                                    }
                                }
                            }

                            override fun onError(errorCode: Int, errorMsg: String?) {
                                mainHandler.post {
                                    result.error("SYNC_FAILED", errorMsg ?: "SpO2 sync failed (code $errorCode)", null)
                                }
                            }
                        },
                    )
                }
                "checkHeartRate" -> {
                    // WARNING: confirmed non-functional on the H59MAX_F104 ring -
                    // its own capability flag reports mSupportManualHeart=false,
                    // and a previous app's logs for this exact hardware show an
                    // explicit "Manual heart rate is not supported" guard
                    // triggered by that flag before any BLE call is even made.
                    // Kept here (unused by the current UI) in case a different
                    // ring model genuinely supports it - syncHeartRate above is
                    // what Home actually uses today.
                    //
                    // One-shot version of startLiveHeartRate: takes the first valid
                    // reading, stops the measurement automatically, and resolves
                    // once - for a tap-and-wait "check now" button rather than the
                    // continuous stream the Activity tab uses during a workout.
                    var resolved = false
                    lateinit var timeoutRunnable: Runnable
                    timeoutRunnable = Runnable {
                        if (!resolved) {
                            resolved = true
                            BleOperateManager.getInstance().manualModeHeart(ICommandResponse<StartHeartRateRsp> {}, true)
                            result.error(
                                "TIMEOUT",
                                "No heart rate reading within 30s - make sure the ring is worn snugly",
                                null,
                            )
                        }
                    }
                    mainHandler.postDelayed(timeoutRunnable, 30000L)
                    BleOperateManager.getInstance().manualModeHeart(
                        ICommandResponse<StartHeartRateRsp> { rsp ->
                            if (!resolved && rsp.errCode.toInt() == 0 && rsp.heartRate > 0) {
                                resolved = true
                                mainHandler.removeCallbacks(timeoutRunnable)
                                BleOperateManager.getInstance().manualModeHeart(ICommandResponse<StartHeartRateRsp> {}, true)
                                mainHandler.post {
                                    result.success(mapOf("bpm" to rsp.heartRate, "stress" to rsp.stress))
                                }
                            }
                        },
                        false,
                    )
                }
                "checkHrv" -> {
                    // Deliberately uses manualModeHrv (live measurement), not
                    // getTodayHrv (raw undecoded array) - grounded in the vendor
                    // sample's own HrvActivity.kt, including its exact getHrv()/
                    // getValue() fallback.
                    var resolved = false
                    lateinit var timeoutRunnable: Runnable
                    timeoutRunnable = Runnable {
                        if (!resolved) {
                            resolved = true
                            BleOperateManager.getInstance().manualModeHrv(ICommandResponse<StartHeartRateRsp> {}, true)
                            result.error(
                                "TIMEOUT",
                                "No HRV reading within 30s - make sure the ring is worn snugly",
                                null,
                            )
                        }
                    }
                    mainHandler.postDelayed(timeoutRunnable, 30000L)
                    BleOperateManager.getInstance().manualModeHrv(
                        ICommandResponse<StartHeartRateRsp> { rsp ->
                            val value = if (rsp.hrv > 0) rsp.hrv else rsp.value
                            if (!resolved && rsp.errCode.toInt() == 0 && value > 0) {
                                resolved = true
                                mainHandler.removeCallbacks(timeoutRunnable)
                                BleOperateManager.getInstance().manualModeHrv(ICommandResponse<StartHeartRateRsp> {}, true)
                                mainHandler.post {
                                    result.success(mapOf("hrvMs" to value))
                                }
                            }
                        },
                        false,
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
