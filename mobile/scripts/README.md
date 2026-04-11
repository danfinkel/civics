# CivicLens mobile scripts (Week 3 dev workflow)

## Physical iPhone: stable app + model (opens from home screen)

**Use this when you want the app to run like a normal install** — including **tapping the icon** (and after force-quit). **Debug** builds use **JIT** on device; they often work with **Product → Run** but **crash on cold start from the home screen**. **Profile** or **Release** uses **AOT** and avoids that.

**Blessed sequence**

1. **Build / refresh config from the repo**

   ```bash
   cd mobile
   ./scripts/dev_deploy.sh
   ```

   This writes `lib/core/config/model_config.dart`, runs `flutter build ios` (default **debug**), and does **not** install by default.

2. **Install on the phone from Xcode with Profile or Release**

   - Open **`ios/Runner.xcworkspace`** in Xcode.
   - Select your **iPhone** in the toolbar.
   - **Product → Scheme → Edit Scheme…** → **Run** (left sidebar) → **Info** tab → set **Build Configuration** to **Profile** or **Release** (not Debug).
   - **Product → Run** (▶).

   Xcode builds and installs that configuration on the device (it may compile **Profile/Release** even if step 1 produced a debug build — that’s fine).

3. **Copy the GGUF into the app’s Documents** (skip the in-app download UI)

   ```bash
   ./scripts/dev_deploy.sh --push-model
   ```

   Optional: `MODEL_PATH=/path/to/gemma-4-E2B-it-Q4_K_M.gguf ./scripts/dev_deploy.sh --push-model`  
   Requires the app to **already** be on the device (step 2), **Xcode 15+** (`devicectl`), and the phone **unplugged or connected** per your usual pairing.

**After you delete the app or get a fresh install**, iOS uses a **new data container** — run **step 3 again** (and step 2 first if the app isn’t installed).

### Hot reload / hot restart (after you used Profile or Release)

- **Profile** and **Release** are **AOT** — there is no `r` / `R` hot reload. For fast iteration, switch back to **Debug**.
- In Xcode: **Product → Scheme → Edit Scheme… → Run → Build Configuration → Debug**, then **Product → Run** (same as before, but **Debug**). Use **`r`** (reload) / **`R`** (restart) in the **debug console**, or **`./scripts/dev_deploy.sh --attach-only`** / **`ios_attach_usb.sh`** if you attach from another terminal (see **Quick iteration loop** and attach troubleshooting below).
- **The GGUF is not re-downloaded** on hot reload — it only reloads Dart. The file stays in **Documents** until you delete the app or wipe data; you do **not** need **`--push-model`** again for normal code edits.

---

## Quick iteration loop

1. **Terminal A — serve the GGUF** (same Wi‑Fi as your iPhone):

   ```bash
   cd mobile
   chmod +x scripts/serve_model.sh
   ./scripts/serve_model.sh
   ```

   Optional: `MODEL_PATH=/path/to/gemma-4-E2B-it-Q4_K_M.gguf ./scripts/serve_model.sh`  
   Optional: `PORT=9000 ./scripts/serve_model.sh`

2. **Set download URL for the phone** — loopback does **not** work from a physical device. Use your Mac’s LAN IP:

   ```bash
   export MODEL_SERVER_URL=http://192.168.1.42:8888   # example
   ```

