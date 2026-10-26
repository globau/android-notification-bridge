package au.glob.notificationbridge

import android.app.Activity
import android.app.AlertDialog
import android.content.DialogInterface
import android.os.Handler
import android.os.Looper
import android.view.Gravity
import android.view.View
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ProgressBar
import android.widget.TextView

/** searches for macs and lets the user pick one to pair; macs that are already paired are left out */
class AddMacDialog(
    private val activity: Activity,
    private val locator: MacLocator,
    private val onPick: (Endpoint) -> Unit,
) {
    private val prefs = Prefs(activity)
    private val handler = Handler(Looper.getMainLooper())
    private val found = mutableListOf<Endpoint>()
    private val macs = LinearLayout(activity).apply { orientation = LinearLayout.VERTICAL }
    private val progress = ProgressBar(activity)
    private val status = TextView(activity)
    private lateinit var dialog: AlertDialog

    fun show() {
        val padding = (24 * activity.resources.displayMetrics.density).toInt()
        val header = LinearLayout(activity).apply {
            gravity = Gravity.CENTER_VERTICAL
            setPadding(padding, padding / 2, padding, 0)
            addView(progress)
            addView(status.apply { setPadding(padding / 2, 0, 0, 0) })
        }
        macs.setPadding(padding, padding / 2, padding, 0)
        dialog = AlertDialog.Builder(activity)
            .setTitle("Add Mac")
            .setView(LinearLayout(activity).apply {
                orientation = LinearLayout.VERTICAL
                addView(header)
                addView(macs)
            })
            .setNegativeButton("Cancel", null)
            .setPositiveButton("Search again", null)
            .create()
        dialog.setOnShowListener {
            dialog.getButton(DialogInterface.BUTTON_POSITIVE).setOnClickListener { search() }
            search()
        }
        dialog.show()
    }

    private fun search() {
        val paired = prefs.macs
        var sawPaired = false
        found.clear()
        macs.removeAllViews()
        progress.visibility = View.VISIBLE
        status.text = "Searching..."
        dialog.getButton(DialogInterface.BUTTON_POSITIVE).visibility = View.GONE
        Thread {
            locator.scan { endpoint ->
                handler.post {
                    when {
                        paired.any { it.publicKey.contentEquals(endpoint.publicKey) } -> sawPaired = true
                        found.none { it.publicKey.contentEquals(endpoint.publicKey) } -> {
                            found += endpoint
                            addButton(endpoint)
                        }
                    }
                }
            }
            handler.post {
                if (!dialog.isShowing) return@post
                progress.visibility = View.GONE
                status.text = when {
                    found.isNotEmpty() -> "Check the fingerprint matches the Mac, then tap it to pair"
                    sawPaired -> "No new Macs found; all are already paired"
                    else -> "No Macs found"
                }
                dialog.getButton(DialogInterface.BUTTON_POSITIVE).visibility = View.VISIBLE
            }
        }.start()
    }

    private fun addButton(endpoint: Endpoint) {
        macs.addView(Button(activity).apply {
            text = "Pair ${endpoint.name}\n${Crypto.fingerprint(endpoint.publicKey)}"
            setOnClickListener {
                dialog.dismiss()
                onPick(endpoint)
            }
        }, LinearLayout.LayoutParams(LinearLayout.LayoutParams.MATCH_PARENT, LinearLayout.LayoutParams.WRAP_CONTENT))
    }
}
