package com.openclaw.app

import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.toComposeImageBitmap
import java.awt.Desktop
import java.awt.FileDialog
import java.awt.Frame
import java.awt.SystemTray
import java.awt.Toolkit
import java.awt.TrayIcon
import java.io.File
import java.util.prefs.Preferences
import org.jetbrains.skia.Image as SkiaImage

private val IMAGE_EXT = Regex("(?i).*\\.(png|jpe?g|gif|webp|bmp|heic|heif)$")

private val prefs: Preferences by lazy { Preferences.userRoot().node("com/openclaw/clawnest") }

actual fun settingsGet(key: String, def: String): String = prefs.get(key, def)
actual fun settingsPut(key: String, value: String) { prefs.put(key, value) }

actual fun appCacheDirPath(): String =
    File(System.getProperty("user.home"), ".clawnest/cache").apply { mkdirs() }.absolutePath

actual fun loadProvisionScript(): String =
    object {}.javaClass.getResourceAsStream("/provision.sh")
        ?.bufferedReader()?.use { it.readText() }
        ?: throw RuntimeException("provision.sh not bundled")

actual fun openInSystemViewer(path: String) {
    runCatching {
        if (Desktop.isDesktopSupported()) Desktop.getDesktop().open(File(path))
    }
}

private val trayIcon: TrayIcon? by lazy {
    runCatching {
        if (!SystemTray.isSupported()) return@runCatching null
        val img = Toolkit.getDefaultToolkit().createImage(ByteArray(0))
        TrayIcon(img, "ClawNest").apply {
            isImageAutoSize = true
            SystemTray.getSystemTray().add(this)
        }
    }.getOrNull()
}

actual fun notifyUser(title: String, body: String) {
    val t = trayIcon
    if (t != null) runCatching { t.displayMessage(title, body, TrayIcon.MessageType.INFO) }
    else println("[notify] $title: $body")
}

actual fun startKeepAlive() {}
actual fun stopKeepAlive() {}

actual fun decodeImageFile(path: String): ImageBitmap? = runCatching {
    SkiaImage.makeFromEncoded(File(path).readBytes()).toComposeImageBitmap()
}.getOrNull()

@Composable
actual fun keyboardOpen(): Boolean = false

@Composable
actual fun rememberAttachmentPicker(imagesOnly: Boolean, onPick: (PickedFile?) -> Unit): () -> Unit =
    remember(imagesOnly, onPick) {
        {
            val dialog = FileDialog(null as Frame?, "Choose file", FileDialog.LOAD)
            if (imagesOnly) dialog.setFilenameFilter { _, name -> IMAGE_EXT.matches(name) }
            dialog.isVisible = true
            val dir = dialog.directory
            val file = dialog.file
            if (dir != null && file != null) {
                val f = File(dir, file)
                onPick(PickedFile(f.absolutePath, f.name, IMAGE_EXT.matches(f.name)))
            } else {
                onPick(null)
            }
        }
    }
