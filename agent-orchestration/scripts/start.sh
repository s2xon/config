#!/usr/bin/env bash
# MINI IS THE BRAIN. Idempotent: ensures the four conductor slot sessions
# a1-a4 exist in the tmux server ON THE MAC MINI, each running claude. Slots
# created here get claude launched; slots that already exist (including ones
# prefix+digit opened earlier as plain shells) are left untouched. The Mac
# holds no fleet state — attach.sh / mini-attach.sh / prefix+1-0 are viewers.
set -uo pipefail

ssh -o ConnectTimeout=5 mac-mini 'bash -s' <<'REMOTE'
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
TMUX_BIN="$(command -v tmux)" || { echo "ERROR: tmux not installed on the mini"; exit 1; }
WORKDIR="$HOME/Documents"
# `command claude` bypasses any zsh alias so the flag isn't doubled.
CLAUDE_CMD="command claude --dangerously-skip-permissions"
HAVE_CLAUDE=1
command -v claude >/dev/null 2>&1 || HAVE_CLAUDE=0

# "=aN" forces exact-name match (plain -t aN would prefix-match a10).
for n in 1 2 3 4; do
  if "$TMUX_BIN" has-session -t "=a$n" 2>/dev/null; then
    echo "slot a$n: already running"
  else
    "$TMUX_BIN" new-session -d -s "a$n" -c "$WORKDIR"
    [ "$HAVE_CLAUDE" -eq 1 ] && "$TMUX_BIN" send-keys -t "=a$n" "$CLAUDE_CMD" C-m
    echo "slot a$n: created"
  fi
done
[ "$HAVE_CLAUDE" -eq 1 ] || echo "WARNING: claude not on the mini's PATH — slots are plain shells"
echo "--- mini tmux sessions:"
"$TMUX_BIN" ls
REMOTE
