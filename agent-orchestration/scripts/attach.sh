#!/usr/bin/env bash
# Attach this terminal to fleet conductor slot N on the MAC MINI (default 1).
# Thin wrapper over mini-attach.sh: creates session aN on the mini on demand,
# retry prompt if the mini is unreachable. Usage: attach.sh [1-10]
exec "$HOME/.config/tmux/mini-attach.sh" "${1:-1}"
