#!/usr/bin/env bash
# One-shot: regenerate model_config.dart, optional flutter clean, build iOS, optional install / attach.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MOBILE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$MOBILE_DIR"

RELEASE=0
EVAL=0
PUSH_MODEL=0
BUMP_BUILD=0
INSTALL=0
ATTACH_ONLY=0
[[ "${DEV_DEPLOY_PUSH_MODEL:-}" == "1" ]] && PUSH_MODEL=1
[[ "${DEV_DEPLOY_BUMP_BUILD:-}" == "1" ]] && BUMP_BUILD=1
[[ "${DEV_DEPLOY_INSTALL:-}" == "1" ]] && INSTALL=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --release) RELEASE=1 ;;
    --eval) EVAL=1 ;;
    --push-model) PUSH_MODEL=1 ;;
    --bump-build) BUMP_BUILD=1 ;;
    --install) INSTALL=1 ;;
    --attach-only) ATTACH_ONLY=1 ;;
    -h|--help)
      echo "Usage: $0 [--release] [--eval] [--push-model] [--bump-build] [--install] [--attach-only]"
      echo ""
      echo "Default workflow (no flutter install — good when devicectl/install is flaky):"
      echo "  1) $0 [--release]   → build + write model_config"
      echo "  2) Xcode: open ios/Runner.xcworkspace → Product → Run on the iPhone"
      echo "  3) $0 --attach-only → hot reload / hot restart in this terminal"
      echo ""
      echo "  --release     flutter build ios --release (install mode: --release with --install)"
      echo "  --eval        pass --dart-define=EVAL_MODE=true"
      echo "  --install     run flutter install after build (opt-in; default is skip)"
      echo "  --attach-only only run: flutter attach -d <device> (after Xcode Run)"
      echo "  --push-model  copy local GGUF into app Documents/ via devicectl (app must exist on device)"
      echo "  --bump-build  increment pubspec build number (1.0.4+14 → +15) before build;"
      echo "                use before TestFlight uploads. Or: export DEV_DEPLOY_BUMP_BUILD=1"
      echo ""
      echo "Env:"
      echo "  DEVICE_ID                Flutter device id (default: first physical iOS)"
      echo "  MODEL_SERVER_URL         Base URL for GGUF (default: http://localhost:8888)"
      echo "  MODEL_FILENAME           default: gemma-4-E2B-it-Q4_K_M.gguf"
      echo "  MODEL_PATH               local GGUF for --push-model (else ios/, assets/models/, ~/Downloads/)"
      echo "  IOS_BUNDLE_ID            default: com.example.civiclens"
      echo "  DEV_DEPLOY_PUSH_MODEL    set to 1 to always --push-model"
      echo "  DEV_DEPLOY_BUMP_BUILD    set to 1 to bump build every run"
      echo "  DEV_DEPLOY_INSTALL       set to 1 to always run flutter install after build"
      echo "  FLUTTER_INSTALL_VERBOSE  set to 1 for flutter -v install"
      echo "  FLUTTER_ATTACH_USB       set to 1 with --attach-only to use USB only (helps VM discovery)"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
  shift
done

