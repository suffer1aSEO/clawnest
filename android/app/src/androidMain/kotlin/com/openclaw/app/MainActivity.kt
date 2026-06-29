package com.openclaw.app

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.compose.runtime.CompositionLocalProvider
import androidx.core.content.ContextCompat
import androidx.lifecycle.ViewModel
import com.openclaw.app.ui.AppNav
import com.openclaw.app.ui.AppViewModel
import com.openclaw.app.ui.LocalStrings
import com.openclaw.app.ui.OpenClawTheme
import com.openclaw.app.ui.Strings

/** Retains the shared (platform-agnostic) AppViewModel across configuration changes. */
class VmHolder : ViewModel() {
    val vm = AppViewModel()
}

class MainActivity : ComponentActivity() {
    private val holder: VmHolder by viewModels()
    private val vm get() = holder.vm

    private val notifPermission =
        registerForActivityResult(ActivityResultContracts.RequestPermission()) { /* best-effort */ }

    override fun onCreate(savedInstanceState: Bundle?) {
        // Platform actuals (prefs, cache, notifications, assets) resolve through this.
        AppCtx.ctx = applicationContext
        super.onCreate(savedInstanceState)
        requestNotifPermission()
        setContent {
            CompositionLocalProvider(LocalStrings provides Strings(vm.lang.value == "en")) {
                OpenClawTheme { AppNav(vm) }
            }
        }
        // Saved server + key from a previous run → restore the link without re-entry.
        vm.autoConnect()
    }

    override fun onResume() {
        super.onResume()
        // Came back from background: re-establish the link if it dropped while away.
        vm.onResume()
    }

    private fun requestNotifPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(this, Manifest.permission.POST_NOTIFICATIONS) !=
            PackageManager.PERMISSION_GRANTED
        ) {
            notifPermission.launch(Manifest.permission.POST_NOTIFICATIONS)
        }
    }
}
