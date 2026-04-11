#!/usr/bin/env bash
# Attach to a running Debug app using USB port forwarding (works when Wi-Fi / mDNS fails).
#
# Usage:
#   ./scripts/ios_attach_usb.sh 'http://127.0.0.1:51381/qGWcLg5GKTg=/'
#
# Copy the exact URL from the Xcode debug console (keep 127.0.0.1 — the tunnel maps it to the phone).
#
# Tunnel backends (first match wins when ATTACH_USB_TUNNEL=auto):
#   - iproxy  — brew install libimobiledevice (when idevice_id -l lists your phone)
#   - pymobiledevice3 — python3 -m pip install -U pymobiledevice3 (often works when idevice_id is empty on new macOS)
#
# Env:
#   ATTACH_USB_TUNNEL=auto|iproxy|pymobiledevice3   (default: auto)
#   DEVICE_ID=...          Flutter / usbmux UDID if not inferred
#   FLUTTER_ATTACH_CONNECTION=attached|wireless|auto  (default: auto — wireless if usbmux only sees network pairing)
#   IPROXY_NO_UDID=1       iproxy: omit -u (single USB device)
#   PM3_NO_UDID=1          pymobiledevice3: omit --udid (single usbmux device)
#   IPROXY_VERBOSE=1       iproxy -d
#
# Note: pymobiledevice3 usbmux list --simple -u  is USB-only. [] often means the phone is paired
#   over Wi‑Fi only (Xcode still works). Try: pymobiledevice3 usbmux list --simple  (no -u).
#
# If iproxy logs "No connected/matching device found":
#   - Xcode → Devices and Simulators → iPhone → uncheck "Connect via network"
#   - Try ATTACH_USB_TUNNEL=pymobiledevice3 if idevice_id is empty
#
# Flow:
#   1) App running from Xcode (Debug) on a USB-connected iPhone
#   2) Run this script (starts a local TCP forward, then flutter attach)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MOBILE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$MOBILE_DIR"

URL="${1:-}"
if [[ -z "$URL" ]]; then
  echo "Usage: $0 'http://127.0.0.1:PORT/path='"
  echo "Example: $0 'http://127.0.0.1:51381/qGWcLg5GKTg=/'"
  exit 1
fi

# Parse port from http://127.0.0.1:PORT/...
PORT="$(python3 -c "
import urllib.parse, sys
p = urllib.parse.urlparse(sys.argv[1])
if p.port:
    print(p.port)
else:
    print('ERROR: no port in URL', file=sys.stderr)
    sys.exit(1)
" "$URL")" || exit 1

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
  echo "ERROR: No physical iOS device. Connect iPhone via USB or set DEVICE_ID."
  exit 1
fi

pm3() {
  if command -v pymobiledevice3 >/dev/null 2>&1; then
    pymobiledevice3 "$@"
  else
    python3 -m pymobiledevice3 "$@"
  fi
}

pm3_available() {
  command -v pymobiledevice3 >/dev/null 2>&1 || python3 -c "import pymobiledevice3" 2>/dev/null
}

# Last line of output should be a JSON array of UDIDs.
pm3_usb_udids_line() {
  pm3 usbmux list --simple -u 2>/dev/null | tail -n 1 || true
}

# USB + network/Wi‑Fi devices visible to usbmux (what Xcode often uses when "Connect via network" is on).
pm3_all_udids_line() {
  pm3 usbmux list --simple 2>/dev/null | tail -n 1 || true
}

json_array_nonempty() {
  local line="$1"
  [[ -z "$line" ]] && return 1
  echo "$line" | python3 -c "import json,sys; d=json.load(sys.stdin); sys.exit(0 if isinstance(d,list) and len(d)>0 else 1)" 2>/dev/null
}

json_array_contains_udid() {
  local line="$1"
  local udid="$2"
  echo "$line" | python3 -c "import json,sys; d=json.load(sys.stdin); u=sys.argv[1]; sys.exit(0 if u in d else 1)" "$udid" 2>/dev/null
}

IDEVE_IDS=""
if command -v idevice_id >/dev/null 2>&1; then
  IDEVE_IDS="$(idevice_id -l 2>/dev/null || true)"
fi
IDEVE_nonempty=0
[[ -n "${IDEVE_IDS//[$'\t\r\n ']/}" ]] && IDEVE_nonempty=1

