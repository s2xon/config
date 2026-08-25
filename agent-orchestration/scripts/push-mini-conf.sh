#!/usr/bin/env bash
# Push mini/tmux.conf to the mac mini (backs up any existing conf there first)
# and apply it to a running tmux server if there is one. Run whenever the mini
# is awake; the prefix+digit slot bindings work without it, this just makes the
# mini side nicer (mouse scrollback, green status bar, sane resize).
set -euo pipefail
SRC="$HOME/.config/agent-orchestration/mini/tmux.conf"

ssh -o ConnectTimeout=5 mac-mini '
  mkdir -p ~/.config/tmux
  if [ -f ~/.config/tmux/tmux.conf ]; then
    cp ~/.config/tmux/tmux.conf ~/.config/tmux/tmux.conf.bak-pre-brain
  fi
'
scp "$SRC" mac-mini:.config/tmux/tmux.conf
ssh mac-mini 'tmux source-file ~/.config/tmux/tmux.conf 2>/dev/null || true'
echo "mini tmux conf pushed (backup: ~/.config/tmux/tmux.conf.bak-pre-brain if one existed)"
