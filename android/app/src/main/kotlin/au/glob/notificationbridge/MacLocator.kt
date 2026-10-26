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

/** finds macs' bonjour services; blocking, call off the main thread */
class MacLocator(context: Context) {
    private val nsd = context.getSystemService(NsdManager::class.java)

    fun locate(publicKey: ByteArray): Endpoint? {
        val found = AtomicReference<Endpoint>()
        discover { endpoint ->
            endpoint.publicKey.contentEquals(publicKey) && found.compareAndSet(null, endpoint)
        }
        return found.get()
    }

    /** reports every mac found until the timeout */
    fun scan(onFound: (Endpoint) -> Unit) = discover { onFound(it); false }

    /** onFound returns true to stop early */
    private fun discover(timeoutSeconds: Long = 10, onFound: (Endpoint) -> Boolean) {
        val latch = CountDownLatch(1)
        val resolving = mutableListOf<NsdManager.ServiceInfoCallback>()

        val discovery = object : NsdManager.DiscoveryListener {
            override fun onServiceFound(service: NsdServiceInfo) {
                val callback = resolveCallback(onFound, latch)
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
    }

    private fun resolveCallback(onFound: (Endpoint) -> Boolean, latch: CountDownLatch) =
        object : NsdManager.ServiceInfoCallback {
            override fun onServiceUpdated(info: NsdServiceInfo) {
                val key = info.attributes["pk"]
                    ?.let { runCatching { Base64.getDecoder().decode(it) }.getOrNull() }
                    ?.takeIf { it.size == 32 }
                    ?: return
                val address = info.hostAddresses.firstOrNull { it is Inet4Address } ?: info.hostAddresses.firstOrNull()
                    ?: return
                if (onFound(Endpoint(info.serviceName, address.hostAddress!!, info.port, key))) {
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

        /** shared so locators created per activity don't each leak a thread */
        private val callbacks = Executors.newSingleThreadExecutor()
    }
}
