#!/usr/bin/env bash
# Startup window layout for the Mac. Wired to run on login via aerospace.toml
# (after-startup-command). Safe to re-run by hand on a cold start:
#   ~/.config/agent-orchestration/scripts/layout.sh
#
#   WS1 = Arc browser
#   WS2 = one plain Ghostty window (the index-0 window)
#   WS3 = four Ghostty windows tiled 2x2, each attached to a fleet slot on the
#         MAC MINI (persistent tmux sessions a1-a4 there, claude booted by
#         start.sh) — the mini is the brain, these windows are just viewers
#
# ALL FIVE windows live in a SINGLE Ghostty app instance -- one Dock icon, one
# Cmd-Tab entry, Cmd-` cycles between them. We create the windows with Ghostty's
# AppleScript API instead of `open -na` (which forced a SEPARATE app instance
# per window -> the old 5-apps problem). On macOS there is no CLI to open a
# window-running-a-command in the existing instance (the +new-window IPC is
# Linux-only), but the AppleScript `surface configuration` object has a
# `command` property that does exactly this. AeroSpace then routes each window
# to its workspace by window-id.

export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

AERO=/opt/homebrew/bin/aerospace
# Directory this script lives in -- so it works wherever the repo is moved.
SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
GHOSTTY_BID=com.mitchellh.ghostty

# All current Ghostty window-ids (AeroSpace ids), one per line, sorted (for comm).
ghostty_aids() {
  "$AERO" list-windows --monitor all --app-bundle-id "$GHOSTTY_BID" \
    --format '%{window-id}' 2>/dev/null | sort
}

# Wait until a new Ghostty window-id appears relative to $1 (a sorted snapshot
# from ghostty_aids) and echo it. ~15s timeout.
wait_new_aid() {
  local before="$1" after newid i
  for i in $(seq 1 60); do
    sleep 0.25
    after="$(ghostty_aids)"
    newid="$(comm -13 <(printf '%s\n' "$before") <(printf '%s\n' "$after") | head -n1)"
    [ -n "$newid" ] && { printf '%s' "$newid"; return 0; }
  done
  return 1
}

# Create a new window in the running Ghostty instance and echo its AeroSpace
# window-id. With an argument, that arg becomes the window's `command` (run
# instead of the shell); without, it's a plain shell window.
new_ghostty_window() {
  local before; before="$(ghostty_aids)"
  if [ -n "${1:-}" ]; then
    osascript >/dev/null 2>&1 <<OSA
tell application "Ghostty"
  set cfg to new surface configuration
  set command of cfg to "$1"
  new window with configuration cfg
end tell
OSA
  else
    osascript -e 'tell application "Ghostty" to new window' >/dev/null 2>&1
  fi
  wait_new_aid "$before"
}

# --- WS1: browser -----------------------------------------------------------
# Arc is force-assigned to workspace 1 by an on-window-detected rule in
# aerospace.toml, so we just launch it.
"$AERO" workspace 1
open -a "Arc"

# --- Ensure ONE Ghostty instance + capture the plain index-0 window ----------
# Cold start (login): launching Ghostty creates exactly one window -> that's w0.
# Warm start (re-run by hand): `open` just activates and makes no window, so we
# create the plain window explicitly.
before="$(ghostty_aids)"
open -a Ghostty 2>/dev/null
w0="$(wait_new_aid "$before" || true)"
[ -z "$w0" ] && w0="$(new_ghostty_window || true)"

# --- Boot the fleet on the MAC MINI (the brain), non-fatal if it's down -----
# Ensures persistent tmux sessions a1-a4 exist on the mini with claude running.
# Synchronous on purpose: if it ran in the background, the windows below could
# attach first, mini-attach.sh would create the slots as plain shells, and
# start.sh would then skip them (idempotent) — no claude. ConnectTimeout=5
# bounds the login delay when the mini is unreachable.
"$SCRIPTS/start.sh" \
  || echo "layout.sh: start.sh failed (mini down?) — windows will show retry prompts" >&2

# --- The four conductor windows, all in the SAME instance -------------------
# Each attaches to its mini slot (persistent session aN on the mini). Ghostty
# runs multi-arg commands via /bin/sh -c, so args are fine here. If the mini
# is unreachable the window sits at mini-attach.sh's retry prompt.
w1="$(new_ghostty_window "$HOME/.config/tmux/mini-attach.sh 1")"
w2="$(new_ghostty_window "$HOME/.config/tmux/mini-attach.sh 2")"
w3="$(new_ghostty_window "$HOME/.config/tmux/mini-attach.sh 3")"
w4="$(new_ghostty_window "$HOME/.config/tmux/mini-attach.sh 4")"

# --- Route windows to their workspaces by id --------------------------------
[ -n "$w0" ] && "$AERO" move-node-to-workspace 2 --window-id "$w0"
for w in "$w1" "$w2" "$w3" "$w4"; do
  [ -n "$w" ] && "$AERO" move-node-to-workspace 3 --window-id "$w"
done

# --- WS3: build the 2x2 grid deterministically by window-id ------------------
# flatten -> force one horizontal row -> group into two columns -> stack each.
if [ -n "$w1" ] && [ -n "$w2" ] && [ -n "$w3" ] && [ -n "$w4" ]; then
  "$AERO" flatten-workspace-tree --workspace 3
  "$AERO" layout --window-id "$w1" h_tiles    # root = one horizontal row
  "$AERO" join-with --window-id "$w2" left    # left column  = { w1, w2 }
  "$AERO" join-with --window-id "$w4" left    # right column = { w3, w4 }
  "$AERO" layout --window-id "$w1" v_tiles    # stack left column
  "$AERO" layout --window-id "$w3" v_tiles    # stack right column
  "$AERO" balance-sizes
else
  echo "layout.sh: only got ids [$w1 $w2 $w3 $w4]; skipped 2x2 grid build" >&2
fi

# --- Land on the claude workspace -------------------------------------------
"$AERO" workspace 3