resolve_physical_ios_device() {
  DEVICE_ID="${DEVICE_ID:-}"
  if [[ -z "$DEVICE_ID" ]]; then
    DEVICE_ID=$(flutter devices --machine 2>/dev/null | python3 -c "
import json, sys
data = json.load(sys.stdin)
for d in data:
    if d.get('targetPlatform') == 'ios' and not d.get('emulator', True):
        print(d['id'])
        sys.exit(0)
sys.exit(1)
" || true)
  fi
  if [[ -z "$DEVICE_ID" ]]; then
    echo "ERROR: No physical iOS device found. Connect iPhone or set DEVICE_ID."
    flutter devices
    return 1
  fi
  return 0
}

if [[ "$ATTACH_ONLY" -eq 1 ]]; then
  if ! resolve_physical_ios_device; then
    exit 1
  fi
  IOS_BUNDLE_ID="${IOS_BUNDLE_ID:-com.example.civiclens}"
  echo "==> Attaching to $DEVICE_ID (hot reload: r, hot restart: R, quit: q)"
  echo "    “Waiting for a connection…” can sit there **up to ~3 min** on Wi‑Fi; success looks like"
  echo "    “Flutter run key commands” / a Dart VM URI — not frozen, just slow discovery."
  echo "    Keep the app **open in foreground** on the phone (launched from Xcode)."
  echo "    If it never connects: Settings → CivicLens → Local Network → ON; or USB +"
  echo "    FLUTTER_ATTACH_USB=1 $0 --attach-only"
  echo "    Mac: System Settings → Privacy & Security → Local Network → ON for Terminal (or Cursor)."
  echo "    If mDNS never works: Xcode console → copy http://127.0.0.1:PORT/...= then:"
  echo "    ./scripts/ios_attach_usb.sh 'PASTE_URL_HERE'   # handles --no-dds + port forward"
  echo "    Verbose:  flutter attach -d \"$DEVICE_ID\" --app-id \"$IOS_BUNDLE_ID\" --device-timeout 180 -v"
  ATTACH_ARGS=(flutter attach -d "$DEVICE_ID" --app-id "$IOS_BUNDLE_ID" --device-timeout 180)
  [[ "${FLUTTER_ATTACH_USB:-}" == "1" ]] && ATTACH_ARGS+=(--device-connection attached)
  exec "${ATTACH_ARGS[@]}"
fi

bump_pubspec_build() {
  python3 - "$MOBILE_DIR/pubspec.yaml" << 'PY'
import pathlib, re, sys

path = pathlib.Path(sys.argv[1])
text = path.read_text()
lines = text.splitlines(keepends=True)
out = []
done = False
for line in lines:
    raw = line
    line_nl = raw.rstrip("\n")
    m = re.match(r"^version:\s*([\d.]+)\+(\d+)\s*$", line_nl)
    if m and not done:
        v, b = m.group(1), int(m.group(2)) + 1
        # preserve original newline style
        suffix = raw[len(line_nl) :]
        if not suffix:
            suffix = "\n"
        out.append(f"version: {v}+{b}{suffix}")
        done = True
    else:
        out.append(raw)
if not done:
    print(
        "ERROR: pubspec.yaml must have a line like: version: 1.0.4+14",
        file=sys.stderr,
    )
    sys.exit(1)
path.write_text("".join(out))
for s in out:
    if s.startswith("version:"):
        print(f"==> Bumped {s.strip()}")
        break
PY
}

if [[ "$BUMP_BUILD" -eq 1 ]]; then
  bump_pubspec_build
fi

MODEL_SERVER_URL="${MODEL_SERVER_URL:-http://localhost:8888}"
MODEL_FILENAME="${MODEL_FILENAME:-gemma-4-E2B-it-Q4_K_M.gguf}"
# Trim trailing slash
MODEL_SERVER_URL="${MODEL_SERVER_URL%/}"

CONFIG_DIR="$MOBILE_DIR/lib/core/config"
CONFIG_OUT="$CONFIG_DIR/model_config.dart"
mkdir -p "$CONFIG_DIR"

echo "==> Checking model server (optional)"
if curl -sf "${MODEL_SERVER_URL}/health" | grep -q 'ok'; then
  echo "    Health OK: ${MODEL_SERVER_URL}/health"
else
  echo "    WARN: ${MODEL_SERVER_URL}/health not reachable (start scripts/serve_model.sh?)"
fi

DOWNLOAD_URL="${MODEL_SERVER_URL}/${MODEL_FILENAME}"
echo "==> Writing $CONFIG_OUT"
cat > "$CONFIG_OUT" << EOF
// Auto-generated by dev_deploy.sh — do not edit manually
const String kModelDownloadUrl = '$DOWNLOAD_URL';
const String kModelFilename = '$MODEL_FILENAME';
EOF

if [[ "$MODEL_SERVER_URL" == *"127.0.0.1"* || "$MODEL_SERVER_URL" == *"localhost"* ]]; then
  echo ""
  echo "NOTE: kModelDownloadUrl uses loopback. For a physical iPhone, set MODEL_SERVER_URL"
  echo "      to http://<your-mac-lan-ip>:8888 (same Wi‑Fi as the phone)."
  echo ""
fi

PUBSPEC_HASH_FILE="$MOBILE_DIR/.pubspec_hash"
if command -v md5 >/dev/null 2>&1; then
  CURRENT_HASH=$(md5 -q pubspec.yaml)
elif command -v md5sum >/dev/null 2>&1; then
  CURRENT_HASH=$(md5sum pubspec.yaml | awk '{print $1}')
else
  CURRENT_HASH=""
fi
STORED_HASH=""
[[ -f "$PUBSPEC_HASH_FILE" ]] && STORED_HASH=$(cat "$PUBSPEC_HASH_FILE" || true)

if [[ -n "$CURRENT_HASH" ]]; then
  if [[ "$CURRENT_HASH" != "$STORED_HASH" ]]; then
    echo "==> pubspec.yaml changed — flutter clean + pub get"
    flutter clean
    flutter pub get
    echo "$CURRENT_HASH" > "$PUBSPEC_HASH_FILE"
  else
    echo "==> pubspec unchanged — skipping flutter clean"
    flutter pub get
  fi
else
  echo "==> md5 not available — skipping hash-based clean"
  flutter pub get
fi

if ! resolve_physical_ios_device; then
  exit 1
fi

# Default: debug (fast iteration). Use --release for store-like / demo recording.
BUILD_CMD=(flutter build ios --debug)
if [[ "$RELEASE" -eq 1 ]]; then
  BUILD_CMD=(flutter build ios --release)
fi
# Avoid "${arr[@]}" on empty array with set -u (bash 5+ / some configs treat as unbound).
if [[ "$EVAL" -eq 1 ]]; then
  BUILD_CMD+=(--dart-define=EVAL_MODE=true)
fi

echo "==> Building: ${BUILD_CMD[*]}"
set +e
BUILD_LOG=$(mktemp)
"${BUILD_CMD[@]}" 2>&1 | tee "$BUILD_LOG"
BUILD_STATUS=${PIPESTATUS[0]}
set -e
if [[ "$BUILD_STATUS" -ne 0 ]]; then
  echo ""
  echo "ERROR: flutter build failed (exit $BUILD_STATUS). See log above."
  grep -E "Error:|error ·|BUILD FAILED" "$BUILD_LOG" || true
  rm -f "$BUILD_LOG"
  exit "$BUILD_STATUS"
fi
rm -f "$BUILD_LOG"

INSTALL_CMD=(flutter install -d "$DEVICE_ID")
if [[ "$RELEASE" -eq 1 ]]; then
  INSTALL_CMD+=(--release)
else
  INSTALL_CMD+=(--debug)
fi
if [[ "${FLUTTER_INSTALL_VERBOSE:-}" == "1" ]]; then
  INSTALL_CMD=(flutter -v install -d "$DEVICE_ID")
  if [[ "$RELEASE" -eq 1 ]]; then
    INSTALL_CMD+=(--release)
  else
    INSTALL_CMD+=(--debug)
  fi
fi

ios_install_troubleshooting() {
  echo ""
  echo "========== iOS install troubleshooting =========="
  echo "1. iPhone: Settings → Privacy & Security → Developer Mode → On (reboot if it asks)."
  echo "2. Xcode: open ios/Runner.xcworkspace → select Runner → Signing & Capabilities:"
  echo "   turn on \"Automatically manage signing\" and choose YOUR Apple team."
  echo "   (If you see team errors, the project may point at another org’s team ID — pick Personal Team.)"
  echo "3. Prefer USB for install; wireless debugging can fail mid-transfer."
  echo "4. On the phone, delete CivicLens manually, unlock the phone, trust this Mac, then re-run."
  echo "5. Real error is ABOVE the Dart stack trace: search the log for devicectl, CoreDeviceError, or codesign."
  echo "   Try:  FLUTTER_INSTALL_VERBOSE=1 ./scripts/dev_deploy.sh   (or  -vv  for even more)"
  echo "6. Fallback: Xcode → pick your iPhone → Product → Run. If that works, toolchain signing is OK."
  MACOS_MAJOR="$(sw_vers -productVersion 2>/dev/null | cut -d. -f1 || true)"
  if [[ "$MACOS_MAJOR" == "26" ]]; then
    echo ""
    echo "macOS 26 note: flutter install uses Apple’s devicectl; some Xcode 26.x builds fail here while"
    echo "  Xcode Run still works. Workaround: build with this script, install once via Xcode Run, then"
    echo "  use  flutter attach -d <device>  for hot reload. Updating Xcode/macOS often fixes it — see"
    echo "  mobile/scripts/README.md (\"macOS 26 / Xcode 26\")."
  fi
  echo "==============================================="
}

if [[ "$INSTALL" -eq 1 ]]; then
  echo "==> Installing: ${INSTALL_CMD[*]}"
  set +e
  "${INSTALL_CMD[@]}"
  INSTALL_STATUS=$?
  set -e
  if [[ "$INSTALL_STATUS" -ne 0 ]]; then
    echo ""
    echo "ERROR: flutter install failed (exit $INSTALL_STATUS)."
    ios_install_troubleshooting
    exit "$INSTALL_STATUS"
  fi
else
  echo "==> Skipping flutter install (default). Use --install to run it, or Xcode → Run then:"
  echo "    ./scripts/dev_deploy.sh --attach-only"
fi

IOS_BUNDLE_ID="${IOS_BUNDLE_ID:-com.example.civiclens}"

resolve_gguf_path() {
  local p="${MODEL_PATH:-}"
  if [[ -n "$p" && -f "$p" ]]; then
    echo "$p"
    return 0
  fi
  for candidate in \
    "$MOBILE_DIR/ios/$MODEL_FILENAME" \
    "$MOBILE_DIR/assets/models/$MODEL_FILENAME" \
    "$HOME/Downloads/$MODEL_FILENAME"
  do
    if [[ -f "$candidate" ]]; then
      echo "$candidate"
      return 0
    fi
  done
  return 1
}

if [[ "$PUSH_MODEL" -eq 1 ]]; then
  echo "==> Pushing GGUF to device (devicectl → app Documents/)"
  GGUF_PATH=""
  if GGUF_PATH=$(resolve_gguf_path); then
    echo "    Source: $GGUF_PATH"
  else
    echo "ERROR: No local GGUF for --push-model. Set MODEL_PATH or place file at:"
    echo "       $MOBILE_DIR/ios/$MODEL_FILENAME (etc.)"
    exit 1
  fi
  if ! xcrun devicectl device copy to --help >/dev/null 2>&1; then
    echo "ERROR: devicectl not available (need Xcode 15+ Command Line Tools)."
    exit 1
  fi
  # Large file: allow long transfer (Wi‑Fi debugging can be slow).
  if ! xcrun devicectl device copy to \
    --device "$DEVICE_ID" \
    --source "$GGUF_PATH" \
    --destination "Documents/$MODEL_FILENAME" \
    --domain-type appDataContainer \
    --domain-identifier "$IOS_BUNDLE_ID" \
    --timeout 14400; then
    echo ""
    echo "ERROR: devicectl copy failed. Tips:"
    echo "  - Unlock the iPhone; trust this Mac if prompted."
    echo "  - DEVICE_ID must be the same UDID Flutter uses (flutter devices)."
    echo "  - Re-run install first if you changed IOS_BUNDLE_ID or deleted the app."
    exit 1
  fi
  echo "    OK: Documents/$MODEL_FILENAME on device (bundle $IOS_BUNDLE_ID)"
  echo "    Note: Push targets the *current* app data container. If you delete the app or get a"
  echo "    fresh install (new container UUID), run --push-model again before relying on the file."
fi

MODE="debug"
[[ "$RELEASE" -eq 1 ]] && MODE="release"
EVAL_NOTE="off"
[[ "$EVAL" -eq 1 ]] && EVAL_NOTE="EVAL_MODE=true"

echo ""
echo "========== dev_deploy summary =========="
echo "Device:     $DEVICE_ID"
echo "Build:      ios $MODE"
echo "Dart def:   $EVAL_NOTE"
if [[ -f "$MOBILE_DIR/pubspec.yaml" ]]; then
  echo "Version:    $(grep -m1 '^version:' "$MOBILE_DIR/pubspec.yaml" | tr -d '\r' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
fi
echo "Model URL:  $DOWNLOAD_URL"
if [[ "$INSTALL" -eq 1 ]]; then
  echo "Install:    flutter install (completed)"
else
  echo "Install:    skipped (default) — Xcode → Run, then: ./scripts/dev_deploy.sh --attach-only"
fi
if [[ "$PUSH_MODEL" -eq 1 ]]; then
  echo "Model push: devicectl → Documents/$MODEL_FILENAME (skip Download in app)"
else
  echo "Next:       ./scripts/dev_deploy.sh --push-model copies GGUF via USB (no Download tap),"
  echo "            or launch app → Download Now (HTTP). LAN URL + serve_model.sh for HTTP path."
fi
echo "Tests:      cd mobile && flutter test"
echo "Audit list: docs/sprint/week3/plans/agent1_plan.md (Acceptance Criteria)"
echo "========================================"
