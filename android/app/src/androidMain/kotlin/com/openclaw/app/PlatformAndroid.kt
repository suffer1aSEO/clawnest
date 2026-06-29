package com.openclaw.app

import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.provider.OpenableColumns
import android.view.ViewTreeObserver
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.PickVisualMediaRequest
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.platform.LocalView
import androidx.core.content.FileProvider
import androidx.core.view.ViewCompat
import androidx.core.view.WindowInsetsCompat
import java.io.File

/** Holds the application Context for the platform actuals. Set in MainActivity.onCreate. */
object AppCtx {
    lateinit var ctx: Context
}

private val IMAGE_EXT = Regex("(?i).*\\.(png|jpe?g|gif|webp|bmp|heic|heif)$")

private fun prefs() = AppCtx.ctx.getSharedPreferences("openclaw", Context.MODE_PRIVATE)

actual fun settingsGet(key: String, def: String): String = prefs().getString(key, def) ?: def
actual fun settingsPut(key: String, value: String) { prefs().edit().putString(key, value).apply() }

actual fun appCacheDirPath(): String = AppCtx.ctx.cacheDir.absolutePath

actual fun loadProvisionScript(): String =
    AppCtx.ctx.assets.open("provision.sh").bufferedReader().use { it.readText() }

actual fun openInSystemViewer(path: String) {
    val ctx = AppCtx.ctx
    val f = File(path)
    val uri = FileProvider.getUriForFile(ctx, ctx.packageName + ".fileprovider", f)
    val mime = ctx.contentResolver.getType(uri) ?: "*/*"
    val view = Intent(Intent.ACTION_VIEW).setDataAndType(uri, mime)
        .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
    ctx.startActivity(Intent.createChooser(view, "Open").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
}

actual fun notifyUser(title: String, body: String) {
    Notifier.show(AppCtx.ctx, title, body)
}

actual fun startKeepAlive() {
    runCatching { LinkService.start(AppCtx.ctx) }
}

actual fun stopKeepAlive() {
    runCatching { LinkService.stop(AppCtx.ctx) }
}

actual fun decodeImageFile(path: String): ImageBitmap? =
    runCatching { BitmapFactory.decodeFile(path)?.asImageBitmap() }.getOrNull()

@Composable
actual fun keyboardOpen(): Boolean {
    val view = LocalView.current
    var open by remember { mutableStateOf(false) }
    DisposableEffect(view) {
        val listener = ViewTreeObserver.OnGlobalLayoutListener {
            open = ViewCompat.getRootWindowInsets(view)?.isVisible(WindowInsetsCompat.Type.ime()) ?: false
        }
        view.viewTreeObserver.addOnGlobalLayoutListener(listener)
        onDispose { view.viewTreeObserver.removeOnGlobalLayoutListener(listener) }
    }
    return open
}

@Composable
actual fun rememberAttachmentPicker(imagesOnly: Boolean, onPick: (PickedFile?) -> Unit): () -> Unit {
    val mainHandler = remember { Handler(Looper.getMainLooper()) }
    fun resolve(uri: Uri?) {
        if (uri == null) { onPick(null); return }
        // Copy the content Uri to a real cache file off the main thread, then deliver.
        Thread {
            val picked = runCatching { copyToCache(uri) }.getOrNull()
            mainHandler.post { onPick(picked) }
        }.start()
    }
    val photo = rememberLauncherForActivityResult(ActivityResultContracts.PickVisualMedia()) { resolve(it) }
    val doc = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { resolve(it) }
    return {
        if (imagesOnly) photo.launch(PickVisualMediaRequest(ActivityResultContracts.PickVisualMedia.ImageOnly))
        else doc.launch(arrayOf("*/*"))
    }
}

private fun copyToCache(uri: Uri): PickedFile {
    val cr = AppCtx.ctx.contentResolver
    val name = queryName(uri) ?: "file_${System.currentTimeMillis()}"
    val isImage = cr.getType(uri)?.startsWith("image/") == true || IMAGE_EXT.matches(name)
    val dir = File(appCacheDirPath(), "outgoing").apply { mkdirs() }
    val safe = name.replace(Regex("[^A-Za-z0-9._-]"), "_")
    val f = File(dir, "${System.currentTimeMillis()}_$safe")
    (cr.openInputStream(uri) ?: throw RuntimeException("can't open file"))
        .use { input -> f.outputStream().use { input.copyTo(it) } }
    return PickedFile(f.absolutePath, name, isImage)
}

private fun queryName(uri: Uri): String? = try {
    AppCtx.ctx.contentResolver
        .query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
        ?.use { c -> if (c.moveToFirst()) c.getString(0) else null }
} catch (e: Exception) { null }
