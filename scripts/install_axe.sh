#!/usr/bin/env bash
# install_axe.sh — install AXe CLI for sim_snapshot.sh --tree mode (token-cheap a11y trees).
#
# AXe is OPTIONAL. sim_snapshot.sh --tree falls back to screenshot if axe is absent.
# Run this script ONLY after explicit user consent — the SKILL.md contract requires
# the agent to ask the user "want me to install AXe via Homebrew?" first.
#
# Upstream: https://github.com/cameroncooke/AXe (official tap: cameroncooke/axe)
#
# Usage:
#   bash install_axe.sh [--dry-run] [--force]
#
#   --dry-run   Print what would run; do not execute brew.
#   --force     Reinstall even if axe is already on PATH (otherwise idempotent no-op).
#
# Stdout: single-line JSON summary (consumed by agent).
# Stderr: progress lines.
# Exit 0: axe is installed and runnable (or already was).
# Exit 1: prerequisite missing (brew, network, etc.) or install failed.
# Exit 2: --dry-run completed (no install attempted).
set -euo pipefail

START_SECONDS=$SECONDS

# ── arg parsing ───────────────────────────────────────────────────────────────
DRY_RUN=0
FORCE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --force)   FORCE=1;   shift ;;
    -h|--help)
      sed -n '1,22p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) echo "[install_axe] unknown arg: $1" >&2; shift ;;
  esac
done

_emit() {
  # _emit <success> <action> <axe_path|""> <axe_version|""> <error|"">
  local success="$1" action="$2" path="$3" ver="$4" err="$5"
  local elapsed=$((SECONDS - START_SECONDS))
  python3 -c "
import json, sys
print(json.dumps({
  'success':     sys.argv[1] == 'true',
  'action':      sys.argv[2],
  'axe_path':    sys.argv[3] or None,
  'axe_version': sys.argv[4] or None,
  'elapsed_s':   int(sys.argv[5]),
  'error':       sys.argv[6] or None,
}))
" "$success" "$action" "$path" "$ver" "$elapsed" "$err"
}

# ── idempotency check ─────────────────────────────────────────────────────────
if command -v axe >/dev/null 2>&1 && [ "$FORCE" = "0" ]; then
  AXE_PATH=$(command -v axe)
  AXE_VER=$(axe --version 2>/dev/null | head -1 || echo "")
  echo "[install_axe] axe already installed at $AXE_PATH — no-op (use --force to reinstall)" >&2
  _emit true noop "$AXE_PATH" "$AXE_VER" ""
  exit 0
fi

# ── tool checks ───────────────────────────────────────────────────────────────
if ! command -v python3 >/dev/null 2>&1; then
  printf '{"success":false,"action":"failed","axe_path":null,"axe_version":null,"elapsed_s":0,"error":"python3 not found (required for JSON output)"}\n'
  exit 1
fi

if ! command -v brew >/dev/null 2>&1; then
  echo "[install_axe] ERROR: Homebrew (brew) not found." >&2
  echo "[install_axe]        Install brew first: https://brew.sh" >&2
  echo "[install_axe]        (or build axe from source: https://github.com/cameroncooke/AXe#build-from-source)" >&2
  _emit false failed "" "" "Homebrew not installed — see https://brew.sh"
  exit 1
fi

# ── dry-run path ──────────────────────────────────────────────────────────────
if [ "$DRY_RUN" = "1" ]; then
  echo "[install_axe] DRY-RUN would run: brew install cameroncooke/axe/axe" >&2
  _emit true dry_run "" "" ""
  exit 2
fi

# ── install ───────────────────────────────────────────────────────────────────
echo "[install_axe] Installing axe via Homebrew tap cameroncooke/axe..." >&2
echo "[install_axe] Running: brew install cameroncooke/axe/axe" >&2

INSTALL_LOG=$(mktemp -t install_axe.XXXXXX.log)
INSTALL_EXIT=0
brew install cameroncooke/axe/axe >"$INSTALL_LOG" 2>&1 || INSTALL_EXIT=$?

if [ "$INSTALL_EXIT" -ne 0 ]; then
  echo "[install_axe] brew install failed (exit $INSTALL_EXIT). Last 20 log lines:" >&2
  tail -20 "$INSTALL_LOG" >&2 || true
  _emit false failed "" "" "brew install cameroncooke/axe/axe exited $INSTALL_EXIT — see stderr for last log lines (full log: $INSTALL_LOG)"
  exit 1
fi

# ── verify ────────────────────────────────────────────────────────────────────
if ! command -v axe >/dev/null 2>&1; then
  _emit false failed "" "" "brew install reported success but 'axe' not on PATH — try opening a new shell or check brew --prefix/bin"
  exit 1
fi

AXE_PATH=$(command -v axe)
AXE_VER=$(axe --version 2>/dev/null | head -1 || echo "")
echo "[install_axe] OK — axe installed at $AXE_PATH (${AXE_VER:-version unknown})" >&2
_emit true installed "$AXE_PATH" "$AXE_VER" ""
exit 0
