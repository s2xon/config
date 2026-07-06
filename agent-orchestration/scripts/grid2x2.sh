#!/usr/bin/env bash
# grid2x2.sh — arrange the FOCUSED workspace's tiled windows into corners.
# Bound to cmd-shift-g (Cmd-Shift-G) in ~/.config/aerospace/aerospace.toml.
#
#   4 windows -> 2x2 grid   (the requested case)
#   2 windows -> left / right halves
#   3 windows -> two stacked on the left, one tall on the right
#   >4        -> single balanced row (no strict 2x2 is possible)
#
# Two gotchas this script works around, both learned the hard way:
#   1. `aerospace layout ...` exits NON-ZERO when the requested state already
#      holds (a no-op). So NO `set -e` here — it would abort mid-build and leave
#      you stuck at an intermediate row (the "4-across" bug).
#   2. `join-with left` fails on the leftmost window (no left neighbor). So we
#      go to the leftmost window and build columns with `join-with right`, which
#      always has a neighbor — no need to know the windows' spatial order.
set -uo pipefail

AERO=/opt/homebrew/bin/aerospace
ws="$("$AERO" list-workspaces --focused)"
n="$("$AERO" list-windows --workspace "$ws" --count)"

[ "${n:-0}" -lt 2 ] && exit 0            # 0 or 1 window: nothing to arrange

"$AERO" flatten-workspace-tree --workspace "$ws"
"$AERO" focus --dfs-index 0              # focus something so `layout` hits the root
"$AERO" layout horizontal               # flatten into one horizontal row (no-op = ok)

case "$n" in
  2) : ;;                               # a horizontal row IS side-by-side
  3)
    "$AERO" focus --dfs-index 0                    # leftmost
    "$AERO" join-with right                        # left column = first two
    "$AERO" layout vertical                        # stack it
    ;;
  4)
    "$AERO" focus --dfs-index 0                    # leftmost
    "$AERO" join-with right                        # left column = first two
    "$AERO" layout vertical                        # stack it
    "$AERO" focus --boundaries-action stop right   # step out to the 3rd window
    "$AERO" join-with right                        # right column = last two
    "$AERO" layout vertical                        # stack it
    ;;
  *) : ;;                               # >4: leave as the balanced horizontal row
esac

"$AERO" balance-sizes
exit 0
