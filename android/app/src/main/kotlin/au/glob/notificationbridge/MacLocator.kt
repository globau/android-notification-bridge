package au.glob.notificationbridge

import android.content.Context
import android.net.nsd.NsdManager
import android.net.nsd.NsdServiceInfo
import android.util.Log
import java.net.Inet4Address
import java.util.Base64
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

/** finds the mac's bonjour service; blocking, call off the main thread */
class MacLocator(context: Context, private val prefs: Prefs) {
    private val nsd = context.getSystemService(NsdManager::class.java)
    private val callbacks = Executors.newSingleThreadExecutor()

    fun locate(timeoutSeconds: Long = 10): Endpoint? {
        val found = AtomicReference<Endpoint>()
        val latch = CountDownLatch(1)
        val resolving = mutableListOf<NsdManager.ServiceInfoCallback>()

        val discovery = object : NsdManager.DiscoveryListener {
            override fun onServiceFound(service: NsdServiceInfo) {
                val callback = resolveCallback(found, latch)
                synchronized(resolving) { resolving += callback }
                nsd.registerServiceInfoCallback(service, callbacks, callback)
            }

            override fun onServiceLost(service: NsdServiceInfo) {}
            override fun onDiscoveryStarted(serviceType: String) {}
            override fun onDiscoveryStopped(serviceType: String) {}

            override fun onStartDiscoveryFailed(serviceType: String, errorCode: Int) {
                Log.w(TAG, "discovery failed: $errorCode")
                latch.countDown()
            }

            override fun onStopDiscoveryFailed(serviceType: String, errorCode: Int) {}
        }

        nsd.discoverServices(SERVICE_TYPE, NsdManager.PROTOCOL_DNS_SD, discovery)
        latch.await(timeoutSeconds, TimeUnit.SECONDS)
        runCatching { nsd.stopServiceDiscovery(discovery) }
        synchronized(resolving) {
            resolving.forEach { runCatching { nsd.unregisterServiceInfoCallback(it) } }
        }

        return found.get()?.also { endpoint ->
            if (prefs.pinnedMac == null) {
                prefs.pinnedMac = endpoint.publicKey
            }
            prefs.endpoint = endpoint
        }
    }

    private fun resolveCallback(found: AtomicReference<Endpoint>, latch: CountDownLatch) =
        object : NsdManager.ServiceInfoCallback {
            override fun onServiceUpdated(info: NsdServiceInfo) {
                val key = info.attributes["pk"]
                    ?.let { runCatching { Base64.getDecoder().decode(it) }.getOrNull() }
                    ?.takeIf { it.size == 32 }
                    ?: return
                val pinned = prefs.pinnedMac
                if (pinned != null && !pinned.contentEquals(key)) {
                    Log.i(TAG, "ignoring unpinned mac ${info.serviceName}")
                    return
                }
                val address = info.hostAddresses.firstOrNull { it is Inet4Address } ?: info.hostAddresses.firstOrNull()
                    ?: return
                if (found.compareAndSet(null, Endpoint(info.serviceName, address.hostAddress!!, info.port, key))) {
                    latch.countDown()
                }
            }

            override fun onServiceInfoCallbackRegistrationFailed(errorCode: Int) {
                Log.w(TAG, "resolve failed: $errorCode")
            }

            override fun onServiceLost() {}
            override fun onServiceInfoCallbackUnregistered() {}
        }

    companion object {
        private const val TAG = "MacLocator"
        private const val SERVICE_TYPE = "_notifbridge._tcp"
    }
}
