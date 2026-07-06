#!/usr/bin/env bash
# Mac-LOCAL. Attaches a Ghostty window to the single "fleet" tmux session
# (the 2x2 claude grid). Optional arg overrides the session name.
# FUTURE: swap the last line for:  exec ssh wsl -t "tmux attach -t fleet"
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"
exec tmux attach -t "${1:-fleet}"
