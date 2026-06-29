package com.openclaw.app

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.layout.ContentScale

/** A file the user picked, already materialized to a real local path. */
data class PickedFile(val path: String, val name: String, val isImage: Boolean)

// ---- platform glue (actual implementations under androidMain / desktopMain) ----

/** Persistent key/value store (Android SharedPreferences / desktop java.util.prefs). */
expect fun settingsGet(key: String, def: String): String
expect fun settingsPut(key: String, value: String)

/** Absolute path to a writable cache dir for staged/received files. */
expect fun appCacheDirPath(): String

/** The provision.sh shell script bundled with the app. */
expect fun loadProvisionScript(): String

/** Open a local file with the OS default viewer / share target. */
expect fun openInSystemViewer(path: String)

/** Post a user-facing notification (a proactive agent message). */
expect fun notifyUser(title: String, body: String)

/** Start/stop a platform keepalive (Android foreground service; no-op on desktop). */
expect fun startKeepAlive()
expect fun stopKeepAlive()

/** Decode a local image file to an ImageBitmap (null if it can't be read). */
expect fun decodeImageFile(path: String): ImageBitmap?

/** True while a soft keyboard is covering the UI (always false on desktop). */
@Composable
expect fun keyboardOpen(): Boolean

/** Remember a file/photo picker; returns a launch lambda. [onPick] fires with the chosen
 *  file (already copied to a real local path) or null if the user cancelled. */
@Composable
expect fun rememberAttachmentPicker(imagesOnly: Boolean, onPick: (PickedFile?) -> Unit): () -> Unit

/** Inline image from a local file path — platform-decoded, no network loader needed
 *  (attachments are always downloaded to a local cache before they're shown). */
@Composable
fun FileImage(path: String, contentDescription: String?, modifier: Modifier, contentScale: ContentScale = ContentScale.Fit) {
    val bmp = remember(path) { decodeImageFile(path) }
    if (bmp != null) {
        Image(bitmap = bmp, contentDescription = contentDescription, modifier = modifier, contentScale = contentScale)
    } else {
        Box(modifier.background(Color(0xFF15181C)))
    }
}
