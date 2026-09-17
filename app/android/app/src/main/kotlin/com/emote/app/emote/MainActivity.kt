package com.emote.app.emote

import android.content.Context
import android.net.wifi.WifiManager
import android.os.PowerManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    /** mDNS 依赖 UDP 组播（224.0.0.251:5353），Android 默认会过滤组播包，
     *  需持有 MulticastLock 才能持续接收组播报文。 */
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "connectivity#acquireMulticast" -> {
                    result.success(acquireMulticastLock())
                }
                "connectivity#releaseMulticast" -> {
                    releaseMulticastLock()
                    result.success(null)
                }
                "connectivity#isWifiConnected" -> {
                    result.success(isWifiConnected())
                }
                "connectivity#isInteractive" -> {
                    result.success(isInteractive())
                }
                else -> result.notImplemented()
            }
        }
    }

    private fun acquireMulticastLock(): Boolean {
        try {
            if (multicastLock?.isHeld == true) return true // 已持有，幂等
            val wifi = applicationContext
                .getSystemService(Context.WIFI_SERVICE) as WifiManager
            val lock = wifi.createMulticastLock(LOCK_TAG).apply {
                setReferenceCounted(false)
            }
            lock.acquire()
            multicastLock = lock
            return true
        } catch (e: Exception) {
            // 组件缺失（如模拟器无 Wi-Fi）时静默返回失败，mDNS 会退化为不可用。
            return false
        }
    }

    private fun releaseMulticastLock() {
        val lock = multicastLock ?: return
        if (lock.isHeld) {
            lock.release()
        }
        multicastLock = null
    }

    private fun isWifiConnected(): Boolean {
        @Suppress("DEPRECATION") // 兼容 API 26-，避免引入网络回调的过度复杂度
        val wifi = applicationContext
            .getSystemService(Context.WIFI_SERVICE) as WifiManager
        return wifi.isWifiEnabled && (wifi.connectionInfo?.ssid?.isNotEmpty() == true)
    }

    private fun isInteractive(): Boolean {
        val pm = applicationContext
            .getSystemService(Context.POWER_SERVICE) as PowerManager
        return pm.isInteractive
    }

    override fun onDestroy() {
        releaseMulticastLock()
        super.onDestroy()
    }

    companion object {
        private const val CHANNEL = "com.emote.app/connectivity"
        private const val LOCK_TAG = "emote:mdns_multicast"
    }
}