3. **Terminal B — build, then Xcode Run, then attach (default)**

   By default **`dev_deploy.sh` does not run `flutter install`** (avoids flaky `devicectl` on some macOS 26 / Xcode 26 setups). Typical loop:

   ```bash
   cd mobile
   chmod +x scripts/dev_deploy.sh
   ./scripts/dev_deploy.sh                 # debug build + model_config (no install)
   # Xcode: open ios/Runner.xcworkspace → select iPhone → Product → Run
   ./scripts/dev_deploy.sh --attach-only   # hot reload (r) / hot restart (R) in this terminal
   ```

   Optional flags:

   ```bash
   ./scripts/dev_deploy.sh --release       # release build (still no install unless you add --install)
   ./scripts/dev_deploy.sh --eval          # --dart-define=EVAL_MODE=true
   ./scripts/dev_deploy.sh --install       # opt back into flutter install after build
   export DEV_DEPLOY_INSTALL=1             # always install after build
   ```

   **`--eval` (model QA / automation)** — Passes `--dart-define=EVAL_MODE=true`. The app then shows evidence excerpts, per-row confidence badges, and confidence-based compliance headlines (resident builds hide those). This flag is enough for eval-oriented builds; **putting the `.app` on a phone** is unchanged: default is still **no** `flutter install`, so use **Xcode → Run**, **`--install`**, or CI — not because `--eval` is unsupported, but because device install is environment-specific.

   **Bump the iOS build number** (the `+14` part in `pubspec.yaml` → `+15`, etc.) before each build — needed when you upload to TestFlight/App Store Connect, optional for USB-only testing:

   ```bash
   ./scripts/dev_deploy.sh --bump-build
   ./scripts/dev_deploy.sh --release --bump-build
   ```

   For a whole week of iteration without typing the flag each time:

   ```bash
   export DEV_DEPLOY_BUMP_BUILD=1
   ```

   The deploy summary at the end prints the current `version:` line so you can confirm.

   **Skip the in-app “Download Now” tap** (copy ~3GB GGUF over USB / wireless debugging with Xcode 15+):

   ```bash
   ./scripts/dev_deploy.sh --push-model
   MODEL_PATH=/path/to/gemma-4-E2B-it-Q4_K_M.gguf ./scripts/dev_deploy.sh --push-model
   ```

   This uses `xcrun devicectl` to place the file in the app’s **Documents** folder (same location `ModelManager` uses). The app must already be on the device (**Xcode → Run** or **`--install`**). Needs **Xcode 15+** (`devicectl`). To always push: `export DEV_DEPLOY_PUSH_MODEL=1`.

   Optional: `DEVICE_ID=<flutter-device-id> ./scripts/dev_deploy.sh --release`

## What each script does

| Script | Purpose |
|--------|---------|
| **`dev_deploy.sh`** | Writes `model_config.dart`, optional `flutter clean`, **`flutter build ios`**. **Default: skips `flutter install`** — use **Xcode → Run** then **`--attach-only`** for hot reload. **`--install`** / **`DEV_DEPLOY_INSTALL=1`** restores CLI install. **`--attach-only`** runs **`flutter attach`**. **`--bump-build`**, **`--push-model`**: same as before. |
| **`serve_model.sh`** | Validates GGUF path, runs `serve_model_http.py` on port **8888** with **`GET /health`** → `{"status":"ok"}` and **`GET /<filename>`** for the model binary. |
| **`sync_test_assets.sh`** | Prints which planned demo images exist under `assets/test_docs/` or `spike/`, and gives manual steps to get them into **Photos** on the phone. |

## `flutter install` failed (“Could not install … Runner.app”)

Usually **signing** or **Developer Mode**, not Flutter itself.

1. **Developer Mode** — iPhone: **Settings → Privacy & Security → Developer Mode** → On (reboot if prompted).
2. **Signing** — Open **`ios/Runner.xcworkspace`** in Xcode → **Runner** target → **Signing & Capabilities** → enable **Automatically manage signing** and select **your** Apple ID team. If the project still references another org’s team, Xcode will warn until you pick a team you belong to.
3. **USB** — Use a cable for flaky wireless installs.
4. **Clean state** — Delete **CivicLens** on the phone, keep the phone **unlocked**, then run `dev_deploy.sh` again.
5. **See the real error** — `FLUTTER_INSTALL_VERBOSE=1 ./scripts/dev_deploy.sh --install` (add your usual flags).
6. **Fallback** — Xcode: select your iPhone in the toolbar → **Product → Run**.

### macOS 26 / Xcode 26 (`flutter install` works in Xcode but not in the terminal)

On **macOS Tahoe (26.x)** with **Xcode 26**, `flutter install` / `flutter run` sometimes fails even when **signing is fine**, because the CLI path uses Apple’s **`devicectl`** and a few OS/Xcode combinations were buggy. The stack trace that ends in `InstallCommand._installApp` is **not** the real error — scroll **up** in the log for **`devicectl`**, **`CoreDeviceError`**, or **`Connection unexpectedly closed`**.

**What often works:**

1. **Pairing** — Xcode → **Window → Devices and Simulators** → right‑click the iPhone → **Unpair Device** → unplug/replug → **Trust** (repeat trust if prompted).
2. **Developer Disk Images** — in Terminal: `xcrun devicectl manage ddis update` (then try deploy again).
3. **Hybrid workflow** — **`./scripts/dev_deploy.sh`** (build). Open **`ios/Runner.xcworkspace`**, **Product → Run**. Then **`./scripts/dev_deploy.sh --attach-only`** (or `flutter attach -d <id>`).
4. **Toolchain** — Apple/Flutter fixes land in newer Xcode/macOS builds; if installs are still broken, update **Xcode** (and macOS when practical).

