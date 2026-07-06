#!/usr/bin/env bash
# Mac-LOCAL. Idempotent: ensures ONE tmux session "fleet" exists, split into a
# 2x2 grid of 4 *generic* claude conductors (no roles / no duties), each running
# claude. No per-agent session names, no charters.
#
# FUTURE (PC as source of truth): point this + attach.sh at `ssh wsl` and run the
# session in WSL — everything else is the same.
set -uo pipefail
export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

TMUX_BIN="$(command -v tmux || echo /opt/homebrew/bin/tmux)"
WORKDIR="$HOME/Documents"
SESSION="fleet"
# `command claude` bypasses your zsh alias so the flag isn't doubled.
CLAUDE_CMD="command claude --dangerously-skip-permissions"

command -v claude >/dev/null 2>&1 || { echo "ERROR: claude not on PATH"; exit 1; }

if ! "$TMUX_BIN" has-session -t "$SESSION" 2>/dev/null; then
  # Pane 1, then split into a tiled 2x2 grid (panes 1-4 with pane-base-index 1).
  "$TMUX_BIN" new-session   -d -s "$SESSION" -c "$WORKDIR"
  "$TMUX_BIN" split-window  -h -t "$SESSION" -c "$WORKDIR"
  "$TMUX_BIN" split-window  -v -t "$SESSION" -c "$WORKDIR"
  "$TMUX_BIN" select-pane      -t "$SESSION.1"
  "$TMUX_BIN" split-window  -v -t "$SESSION" -c "$WORKDIR"
  "$TMUX_BIN" select-layout    -t "$SESSION" tiled
  # Boot a generic claude in each corner — no charter, no assigned role.
  for p in 1 2 3 4; do
    "$TMUX_BIN" send-keys -t "$SESSION.$p" "$CLAUDE_CMD" C-m
  done
  "$TMUX_BIN" select-pane -t "$SESSION.1"
fi

echo "Fleet session ready (2x2 claude grid):"
"$TMUX_BIN" ls
