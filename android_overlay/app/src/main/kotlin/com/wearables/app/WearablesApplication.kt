package com.wearables.app

import android.app.Application
import com.oudmon.ble.base.bluetooth.BleOperateManager

/**
 * Initializes the QRing SDK exactly the way the vendor's own sample app
 * does it (see MyApplication.kt in SDKSample) - this is the one required
 * init call; everything else about Bluetooth permission handling is on
 * top of this, not instead of it.
 */
class WearablesApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        BleOperateManager.getInstance(this)
        BleOperateManager.getInstance().init()
    }
}
