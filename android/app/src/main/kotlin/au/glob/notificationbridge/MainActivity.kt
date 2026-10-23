package au.glob.notificationbridge

import android.Manifest
import android.app.Activity
import android.app.NotificationManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.Settings
import android.view.View
import android.view.WindowInsets
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.Switch
import android.widget.TextView

fun appLabel(context: Context, pkg: String): String =
    runCatching {
        context.packageManager.getApplicationLabel(context.packageManager.getApplicationInfo(pkg, 0)).toString()
    }.getOrDefault(pkg)

class MainActivity : Activity() {
    private val prefs by lazy { Prefs(this) }
    private val handler = Handler(Looper.getMainLooper())
    private lateinit var content: LinearLayout

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val padding = dp(16)
        content = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL }
        setContentView(ScrollView(this).apply {
            addView(content)
            setOnApplyWindowInsetsListener { view, insets ->
                val bars = insets.getInsets(WindowInsets.Type.systemBars())
                view.setPadding(padding + bars.left, padding + bars.top, padding + bars.right, padding + bars.bottom)
                insets
            }
        })
    }

    override fun onResume() {
        super.onResume()
        render()
    }

    private fun render() {
        content.removeAllViews()

        heading("Setup")
        val listener = ComponentName(this, BridgeListenerService::class.java)
        val hasAccess = getSystemService(NotificationManager::class.java).isNotificationListenerAccessGranted(listener)
        status("Notification access", hasAccess)
        if (!hasAccess) {
            button("Grant notification access") {
                startActivity(
                    Intent(Settings.ACTION_NOTIFICATION_LISTENER_DETAIL_SETTINGS)
                        .putExtra(Settings.EXTRA_NOTIFICATION_LISTENER_COMPONENT_NAME, listener.flattenToString())
                )
            }
        }

        val hasNetwork = Build.VERSION.SDK_INT < LOCAL_NETWORK_PERMISSION_SDK ||
            checkSelfPermission(Manifest.permission.ACCESS_LOCAL_NETWORK) == PackageManager.PERMISSION_GRANTED
        status("Local network access", hasNetwork)
        if (!hasNetwork) {
            button("Grant local network access") {
                requestPermissions(arrayOf(Manifest.permission.ACCESS_LOCAL_NETWORK), 0)
            }
        }

        val unrestricted = getSystemService(PowerManager::class.java).isIgnoringBatteryOptimizations(packageName)
        status("Unrestricted battery", unrestricted)
        if (!unrestricted) {
            button("Allow background running") {
                startActivity(
                    Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS, Uri.parse("package:$packageName"))
                )
            }
        }

        heading("Mac")
        val pinned = prefs.pinnedMac
        val macName = prefs.macName ?: "Mac"
        when {
            pinned == null -> text("Not paired yet")
            prefs.approved -> text(macName)
            else -> text("$macName (${Crypto.fingerprint(pinned)})")
        }
        if (!prefs.approved) {
            text("This phone: ${Crypto.fingerprint(prefs.identity.publicKey)}")
        }
        prefs.lastResult?.let { text("Last: $it") }
        button("Send test notification") {
            Forwarder.get(this).posted(
                "test:${System.currentTimeMillis()}", packageName, "Notification Bridge", "Test", "Hello from your phone"
            )
            handler.postDelayed(::render, 3000)
        }
        if (pinned != null) {
            button("Forget Mac") {
                prefs.forgetMac()
                render()
            }
        }

        heading("Apps")
        text("Notifications are forwarded only while the screen is off and the phone is plugged in.")
        val denied = prefs.deniedPackages
        prefs.seenPackages
            .map { it to appLabel(this, it) }
            .sortedBy { it.second.lowercase() }
            .forEach { (pkg, label) ->
                content.addView(Switch(this).apply {
                    text = label
                    isChecked = pkg !in denied
                    setPadding(0, dp(8), 0, dp(8))
                    setOnCheckedChangeListener { _, checked -> prefs.setForwarded(pkg, checked) }
                })
            }
    }

    private fun heading(label: String) {
        content.addView(TextView(this).apply {
            text = label
            textSize = 20f
            setPadding(0, dp(16), 0, dp(8))
        })
    }

    private fun text(label: String) {
        content.addView(TextView(this).apply {
            text = label
            setPadding(0, dp(4), 0, dp(4))
        })
    }

    private fun status(label: String, ok: Boolean) = text("$label: ${if (ok) "granted" else "missing"}")

    private fun button(label: String, onClick: (View) -> Unit) {
        val params = LinearLayout.LayoutParams(
            LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT
        ).apply { setMargins(0, dp(8), 0, dp(8)) }
        content.addView(Button(this).apply {
            text = label
            setOnClickListener(onClick)
        }, params)
    }

    private fun dp(value: Int) = (value * resources.displayMetrics.density).toInt()

    companion object {
        private const val LOCAL_NETWORK_PERMISSION_SDK = 37
    }
}
