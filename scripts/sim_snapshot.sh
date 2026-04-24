#!/usr/bin/env bash
# sim_snapshot.sh — capture iOS simulator UI state (a11y tree or screenshot)
#
# Usage: sim_snapshot.sh --sim <UDID> [--tree | --screenshot] [--iter N]
#
# Default mode: --tree (falls back to screenshot when axe not installed)
# Stdout: single JSON object (the ONLY content on stdout)
# Stderr: human-readable progress and warnings
#
# Exit codes:
#   0 — success (screenshot or tree captured)
#   1 — simulator not booted / not found, or missing required argument
#   3 — capture command failed (xcrun simctl io or axe returned non-zero)
#
# IMPORTANT: Call this script ONLY when failure-triage.md mandates it (category 5-E).
# Do NOT call on every iteration — even a11y trees consume tokens.

set -euo pipefail

START_SECONDS=$SECONDS

# ── arg parsing ───────────────────────────────────────────────────────────────

UDID=""
MODE="tree"   # default: try axe, fall back to screenshot
ITER=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --sim)        UDID="$2";         shift 2 ;;
    --tree)       MODE="tree";       shift   ;;
    --screenshot) MODE="screenshot"; shift   ;;
    --iter)       ITER="$2";         shift 2 ;;
    *) echo "[sim_snapshot] Unknown argument: $1" >&2; shift ;;
  esac
done

if [ -z "$UDID" ]; then
  printf '{"mode":null,"udid":null,"tool":null,"tree_path":null,"tree_summary":null,"token_estimate":null,"screenshot_path":null,"warning":null,"error":"--sim <UDID> is required"}\n'
  exit 1
fi

# ── tool checks ───────────────────────────────────────────────────────────────

if ! command -v xcrun &>/dev/null; then
  printf '{"mode":null,"udid":"%s","tool":null,"tree_path":null,"tree_summary":null,"token_estimate":null,"screenshot_path":null,"warning":null,"error":"xcrun not found — is Xcode installed?"}\n' "$UDID"
  exit 1
fi

if ! command -v python3 &>/dev/null; then
  printf '{"mode":null,"udid":"%s","tool":null,"tree_path":null,"tree_summary":null,"token_estimate":null,"screenshot_path":null,"warning":null,"error":"python3 not found"}\n' "$UDID"
  exit 1
fi

# ── check simulator state ─────────────────────────────────────────────────────
# Iterates ALL runtime keys (never hardcodes iOS version)

