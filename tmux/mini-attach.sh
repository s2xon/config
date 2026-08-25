#!/usr/bin/env bash
# Window command for the prefix+digit mini slots (see tmux.conf).
# Attaches to persistent tmux session "a<N>" on the mac mini, creating it there
# on demand — the mini needs no pre-provisioning beyond tmux being installed.
# If the mini is unreachable the window stays open so you can retry with `r`.
N="${1:?usage: mini-attach.sh <slot 1-10>}"
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:$PATH"

while :; do
  ssh -o ConnectTimeout=5 -t mac-mini "tmux new-session -A -s a$N"
  rc=$?
  # Clean detach (inner prefix d) exits 0 -> close the window.
  [ "$rc" -eq 0 ] && exit 0
  echo ""
  echo "slot a$N: ssh exited $rc — mini asleep/offline?"
  read -rn1 -p "press r to retry, anything else to close... " ans
  echo ""
  [ "$ans" = "r" ] || exit 0
done