PM3_LINE=""
PM3_nonempty=0
# usb = seen on USB usbmux; any = only non-USB (e.g. network) entries matched
PM3_USBMUX_VIA=""
if pm3_available; then
  PM3_LINE_USB="$(pm3_usb_udids_line)"
  PM3_LINE_ANY="$(pm3_all_udids_line)"
  if json_array_nonempty "$PM3_LINE_USB"; then
    PM3_LINE="$PM3_LINE_USB"
    PM3_nonempty=1
    PM3_USBMUX_VIA=usb
  elif json_array_nonempty "$PM3_LINE_ANY"; then
    PM3_LINE="$PM3_LINE_ANY"
    PM3_nonempty=1
    PM3_USBMUX_VIA=network
  fi
fi

TUNNEL="${ATTACH_USB_TUNNEL:-auto}"
BACKEND=""
case "$TUNNEL" in
  iproxy)
    BACKEND=iproxy
    ;;
  pymobiledevice3 | pm3)
    BACKEND=pymobiledevice3
    ;;
  auto)
    if [[ "$IDEVE_nonempty" -eq 1 ]]; then
      BACKEND=iproxy
    elif [[ "$PM3_nonempty" -eq 1 ]]; then
      BACKEND=pymobiledevice3
    else
      BACKEND=""
    fi
    ;;
  *)
    echo "ERROR: ATTACH_USB_TUNNEL must be auto, iproxy, or pymobiledevice3 (got: $TUNNEL)"
    exit 1
    ;;
esac

if [[ -z "$BACKEND" ]]; then
  echo "ERROR: No USB tunnel backend can see your iPhone."
  echo ""
  if [[ "$IDEVE_nonempty" -eq 1 ]]; then
    echo "  idevice_id -l:        OK"
  else
    echo "  idevice_id -l:        EMPTY (common on new macOS: Homebrew libimobiledevice vs Apple usbmuxd)"
  fi
  if [[ "$PM3_nonempty" -eq 1 ]]; then
    echo "  pymobiledevice3:        OK (unexpected — recheck script)"
  else
    echo "  pymobiledevice3 USB:    EMPTY (pymobiledevice3 usbmux list --simple -u → [])"
    echo "  pymobiledevice3 (any):  run: pymobiledevice3 usbmux list --simple"
  fi
  echo ""
  echo "Try in order:"
  echo "  1) Plug in the iPhone (USB) and unlock — list --simple -u stays [] until the cable path exists."
  echo "  2) pymobiledevice3 usbmux list --simple     # no -u: includes network-paired phones"
  echo "     If this is also []: Trust, Developer Mode, or try reboot Mac/phone."
  echo "  3) Xcode → Window → Devices → iPhone → try turning OFF \"Connect via network\","
  echo "     unplug/replug USB, unlock phone — then run: pymobiledevice3 usbmux list --simple -u"
  echo "  4) python3 -m pip install -U pymobiledevice3"
  echo "  5) brew update && brew upgrade libimobiledevice libusbmuxd"
  echo "  6) sudo killall usbmuxd   # macOS restarts it; you may need to Trust again"
  echo "  7) Skip this script: use Wi‑Fi mDNS attach (Local Network + vm-service-host; see scripts/README.md)"
  exit 1
fi

if [[ "$BACKEND" == "iproxy" ]]; then
  if ! command -v iproxy >/dev/null 2>&1; then
    echo "ERROR: iproxy not found. Install: brew install libimobiledevice"
    echo "  Or use: ATTACH_USB_TUNNEL=pymobiledevice3 (after: pip install pymobiledevice3)"
    exit 1
  fi
  if [[ "$IDEVE_nonempty" -eq 0 ]]; then
    echo "ERROR: ATTACH_USB_TUNNEL=iproxy but idevice_id -l is empty."
    echo "  Use ATTACH_USB_TUNNEL=pymobiledevice3 or fix Homebrew libimobiledevice / USB."
    exit 1
  fi
  if ! echo "$IDEVE_IDS" | tr -d '\r' | grep -Fq "$DEVICE_ID"; then
    echo "WARN: UDID $DEVICE_ID not in idevice_id -l:"
    echo "$IDEVE_IDS" | sed 's/^/  /'
    echo "  If forward fails, set DEVICE_ID from a line above or try IPROXY_NO_UDID=1 with one device."
  fi
fi