Upstream discussion (for context): [flutter/flutter#179234](https://github.com/flutter/flutter/issues/179234).

### `flutter attach` / “Dart VM Service was not discovered”

Discovery uses **mDNS** on the LAN. Fix **all** of these that apply:

1. **iPhone: Settings → CivicLens → Local Network** → **On**. Reinstall from Xcode if the app doesn’t appear in the list.
2. **Mac: System Settings → Privacy & Security → Local Network** → enable for **Terminal** (or **iTerm**, **Cursor**, whichever runs `flutter attach`). Without this, the Mac never sees the phone’s advertisement.
3. **Xcode scheme** — The shared **Runner** scheme passes **`--vm-service-host=0.0.0.0`** on launch so the VM service is reachable from the network (not only loopback). **Product → Run** again after pulling this change.
4. **USB** — `FLUTTER_ATTACH_USB=1 ./scripts/dev_deploy.sh --attach-only` (still helps when the device is both wired and on Wi‑Fi).
5. **Manual URL (bypass mDNS)** — With the app running from Xcode, copy the **`http://127.0.0.1:PORT/...=`** line from the debug console.
   - **If `flutter attach --debug-url "http://<phone-IP>:PORT/..."` says connection refused:** the VM is only on the device’s **loopback**, not on Wi‑Fi. Don’t use the phone IP unless **`--vm-service-host=0.0.0.0`** is really active (shared **Runner** scheme includes it — clean build + Run again).
   - **Reliable fix: USB + `iproxy`** — install **`brew install libimobiledevice`**, plug in the phone, keep the app running, then:
     ```bash
     ./scripts/ios_attach_usb.sh 'http://127.0.0.1:51381/qGWcLg5GKTg=/'
     ```
     Use the **exact** URL from Xcode (port and `/…=/` change each launch). The script forwards `Mac localhost:PORT → device:PORT` and runs **`flutter attach --device-connection attached --no-dds --host-vmservice-port PORT`**. You need both: **`--no-dds`** avoids DDS picking another port; **`--host-vmservice-port`** stops Flutter from opening a *second* port forward (e.g. `:62707`) on top of `iproxy`.

   - **`idevice_id -l` is empty** (but Xcode sees the phone): On recent macOS, Homebrew **libimobiledevice** often stops listing devices even though Apple’s **usbmuxd** is fine. Install **`pymobiledevice3`** and use it as the tunnel — **`ios_attach_usb.sh` does this automatically** when `idevice_id` is empty:
     ```bash
     python3 -m pip install -U pymobiledevice3
     pymobiledevice3 usbmux list --simple -u
     ./scripts/ios_attach_usb.sh 'http://127.0.0.1:PORT/...='
     ```
     To force it: **`ATTACH_USB_TUNNEL=pymobiledevice3 ./scripts/ios_attach_usb.sh '…'`**. To stay on Homebrew only: **`brew upgrade libimobiledevice libusbmuxd`**, different USB port/cable, **uncheck “Connect via network”** in Xcode → Devices, or **`sudo killall usbmuxd`** (macOS restarts it; you may need to Trust again).

   - **`iproxy` logs `No connected/matching device found` / attach says connection closed before header:** TCP reached `iproxy`, but **usbmux** could not relay to the phone. Check **`idevice_id -l`**: if **non-empty** but forward still fails, try **`IPROXY_NO_UDID=1`**, **`IPROXY_VERBOSE=1`**, and **uncheck “Connect via network”** for that iPhone. If **`idevice_id` is empty**, use **`pymobiledevice3`** as above instead of `iproxy`.

**Note:** The **“after 30 seconds”** line is a *spinner warning* from Flutter, not always a hard timeout; **`--device-timeout 180`** still applies. If it eventually errors out, use steps 2–5.

## Generated / local files

- **`lib/core/config/model_config.dart`** — overwritten by `dev_deploy.sh`. Template: `model_config.example.dart`.
- **`.pubspec_hash`** — md5 of `pubspec.yaml`; when it changes, `dev_deploy.sh` runs `flutter clean`.

## References

- Week 3 Agent 1 plan: `docs/sprint/week3/plans/agent1_plan.md`
- Human QA template: `docs/sprint/week3_human_qa.md`
