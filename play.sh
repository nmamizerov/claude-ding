#!/bin/sh
# claude-ding: plays a sound from ./sounds without blocking Claude Code.
# Usage: play.sh <sound-name>     e.g. play.sh 07-marimba
DIR="$(cd "$(dirname "$0")" && pwd)"
FILE="$DIR/sounds/${1:-01-chime}.wav"
[ -f "$FILE" ] || exit 0

winpath() {
  if command -v wslpath >/dev/null 2>&1; then wslpath -w "$1"
  elif command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"
  else printf '%s' "$1"; fi
}

play() {
  if command -v afplay >/dev/null 2>&1; then afplay "$FILE"                # macOS
  elif command -v pw-play >/dev/null 2>&1; then pw-play "$FILE"            # PipeWire
  elif command -v paplay >/dev/null 2>&1; then paplay "$FILE"              # PulseAudio
  elif command -v aplay >/dev/null 2>&1; then aplay -q "$FILE"             # ALSA
  elif command -v powershell.exe >/dev/null 2>&1; then                     # Windows (Git Bash / WSL)
    powershell.exe -NoProfile -c "(New-Object Media.SoundPlayer '$(winpath "$FILE")').PlaySync()"
  fi
}

# Detach so the hook returns instantly.
(play >/dev/null 2>&1 &)
exit 0
