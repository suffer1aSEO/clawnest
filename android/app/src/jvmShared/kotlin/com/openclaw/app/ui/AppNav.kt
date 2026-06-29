package com.openclaw.app.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.List
import androidx.compose.material.icons.filled.Home
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.NavigationBarItemDefaults
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.openclaw.app.keyboardOpen

private data class Tab(val route: String, val icon: ImageVector)

private val TABS = listOf(
    Tab("chat", Icons.Filled.Home),
    Tab("agents", Icons.Filled.Person),
    Tab("journal", Icons.AutoMirrored.Filled.List),
    Tab("settings", Icons.Filled.Settings),
)

@Composable
fun AppNav(vm: AppViewModel) {
    val ready = vm.conn.value == ConnState.Ready
    val haveUi = vm.personas.isNotEmpty()
    when {
        // User explicitly chose to edit creds → the form.
        vm.showForm.value -> ConnectScreen(vm)
        // Connected, or we still hold the loaded UI (a drop after login) → main app. A
        // reconnect just shows a banner, never tears the interface down.
        ready || haveUi -> MainScaffold(vm, reconnecting = !ready)
        // Returning user, cold start, nothing loaded yet → tidy splash, not the VPS form.
        vm.hasSavedCreds() -> ConnectingSplash(vm)
        // First-ever launch → setup form.
        else -> ConnectScreen(vm)
    }
}

@Composable
private fun MainScaffold(vm: AppViewModel, reconnecting: Boolean) {
    val accent = personaColor(vm.currentPersona()?.themeColor)
    val kbOpen = keyboardOpen()
    var route by remember { mutableStateOf("chat") }
    // Non-null => the persona editor is open over the current tab ("_new" for a fresh persona).
    var editorId by remember { mutableStateOf<String?>(null) }
    Scaffold(
        containerColor = Bg,
        bottomBar = { if (!kbOpen && editorId == null) BottomBar(route, accent) { route = it } },
    ) { pad ->
        Column(Modifier.padding(pad)) {
            if (reconnecting) ReconnectBanner()
            Box(Modifier.weight(1f)) {
                val ed = editorId
                if (ed != null) {
                    PersonaEditorScreen(vm, ed, onBack = { editorId = null })
                } else when (route) {
                    "chat" -> ChatScreen(vm)
                    "agents" -> AgentsScreen(
                        vm,
                        onOpenChat = { id -> vm.selectPersona(id); route = "chat" },
                        onEdit = { id -> editorId = id },
                        onCreate = { editorId = "_new" },
                    )
                    "journal" -> JournalScreen(vm)
                    "settings" -> SettingsScreen(vm)
                }
            }
        }
    }
}

/** Thin, non-blocking strip shown over the live UI while a logged-in session reconnects. */
@Composable
private fun ReconnectBanner() {
    Row(
        Modifier.fillMaxWidth().background(Color(0xFF2A2614)).padding(horizontal = 14.dp, vertical = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.Center,
    ) {
        CircularProgressIndicator(Modifier.size(13.dp), color = Orange, strokeWidth = 2.dp)
        Spacer(Modifier.width(8.dp))
        Text(LocalStrings.current.reconnecting, color = Orange, fontSize = 13.sp)
    }
}

/** Calm splash for a returning user while the saved connection is being restored. */
@Composable
private fun ConnectingSplash(vm: AppViewModel) {
    val s = LocalStrings.current
    Column(
        Modifier.fillMaxSize().background(Bg).padding(24.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        CircularProgressIndicator(color = Green, strokeWidth = 3.dp)
        Spacer(Modifier.height(20.dp))
        Text(s.signingIn, color = TextC, fontSize = 22.sp, fontWeight = FontWeight.Bold)
        if (vm.host.value.isNotBlank()) {
            Spacer(Modifier.height(6.dp))
            Text(vm.host.value, color = TextDim, fontSize = 13.sp, fontFamily = FontFamily.Monospace)
        }
        Spacer(Modifier.height(28.dp))
        Text(
            s.editCreds, color = TextDim, fontSize = 13.sp,
            modifier = Modifier.clickable { vm.editConnection() }.padding(8.dp),
        )
    }
}

@Composable
private fun BottomBar(route: String, accent: Color, onSelect: (String) -> Unit) {
    val s = LocalStrings.current
    // Nav sits on Bg (not a Surface bar) with no pill indicator, so it reads as a
    // separate row of icons below the floating input — matching the mockup.
    NavigationBar(containerColor = Bg) {
        TABS.forEach { tab ->
            val selected = route == tab.route
            val label = when (tab.route) {
                "chat" -> s.tabChat
                "agents" -> s.tabAgents
                "journal" -> s.tabJournal
                else -> s.tabMore
            }
            NavigationBarItem(
                selected = selected,
                onClick = { if (!selected) onSelect(tab.route) },
                icon = { Icon(tab.icon, label) },
                label = { Text(label) },
                colors = NavigationBarItemDefaults.colors(
                    selectedIconColor = accent,
                    selectedTextColor = accent,
                    indicatorColor = Color.Transparent,
                    unselectedIconColor = TextDim,
                    unselectedTextColor = TextDim,
                ),
            )
        }
    }
}