SIM_STATE=$(xcrun simctl list devices --json 2>/dev/null | python3 -c "
import sys, json
d = json.load(sys.stdin)
udid = sys.argv[1]
for devices in d['devices'].values():
    for dev in devices:
        if dev['udid'] == udid:
            print(dev.get('state', 'unknown'))
            sys.exit(0)
print('not_found')
" "$UDID" 2>/dev/null || echo "not_found")

if [ "$SIM_STATE" != "Booted" ]; then
  printf '{"mode":null,"udid":"%s","tool":null,"tree_path":null,"tree_summary":null,"token_estimate":null,"screenshot_path":null,"warning":null,"error":"Simulator not booted — state: %s"}\n' \
    "$UDID" "$SIM_STATE"
  exit 1
fi

echo "[sim_snapshot] Simulator state: $SIM_STATE" >&2

# ── directory setup ───────────────────────────────────────────────────────────

ITER_DIR=".test-results/iter-${ITER}"
mkdir -p "$ITER_DIR"
ITER_ABS="$(pwd)/$ITER_DIR"

# ── axe detection ─────────────────────────────────────────────────────────────
# axe is NOT installed on the reference machine; fallback always activates here

AXE_AVAILABLE=false
if command -v axe &>/dev/null; then
  AXE_AVAILABLE=true
  AXE_PATH=$(command -v axe)
  echo "[sim_snapshot] axe found at $AXE_PATH" >&2
else
  echo "[sim_snapshot] WARNING: axe not found — falling back to screenshot" >&2
fi

# ── helper: emit screenshot JSON (to stdout) ──────────────────────────────────

emit_screenshot_json() {
  # $1 = absolute screenshot path
  # $2 = warning string (empty string → null in JSON)
  local path="$1"
  local warning="$2"
  python3 -c "
import sys, json
path    = sys.argv[1]
warning = sys.argv[2] if sys.argv[2] else None
d = {
  'mode':            'screenshot',
  'udid':            sys.argv[3],
  'tool':            'xcrun_simctl_io',
  'tree_path':       None,
  'tree_summary':    None,
  'token_estimate':  None,
  'screenshot_path': path,
  'warning':         warning,
}
print(json.dumps(d))
" "$path" "$warning" "$UDID"
}

# ── helper: take screenshot ───────────────────────────────────────────────────
# Prints absolute screenshot path to stdout; all progress → stderr
# Exits 3 on xcrun failure

take_screenshot() {
  local ts
  ts=$(date +%s)
  local out_path="${ITER_ABS}/screenshot-${ts}.png"
  echo "[sim_snapshot] Taking screenshot → $out_path" >&2
  # Route BOTH stdout and stderr of simctl to stderr — simctl prints chatter like
  # "Detected file type from extension: PNG" to stdout, which would otherwise be
  # captured by $(take_screenshot) along with the real out_path. The order
  # `>&2 2>&1` dup's stdout→stderr FIRST, then stderr→(now-stderr)stdout,
  # so both streams end up on stderr.
  if ! xcrun simctl io "$UDID" screenshot "$out_path" >&2 2>&1; then
    local sc_exit=$?
    printf '{"mode":null,"udid":"%s","tool":null,"tree_path":null,"tree_summary":null,"token_estimate":null,"screenshot_path":null,"warning":null,"error":"xcrun simctl io screenshot exited with code %d"}\n' \
      "$UDID" "$sc_exit"
    exit 3
  fi
  echo "$out_path"
}

# ── --screenshot mode (explicit) ──────────────────────────────────────────────

if [ "$MODE" = "screenshot" ]; then
  echo "[sim_snapshot] Mode: screenshot (explicit)" >&2
  SCREENSHOT_PATH=$(take_screenshot)
  WARNING="screenshots are expensive — use --tree (requires axe) for token-efficient triage"
  # stdout: final JSON only
  emit_screenshot_json "$SCREENSHOT_PATH" "$WARNING"
  # audit trail
  emit_screenshot_json "$SCREENSHOT_PATH" "$WARNING" > "${ITER_DIR}/snapshot.json"
  exit 0
fi

# ── --tree mode ───────────────────────────────────────────────────────────────

echo "[sim_snapshot] Mode: tree" >&2

if [ "$AXE_AVAILABLE" = "false" ]; then
  # axe absent — graceful fallback to screenshot with stderr WARNING
  echo "[sim_snapshot] Falling back to screenshot (axe not installed)" >&2
  SCREENSHOT_PATH=$(take_screenshot)
  WARNING="axe not installed — fell back to screenshot; install axe for cheaper a11y trees"
  emit_screenshot_json "$SCREENSHOT_PATH" "$WARNING"
  emit_screenshot_json "$SCREENSHOT_PATH" "$WARNING" > "${ITER_DIR}/snapshot.json"
  exit 0
fi

# axe is available — attempt a11y tree capture
# NOTE: axe describe-ui CLI is ASSUMED (axe absent on reference machine; cannot verify exact flags)
# If axe CLI differs, script falls back to screenshot with a clear stderr error message.

TREE_PATH="${ITER_ABS}/a11y-tree.txt"
echo "[sim_snapshot] Capturing a11y tree via axe → $TREE_PATH" >&2

AXE_EXIT=0
axe describe-ui --udid "$UDID" > "$TREE_PATH" 2>&1 || AXE_EXIT=$?

if [ $AXE_EXIT -ne 0 ]; then
  echo "[sim_snapshot] WARNING: axe describe-ui failed (exit $AXE_EXIT) — falling back to screenshot" >&2
  SCREENSHOT_PATH=$(take_screenshot)
  WARNING="axe describe-ui failed (exit ${AXE_EXIT}) — fell back to screenshot"
  emit_screenshot_json "$SCREENSHOT_PATH" "$WARNING"
  emit_screenshot_json "$SCREENSHOT_PATH" "$WARNING" > "${ITER_DIR}/snapshot.json"
  exit 0
fi

# Extract compact tree summary (50-line hard cap for token budget)
# Keep label/value/role/enabled/focused/interactive-element lines; strip raw coordinates
TREE_SUMMARY=$(grep -E '(label|value|role|enabled|focused|Button|Text|TextField|Switch|Slider)' \
  "$TREE_PATH" \
  | sed 's/[[:space:]]\+/ /g' \
  | head -50 || true)

# Token estimate: bytes / 4  (1 token ≈ 4 ASCII bytes — rough approximation)
TOKEN_ESTIMATE=$(printf '%s' "$TREE_SUMMARY" | wc -c | awk '{printf "%d", $1/4}')

# Emit a11y_tree JSON to stdout
python3 -c "
import sys, json
udid     = sys.argv[1]
tree_path= sys.argv[2]
summary  = sys.argv[3] if sys.argv[3] else None
tok_est  = int(sys.argv[4])
d = {
  'mode':            'a11y_tree',
  'udid':            udid,
  'tool':            'axe',
  'tree_path':       tree_path,
  'tree_summary':    summary,
  'token_estimate':  tok_est,
  'screenshot_path': None,
  'warning':         None,
}
print(json.dumps(d))
" "$UDID" "$TREE_PATH" "$TREE_SUMMARY" "$TOKEN_ESTIMATE"

# Write snapshot.json audit trail (same content)
python3 -c "
import sys, json
udid     = sys.argv[1]
tree_path= sys.argv[2]
summary  = sys.argv[3] if sys.argv[3] else None
tok_est  = int(sys.argv[4])
d = {
  'mode':            'a11y_tree',
  'udid':            udid,
  'tool':            'axe',
  'tree_path':       tree_path,
  'tree_summary':    summary,
  'token_estimate':  tok_est,
  'screenshot_path': None,
  'warning':         None,
}
print(json.dumps(d))
" "$UDID" "$TREE_PATH" "$TREE_SUMMARY" "$TOKEN_ESTIMATE" > "${ITER_DIR}/snapshot.json"

exit 0
