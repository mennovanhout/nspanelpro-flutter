package nl.mennovanhout.nspanel_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/// Brings the app up on its own after a power cut (BOOT_COMPLETED) and after
/// it has updated itself (MY_PACKAGE_REPLACED - an install kills the running
/// process and nothing restarts it otherwise). Android 8.1 still lets a
/// receiver start an activity; the background-start rules came with 10.
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED, Intent.ACTION_MY_PACKAGE_REPLACED -> {
                val launch = Intent(context, MainActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                context.startActivity(launch)
            }
        }
    }
}
