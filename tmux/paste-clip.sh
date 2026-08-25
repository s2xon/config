#!/usr/bin/env bash
# Smart paste for tmux (bound to: prefix + v, and cmd+v via Ghostty -> C-_ in "native" mode).
#   * native mode ($2 = "native", used by cmd+v): if the pane is Claude Code
#     running locally, forward a real Ctrl+V so Claude does its own clipboard
#     image paste and shows the [Image #1] placeholder. Everything else falls
#     through to the behaviors below.
#   * clipboard holds an IMAGE -> save it to ~/.claude-clip/*.png and type the
#     path into the pane (Claude Code / tools attach it; survives tmux, which
#     otherwise strips image data from the clipboard).
#     If the pane is an ssh session (e.g. mac-mini), the image is pushed to the
#     remote host's ~/.claude-clip over ssh first and the REMOTE path is typed,
#     so Claude Code running on the other end can read it.
#   * clipboard holds TEXT -> paste it normally (bracketed, multiline-safe).
#     Text needs no special handling over ssh — it goes through as keystrokes.
# Pure macOS built-ins (osascript + sips + ssh) — no app, no extra installs.

set -uo pipefail
pane="${1:?pane id required}"
mode="${2:-path}"

# Regular-paste fidelity: load-buffer streams the raw bytes (no ARG_MAX limit,
# trailing newlines preserved); paste-buffer -p brackets only if the app asked,
# same as a terminal-native paste.
paste_text() {
  pbpaste 2>/dev/null | tmux load-buffer -b paste-clip - \
    && tmux paste-buffer -d -p -b paste-clip -t "$pane"
}

