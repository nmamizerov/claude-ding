#!/bin/sh
# claude-ding: plays a sound from ./sounds without blocking Claude Code.
# Usage: play.sh <sound> [volume 1-100] [always|unfocused]
#   unfocused = stay quiet while the window running Claude Code is the one in front
DIR="$(cd "$(dirname "$0")" && pwd)"
FILE="$DIR/sounds/${1:-01-chime}.wav"
VOL="${2:-40}"
MODE="${3:-always}"
[ -f "$FILE" ] || exit 0
V="$(awk -v v="$VOL" 'BEGIN { if (v < 0) v = 0; if (v > 100) v = 100; printf "%.2f", v / 100 }')"

# PIDs of this script and every process above it (claude, shell, terminal, ...)
ancestors() {
  p=$$
  while [ -n "$p" ] && [ "$p" -gt 1 ] 2>/dev/null; do
    echo "$p"
    p="$(ps -o ppid= -p "$p" 2>/dev/null | tr -d ' ')"
  done
}

# True when the app/window that runs this Claude Code session is focused.
focused() {
  if command -v lsappinfo >/dev/null 2>&1; then                 # macOS, no permissions needed
    front="$(lsappinfo front 2>/dev/null)" || return 1
    fpid="$(lsappinfo info -only pid "$front" 2>/dev/null | sed -n 's/.*=\([0-9][0-9]*\).*/\1/p')"
    fname="$(lsappinfo info -only name "$front" 2>/dev/null | sed -n 's/.*"="\(.*\)"$/\1/p')"
    [ -n "$fpid" ] && ancestors | grep -qx "$fpid" && return 0
    case "$TERM_PROGRAM:$fname" in                              # terminals that detach their shells
      iTerm.app:iTerm2|Apple_Terminal:Terminal|ghostty:Ghostty|WarpTerminal:Warp|WezTerm:WezTerm|Hyper:Hyper) return 0 ;;
      vscode:Code|vscode:Cursor|vscode:Windsurf|vscode:VSCodium|vscode:Visual\ Studio\ Code) return 0 ;;
    esac
    return 1
  fi
  if [ -n "${DISPLAY:-}" ] && command -v xdotool >/dev/null 2>&1; then   # Linux / X11
    wpid="$(xdotool getactivewindow getwindowpid 2>/dev/null)" || return 1
    ancestors | grep -qx "$wpid"
    return
  fi
  return 1                                                      # can't tell -> play
}

[ "$MODE" = unfocused ] && focused && exit 0

winpath() {
  if command -v wslpath >/dev/null 2>&1; then wslpath -w "$1"
  elif command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"
  else printf '%s' "$1"; fi
}

play() {
  if command -v afplay >/dev/null 2>&1; then afplay -v "$V" "$FILE"                       # macOS
  elif command -v pw-play >/dev/null 2>&1; then pw-play --volume="$V" "$FILE"             # PipeWire
  elif command -v paplay >/dev/null 2>&1; then
    paplay --volume="$(awk -v v="$V" 'BEGIN { printf "%d", v * 65536 }')" "$FILE"          # PulseAudio
  elif command -v aplay >/dev/null 2>&1; then aplay -q "$FILE"                             # ALSA (no volume)
  elif command -v powershell.exe >/dev/null 2>&1; then                                     # Windows
    powershell.exe -NoProfile -c "Add-Type -AssemblyName PresentationCore; \$p = New-Object System.Windows.Media.MediaPlayer; \$p.Open([uri]'$(winpath "$FILE")'); \$p.Volume = $V; \$p.Play(); Start-Sleep -Milliseconds 2500"
  fi
}

# Detach so the hook returns instantly.
(play >/dev/null 2>&1 &)
exit 0
