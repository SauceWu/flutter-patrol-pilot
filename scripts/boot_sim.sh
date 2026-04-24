#!/usr/bin/env bash
# boot_sim.sh — idempotent iOS simulator boot
# Usage: boot_sim.sh <device-name-or-udid>
# Stdout: single JSON object (never mixed with other text)
# Stderr: human-readable progress
# Exit 0: booted or already booted
# Exit 1: device not found
# Exit 2: boot timed out after 30s
set -euo pipefail

START_SECONDS=$SECONDS
DEVICE_INPUT="${1:-}"

# ── usage check ───────────────────────────────────────────────────────────────
if [ -z "$DEVICE_INPUT" ]; then
  printf '{"udid":null,"name":null,"state":"not_found","action":"failed","elapsed_s":0,"error":"Usage: boot_sim.sh <device-name-or-udid>"}\n'
  exit 1
fi

# ── tool checks ──────────────────────────────────────────────────────────────
for tool in xcrun python3; do
  if ! command -v "$tool" &>/dev/null; then
    printf '{"udid":null,"name":null,"state":"not_found","action":"failed","elapsed_s":0,"error":"Required tool not found: %s"}\n' "$tool"
    exit 1
  fi
done

JQ_AVAILABLE=false
command -v jq &>/dev/null && JQ_AVAILABLE=true

# ── UDID detection ───────────────────────────────────────────────────────────
# UDIDs are 36-char strings matching UUID format: XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX
IS_UDID=false
if echo "$DEVICE_INPUT" | grep -qE '^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}$'; then
  IS_UDID=true
fi

# ── lookup: find UDID + name + runtime key ───────────────────────────────────
# CRITICAL: iterate ALL runtime keys — never assume a fixed iOS version key
DEVICES_JSON=$(xcrun simctl list devices --json 2>/dev/null)

