# ClawNest for iPhone (sideload build)

A native **SwiftUI** port of the ClawNest Android client. Same idea: the phone is a thin
client to your self-hosted `openclaw` agent on your VPS, reached over an **on-device SSH
tunnel** (no public port, no cloud). Distribute it **without the App Store** by sideloading.

```
iPhone (SwiftUI)  ──SSH (Citadel/SwiftNIO)──▶  your VPS
  thin client                                  ├─ local port-forward ──▶ openclaw agent (ws)
  no cloud, no domain                          └─ agent drives Claude Code via claude-agent-sdk
```

The **backend is unchanged** — this app runs the same `backend/openclaw_agent` and the same
`provision.sh` (bundled here as `ClawNest/Resources/provision.sh`) as the Android app.

---

## What maps to what

| Android (Kotlin) | iOS (Swift) |
|---|---|
| `SshLink.kt` (JSch) | `Net/SSHTunnel.swift` + `Net/ForwardHandler.swift` (Citadel / SwiftNIO) |
| `OpenClawClient.kt` (OkHttp WS) | `Net/OpenClawClient.swift` + `URLSessionWSChannel` |
| `Models.kt` / `ChatModel.kt` | `Model/Protocol.swift` / `Model/ChatModel.swift` |
| `AppViewModel.kt` | `ViewModel/AppViewModel.swift` |
| Compose screens | `Views/*.swift` (SwiftUI) |
| SharedPreferences | `Model/Store.swift` (UserDefaults + Keychain for secrets) |

---

## Requirements

- A **Mac with Xcode 15+** (the full app, not just Command Line Tools) — required to build,
  sign and install any iOS app.
- An **Apple ID** (free is enough for sideloading; a paid Apple Developer account gives
  longer-lived signatures).
- An **iPhone** (iOS 16+).

> This project was scaffolded on a machine **without Xcode**, so the SSH/NIO layer
> (`SSHTunnel.swift`, `ForwardHandler.swift`) could not be compiled here. The pure app
> logic (protocol, view model, mock transport) *was* type-checked. See **Caveats** below.

---

## 1. Generate the Xcode project

Two options.

### Option A — XcodeGen (recommended)
```bash
brew install xcodegen
cd ios
xcodegen generate          # reads project.yml → ClawNest.xcodeproj
open ClawNest.xcodeproj
```

### Option B — by hand in Xcode
1. **File ▸ New ▸ Project ▸ iOS App**, name `ClawNest`, interface **SwiftUI**, language **Swift**.
2. Delete the template `ContentView.swift` / `App.swift`, then drag the `ClawNest/` folder
   from this repo into the project (**Copy items if needed**, create groups).
3. Make sure `Resources/provision.sh` is in **Target ▸ Build Phases ▸ Copy Bundle Resources**.
4. **File ▸ Add Package Dependencies…** and add:
   - `https://github.com/orlandos-nl/Citadel.git` (product **Citadel**)
   - `https://github.com/apple/swift-nio.git` (products **NIOCore**, **NIOPosix**)
5. Use the `App/Info.plist` from this repo (it allows plaintext `ws://` to `127.0.0.1` only,
   which is the local end of the SSH tunnel).

## 2. Sign it

In Xcode ▸ target **ClawNest** ▸ **Signing & Capabilities**:
- Set **Team** to your Apple ID (add it under Xcode ▸ Settings ▸ Accounts if needed).
- Keep **Automatically manage signing** on. Xcode will make a provisioning profile.
- If the bundle id `com.openclaw.clawnest` is taken, change it to something unique
  (e.g. `com.<you>.clawnest`).

## 3. Install without the App Store

Pick one:

### AltStore / SideStore (free Apple ID)
1. Install **AltServer** on your Mac (or SideStore on the phone), from `altstore.io`.
2. In Xcode: **Product ▸ Archive**, then **Distribute App ▸ Custom ▸ Ad Hoc / Development ▸
   Export** to get a `ClawNest.ipa` (or use `Debug` build straight to the device).
3. Open the `.ipa` with AltStore on the phone to install.
- Free Apple ID: the signature **expires after 7 days** — AltStore/SideStore re-sign
  automatically over Wi-Fi while they're running. Paid dev account: valid for a year.

### Sideloadly (free Apple ID)
1. Install **Sideloadly** (`sideloadly.io`) on the Mac/PC.
2. Plug in the iPhone, drag in the `.ipa` (or point it at the archive), enter your Apple ID,
   **Start**. Same 7-day/1-year rule as above.

### Just run it from Xcode
Plug in the iPhone, select it as the run destination, press **Run**. This installs the app
for as long as the signature is valid — the simplest path if you have the Mac in hand.

> On first launch, iOS may block the app: **Settings ▸ General ▸ VPN & Device Management ▸
> [your Apple ID] ▸ Trust**.

---

## Using it

1. Launch, fill in **Server IP**, **SSH user** (default `root`), **SSH password**, and
   optionally a **Claude key** (`sk-ant-oat…` or an API key).
2. Tap **Connect**. The app SSHes in, runs `provision.sh`, forwards the agent port and opens
   the chat. Creds are saved (Keychain) after the first good connect, so it reconnects itself.
3. Pick an agent → chat. Streaming replies, tool/terminal blocks and interactive questions
   all render live.

### Demo mode (no server)
Toggle **Demo mode** on the connect screen (default **on** in the iOS Simulator). It runs a
built-in `MockTunnel` + `MockWSChannel` so you can exercise the whole UI without a VPS — great
for testing the build before you have a server.

---

## Caveats / TODO (v1 MVP)

- **⚠️ Verify the Citadel API.** `SSHTunnel.swift` is written against Citadel's classic async
  API: `SSHClient.connect(host:port:authenticationMethod:hostKeyValidator:reconnect:)`,
  `executeCommand(_:maxResponseSize:mergeStreams:)`, and
  `createDirectTCPIPChannel(using:SSHChannelType.DirectTCPIP(...))`. If your resolved Citadel
  version renamed any of these, this one file is where to adjust. It could not be compiled off
  a Mac when scaffolded — **expect to fix a signature or two on first build.**
- **Port-forward.** `ForwardHandler.swift` glues the local loopback socket (that URLSession
  connects to) to the SSH direct-tcpip channel — the equivalent of JSch's `setPortForwardingL`.
  Backpressure is intentionally simple; fine for the small agent protocol.
- **Not yet ported:** file/photo attachments both ways (SFTP up/download throws
  `notImplemented` — the SFTP calls in `SSHTunnel.swift` are the stubs to fill in), the
  persona editor, the full audit-log screen, and background keep-alive. The core loop
  (connect → agents → streaming chat → questions → proactive push) is complete.
- **Proactive push** shows a **local** notification only while the app is running; true
  background push (APNs) isn't available to a sideloaded free-provisioned app.

---

Licensed under the [MIT License](../LICENSE), same as the rest of ClawNest.