if [ "$mode" = "native" ]; then
  # cmd+v must behave EXACTLY like a regular paste whenever the clipboard has
  # any text representation — text wins, instantly, no osascript.
  if [ -n "$(pbpaste 2>/dev/null | head -c 1)" ]; then
    paste_text
    exit 0
  fi
  # Text-free clipboard (i.e. a screenshot) headed into a local Claude Code
  # pane: Claude's own ctrl+v reads the clipboard image directly, so skip the
  # osascript save entirely. This is the hot path — keep it fork-light.
  # (Claude Code's process title is its version number, e.g. "2.1.221".)
  panecmd="$(tmux display -p -t "$pane" '#{pane_current_command}')"
  if [[ "$panecmd" =~ ^(claude|[0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
    tmux send-keys -t "$pane" C-v
    exit 0
  fi
fi

dir="$HOME/.claude-clip"
mkdir -p "$dir"
find "$dir" -name 'clip-*' -mtime +7 -delete 2>/dev/null
stamp="$(date +%s)-$RANDOM"
png="$dir/clip-$stamp.png"

# Coerce the clipboard to PNG and write it out. Returns non-zero if there is no
# image on the clipboard (e.g. it holds plain text).
save_png() {
  osascript - "$png" >/dev/null 2>&1 <<'APPLESCRIPT'
on run argv
  set outPath to POSIX file (item 1 of argv)
  set pngData to (the clipboard as «class PNGf»)
  set fh to open for access outPath with write permission
  set eof fh to 0
  write pngData to fh
  close access fh
end run
APPLESCRIPT
}

# Fallback: some images live on the clipboard only as TIFF. Grab TIFF, then let
# sips transcode to PNG.
save_tiff_as_png() {
  local tiff="$dir/clip-$stamp.tiff"
  osascript - "$tiff" >/dev/null 2>&1 <<'APPLESCRIPT'
on run argv
  set outPath to POSIX file (item 1 of argv)
  set tiffData to (the clipboard as «class TIFF»)
  set fh to open for access outPath with write permission
  set eof fh to 0
  write tiffData to fh
  close access fh
end run
APPLESCRIPT
  if [ -s "$tiff" ]; then
    sips -s format png "$tiff" --out "$png" >/dev/null 2>&1
    local rc=$?
    rm -f "$tiff"
    return $rc
  fi
  rm -f "$tiff" 2>/dev/null
  return 1
}

# Find the ssh client process running inside the pane: the pane process itself
# (pane launched as `ssh host`) or a descendant a few levels deep (ssh typed at
# a shell, or under a wrapper script).
find_ssh_pid() {
  local pane_pid
  pane_pid="$(tmux display -p -t "$pane" '#{pane_pid}')" || return 1
  local frontier=("$pane_pid") next=() depth pid name
  for depth in 0 1 2 3; do
    next=()
    for pid in "${frontier[@]}"; do
      name="$(ps -o comm= -p "$pid" 2>/dev/null)"
      name="${name##*/}"
      if [ "$name" = "ssh" ]; then
        printf '%s\n' "$pid"
        return 0
      fi
      next+=($(pgrep -P "$pid" 2>/dev/null))
    done
    [ ${#next[@]} -eq 0 ] && return 1
    frontier=("${next[@]}")
  done
  return 1
}

# Pull the destination (host / user@host) out of the ssh process's arguments:
# skip option flags (and the values of flags that take one), first bare word
# is the destination.
ssh_dest() {
  local pid="$1" a
  local -a argv
  read -r -a argv <<<"$(ps -o args= -p "$pid" 2>/dev/null)"
  [ ${#argv[@]} -ge 2 ] || return 1
  # ssh flags that consume a following argument
  local valopts=" -B -b -c -D -E -e -F -I -i -J -L -l -m -O -o -p -P -Q -R -S -W -w "
  local i=1
  while [ "$i" -lt ${#argv[@]} ]; do
    a="${argv[$i]}"
    case "$a" in
      --) i=$((i + 1)); break ;;
      -*)
        if [ ${#a} -eq 2 ] && [[ "$valopts" == *" $a "* ]]; then
          i=$((i + 2))
        else
          i=$((i + 1))
        fi
        ;;
      *) break ;;
    esac
  done
  a="${argv[$i]:-}"
  [ -n "$a" ] || return 1
  printf '%s\n' "$a"
}

# Stream the png to the remote host's ~/.claude-clip and print the remote path.
# RemoteCommand=none / RequestTTY=no override any host config; ControlMaster in
# ~/.ssh/config makes this reuse the pane's existing connection (fast, no auth).
push_remote() {
  local dest="$1" base remote_home
  base="$(basename "$png")"
  remote_home="$(
    ssh -o BatchMode=yes -o ConnectTimeout=8 -o RemoteCommand=none -o RequestTTY=no "$dest" \
      "mkdir -p ~/.claude-clip && cat > ~/.claude-clip/$base || exit 1; find ~/.claude-clip -name 'clip-*' -mtime +7 -delete 2>/dev/null; echo ~" \
      <"$png" 2>/dev/null | tail -n 1
  )" || return 1
  case "$remote_home" in
    /*) printf '%s/.claude-clip/%s\n' "$remote_home" "$base" ;;
    *) return 1 ;;
  esac
}

if { save_png || save_tiff_as_png; } && [ -s "$png" ]; then
  typed="$png"
  if [ "$(tmux display -p -t "$pane" '#{pane_current_command}')" = "ssh" ]; then
    if sshpid="$(find_ssh_pid)" && dest="$(ssh_dest "$sshpid")" && rpath="$(push_remote "$dest")"; then
      typed="$rpath"
      tmux display-message "pasted image -> $dest:$rpath"
    else
      tmux display-message "image push to remote failed; saved locally at $png (path NOT typed)"
      exit 0
    fi
  else
    tmux display-message "pasted image -> $png"
  fi
  # Type the path (trailing space, same as a drag-and-drop insert).
  tmux send-keys -t "$pane" -l "$typed "
else
  # No image: normal text paste.
  rm -f "$png" 2>/dev/null
  paste_text
fi