if [[ "$BACKEND" == "pymobiledevice3" ]]; then
  if ! pm3_available; then
    echo "ERROR: pymobiledevice3 not installed."
    echo "  python3 -m pip install -U pymobiledevice3"
    exit 1
  fi
  if [[ "$PM3_nonempty" -eq 0 ]]; then
    echo "ERROR: ATTACH_USB_TUNNEL=pymobiledevice3 but no devices in usbmux (try without -u):"
    echo "  pymobiledevice3 usbmux list --simple -u   # USB-only"
    echo "  pymobiledevice3 usbmux list --simple      # USB + network pairing"
    exit 1
  fi
  if ! json_array_contains_udid "$PM3_LINE" "$DEVICE_ID"; then
    echo "WARN: UDID $DEVICE_ID not in pymobiledevice3 usbmux list:"
    echo "  $PM3_LINE"
    echo "  If forward fails, set DEVICE_ID to a UDID from that JSON array or try PM3_NO_UDID=1 with one device."
  fi
fi

# flutter attach: match how the device is exposed (USB vs wireless) when not overridden.
FLUTTER_ATTACH_EXTRA=()
if [[ -n "${FLUTTER_ATTACH_CONNECTION:-}" ]]; then
  case "${FLUTTER_ATTACH_CONNECTION}" in
    attached) FLUTTER_ATTACH_EXTRA=(--device-connection attached) ;;
    wireless) FLUTTER_ATTACH_EXTRA=(--device-connection wireless) ;;
    auto | none | "") ;;
    *)
      echo "ERROR: FLUTTER_ATTACH_CONNECTION must be attached, wireless, auto, or none (got: ${FLUTTER_ATTACH_CONNECTION})"
      exit 1
      ;;
  esac
else
  if [[ "$BACKEND" == "pymobiledevice3" && "${PM3_USBMUX_VIA:-usb}" == "network" ]]; then
    FLUTTER_ATTACH_EXTRA=(--device-connection wireless)
  else
    FLUTTER_ATTACH_EXTRA=(--device-connection attached)
  fi
fi

FORWARD_PID=""
cleanup() {
  [[ -n "$FORWARD_PID" ]] && kill "$FORWARD_PID" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

echo "==> TCP forward: Mac localhost:$PORT → device:$PORT ($BACKEND)"
if [[ "$BACKEND" == "pymobiledevice3" && "${PM3_USBMUX_VIA:-usb}" == "network" ]]; then
  echo "    (usbmux path is network pairing — plug in USB if you expected a cable-only device)"
fi
echo "    Device: $DEVICE_ID"
if [[ "${#FLUTTER_ATTACH_EXTRA[@]}" -gt 0 ]]; then
  echo "==> flutter attach ${FLUTTER_ATTACH_EXTRA[*]} --debug-url --no-dds --host-vmservice-port $PORT"
else
  echo "==> flutter attach --debug-url --no-dds --host-vmservice-port $PORT"
fi

case "$BACKEND" in
  iproxy)
    echo "    (--no-dds: avoid extra local port for DDS)"
    echo "    (--host-vmservice-port: avoids a second forward conflicting with the tunnel)"
    IPROXY_EXTRA=()
    if [[ -n "${IPROXY_VERBOSE:-}" ]]; then
      IPROXY_EXTRA+=(-d)
    fi
    if [[ -n "${IPROXY_NO_UDID:-}" ]]; then
      echo "    (IPROXY_NO_UDID: iproxy without -u)"
      iproxy "${IPROXY_EXTRA[@]}" "$PORT:$PORT" &
    else
      iproxy "${IPROXY_EXTRA[@]}" -u "$DEVICE_ID" "$PORT:$PORT" &
    fi
    FORWARD_PID=$!
    ;;
  pymobiledevice3)
    if [[ -n "${PM3_NO_UDID:-}" ]]; then
      echo "    (PM3_NO_UDID: forward without --udid — single usbmux device only)"
      pm3 usbmux forward "$PORT" "$PORT" &
    else
      pm3 usbmux forward "$PORT" "$PORT" --udid "$DEVICE_ID" &
    fi
    FORWARD_PID=$!
    ;;
esac

sleep 1

flutter attach -d "$DEVICE_ID" "${FLUTTER_ATTACH_EXTRA[@]}" --debug-url "$URL" --no-dds --host-vmservice-port "$PORT"
