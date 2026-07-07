#!/usr/bin/env bash
# Smart paste for tmux (bound to: prefix + v).
#   * clipboard holds an IMAGE -> save it to ~/.claude-clip/*.png and type the
#     path into the pane (Claude Code / tools attach it; survives tmux, which
#     otherwise strips image data from the clipboard).
#   * clipboard holds TEXT -> paste it normally (bracketed, multiline-safe).
# Pure macOS built-ins (osascript + sips) — no app, no extra installs.

set -uo pipefail
pane="${1:?pane id required}"

dir="$HOME/.claude-clip"
mkdir -p "$dir"
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

if { save_png || save_tiff_as_png; } && [ -s "$png" ]; then
  # Image: type the path (trailing space, same as a drag-and-drop insert).
  tmux send-keys -t "$pane" -l "$png "
  tmux display-message "pasted image -> $png"
else
  # No image: normal text paste.
  rm -f "$png" 2>/dev/null
  tmux set-buffer -- "$(pbpaste)"
  tmux paste-buffer -d -p -t "$pane"
fi
