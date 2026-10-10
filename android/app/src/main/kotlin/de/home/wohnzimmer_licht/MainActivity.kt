package de.home.wohnzimmer_licht

import android.content.Context
import android.net.wifi.WifiManager
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {

    // Ohne MulticastLock verwerfen viele Android-Geräte
    // Multicast-Pakete (Govee-Scan auf 239.255.255.250).
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val wifi = applicationContext
            .getSystemService(Context.WIFI_SERVICE) as WifiManager

        multicastLock = wifi.createMulticastLock("govee-lan").apply {
            setReferenceCounted(false)
            acquire()
        }
    }

    override fun onDestroy() {
        multicastLock?.takeIf { it.isHeld }?.release()
        super.onDestroy()
    }
}