if [ "$IS_UDID" = "true" ]; then
  echo "[boot_sim] Input looks like a UDID — looking up directly..." >&2
  if [ "$JQ_AVAILABLE" = "true" ]; then
    FOUND=$(echo "$DEVICES_JSON" | jq -r --arg udid "$DEVICE_INPUT" \
      '.devices | to_entries[]
       | select(.key | contains("iOS"))
       | {runtime: .key, device: .value[]}
       | select(.device.udid == $udid and .device.isAvailable == true)
       | "\(.device.udid)\t\(.device.name)\t\(.runtime)"' 2>/dev/null | head -1)
  else
    FOUND=$(echo "$DEVICES_JSON" | python3 -c "
import sys, json
data = json.load(sys.stdin)
target = sys.argv[1]
for rkey, devs in data['devices'].items():
    if 'iOS' not in rkey:
        continue
    for d in devs:
        if not d.get('isAvailable', False):
            continue
        if d['udid'] == target:
            print(d['udid'] + '\t' + d['name'] + '\t' + rkey)
            sys.exit(0)
" "$DEVICE_INPUT" 2>/dev/null)
  fi
else
  # Name substring match (case-insensitive) across all runtime keys
  echo "[boot_sim] Looking up device by name: '$DEVICE_INPUT'..." >&2
  if [ "$JQ_AVAILABLE" = "true" ]; then
    FOUND=$(echo "$DEVICES_JSON" | jq -r --arg name "$DEVICE_INPUT" \
      '.devices | to_entries[]
       | select(.key | contains("iOS"))
       | {runtime: .key, device: .value[]}
       | select(.device.isAvailable == true and (.device.name | ascii_downcase | contains($name | ascii_downcase)))
       | "\(.device.udid)\t\(.device.name)\t\(.runtime)"' 2>/dev/null | head -1)
  else
    FOUND=$(echo "$DEVICES_JSON" | python3 -c "
import sys, json
data = json.load(sys.stdin)
target = sys.argv[1].lower()
for rkey, devs in data['devices'].items():
    if 'iOS' not in rkey:
        continue
    for d in devs:
        if not d.get('isAvailable', False):
            continue
        if target in d['name'].lower():
            print(d['udid'] + '\t' + d['name'] + '\t' + rkey)
            sys.exit(0)
" "$DEVICE_INPUT" 2>/dev/null)
  fi
fi

if [ -z "$FOUND" ]; then
  ELAPSED=$(( SECONDS - START_SECONDS ))
  printf '{"udid":null,"name":null,"state":"not_found","action":"failed","elapsed_s":%d,"error":"No device matching '"'"'%s'"'"' found in xcrun simctl list devices"}\n' \
    "$ELAPSED" "$DEVICE_INPUT"
  exit 1
fi

UDID=$(echo "$FOUND" | cut -f1)
NAME=$(echo "$FOUND" | cut -f2)
RUNTIME_KEY=$(echo "$FOUND" | cut -f3)
# Strip prefix to get e.g. "iOS-18-2"
RUNTIME=$(echo "$RUNTIME_KEY" | sed 's/com\.apple\.CoreSimulator\.SimRuntime\.//')

echo "[boot_sim] Found: $NAME ($UDID) runtime=$RUNTIME" >&2

# ── helper: get current state for a UDID ─────────────────────────────────────
get_state() {
  xcrun simctl list devices --json 2>/dev/null | python3 -c "
import sys, json
data = json.load(sys.stdin)
udid = sys.argv[1]
for devs in data['devices'].values():
    for d in devs:
        if d['udid'] == udid:
            print(d.get('state', 'unknown'))
            sys.exit(0)
print('unknown')
" "$UDID" 2>/dev/null
}

# ── check current state ──────────────────────────────────────────────────────
CURRENT_STATE=$(get_state)
echo "[boot_sim] Current state: $CURRENT_STATE" >&2

if [ "$CURRENT_STATE" = "Booted" ]; then
  echo "[boot_sim] $NAME ($UDID) is already booted" >&2
  ELAPSED=$(( SECONDS - START_SECONDS ))
  printf '{"udid":"%s","name":"%s","state":"Booted","runtime":"%s","action":"already_running","elapsed_s":%d,"error":null}\n' \
    "$UDID" "$NAME" "$RUNTIME" "$ELAPSED"
  exit 0
fi

# ── boot ─────────────────────────────────────────────────────────────────────
echo "[boot_sim] Booting $NAME ($UDID)..." >&2
# Idempotent: boot || true — xcrun simctl boot exits non-zero if already booted
xcrun simctl boot "$UDID" 2>/dev/null || true

# ── poll until Booted (hard timeout 30s at 1s intervals) ─────────────────────
DEADLINE=$(( SECONDS + 30 ))
echo "[boot_sim] Waiting for Booted state (timeout 30s)..." >&2
while true; do
  POLL_STATE=$(get_state)
  if [ "$POLL_STATE" = "Booted" ]; then
    break
  fi
  if [ "$SECONDS" -ge "$DEADLINE" ]; then
    ELAPSED=$(( SECONDS - START_SECONDS ))
    printf '{"udid":"%s","name":"%s","state":"Booting","runtime":"%s","action":"failed","elapsed_s":%d,"error":"Boot timeout after 30s — simulator still in Booting state"}\n' \
      "$UDID" "$NAME" "$RUNTIME" "$ELAPSED"
    exit 2
  fi
  echo "[boot_sim] State: $POLL_STATE — waiting..." >&2
  sleep 1
done

ELAPSED=$(( SECONDS - START_SECONDS ))
echo "[boot_sim] $NAME booted successfully in ${ELAPSED}s" >&2
printf '{"udid":"%s","name":"%s","state":"Booted","runtime":"%s","action":"booted","elapsed_s":%d,"error":null}\n' \
  "$UDID" "$NAME" "$RUNTIME" "$ELAPSED"
exit 0
