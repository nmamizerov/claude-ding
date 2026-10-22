#!/usr/bin/env bash
# claude-ding installer: a sound when Claude Code finishes a task.
#
#   curl -fsSL https://raw.githubusercontent.com/nmamizerov/claude-ding/main/install.sh | bash
#
# Non-interactive flags:
#   --sound <1-10|name>   which sound to use
#   --scope <global|project>
#   --no-notify           don't play when Claude is waiting for your input
#   --uninstall           remove hooks (global + current project) and files
set -euo pipefail

REPO_RAW="${CLAUDE_DING_RAW:-https://raw.githubusercontent.com/nmamizerov/claude-ding/main}"
DEST="$HOME/.claude/claude-ding"
SOUNDS=(01-chime 02-ping 03-pop 04-bubble 05-coin 06-blip 07-marimba 08-bell 09-levelup 10-droplet)

SOUND="" SCOPE="" NOTIFY="" UNINSTALL=0
while [ $# -gt 0 ]; do
  case "$1" in
    --sound) SOUND="$2"; shift 2 ;;
    --scope) SCOPE="$2"; shift 2 ;;
    --no-notify) NOTIFY=0; shift ;;
    --uninstall) UNINSTALL=1; shift ;;
    -h|--help) sed -n '2,12p' "$0" 2>/dev/null || true; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

b=$'\033[1m' d=$'\033[2m' g=$'\033[32m' c=$'\033[36m' r=$'\033[0m'
say() { printf '%s\n' "$*"; }

# Interactive input must come from the terminal: under `curl | bash` stdin is the script.
TTY=""
if [ -r /dev/tty ] && { : </dev/tty; } 2>/dev/null; then TTY=/dev/tty; fi

# ---------- settings.json editing (jq -> node -> python3) ----------
edit_settings() { # file mode(install|uninstall) cmd notify(0|1)
  local file="$1" mode="$2" cmd="${3:-}" notify="${4:-0}"
  [ "$mode" = uninstall ] && [ ! -f "$file" ] && return 0
  mkdir -p "$(dirname "$file")"
  [ -s "$file" ] || echo '{}' >"$file"
  local tmp="$file.claude-ding.tmp"

  if command -v jq >/dev/null 2>&1; then
    jq --arg mode "$mode" --arg cmd "$cmd" --argjson notify "$notify" '
      def strip: map(select(any(.hooks[]?; (.command // "") | contains("claude-ding")) | not));
      def entry: [{hooks: [{type: "command", command: $cmd}]}];
      .hooks = (.hooks // {})
      | .hooks.Stop = ((.hooks.Stop // []) | strip)
      | .hooks.Notification = ((.hooks.Notification // []) | strip)
      | if $mode == "install" then
          .hooks.Stop += entry
          | if $notify == 1 then .hooks.Notification += entry else . end
        else . end
      | if .hooks.Stop == [] then del(.hooks.Stop) else . end
      | if .hooks.Notification == [] then del(.hooks.Notification) else . end
      | if .hooks == {} then del(.hooks) else . end
    ' "$file" >"$tmp"
  elif command -v node >/dev/null 2>&1; then
    node -e '
      const fs = require("fs"); const [file, mode, cmd, notify] = process.argv.slice(1);
      const s = JSON.parse(fs.readFileSync(file, "utf8") || "{}"); s.hooks = s.hooks || {};
      const strip = a => (a || []).filter(g => !(g.hooks || []).some(h => (h.command || "").includes("claude-ding")));
      const entry = { hooks: [{ type: "command", command: cmd }] };
      for (const ev of ["Stop", "Notification"]) {
        s.hooks[ev] = strip(s.hooks[ev]);
        if (mode === "install" && (ev === "Stop" || notify === "1")) s.hooks[ev].push(entry);
        if (!s.hooks[ev].length) delete s.hooks[ev];
      }
      if (!Object.keys(s.hooks).length) delete s.hooks;
      fs.writeFileSync(process.argv[5], JSON.stringify(s, null, 2) + "\n");
    ' "$file" "$mode" "$cmd" "$notify" "$tmp"
  elif command -v python3 >/dev/null 2>&1; then
    python3 - "$file" "$mode" "$cmd" "$notify" "$tmp" <<'PY'
import json, sys
file, mode, cmd, notify, tmp = sys.argv[1:]
s = json.load(open(file)) or {}
hooks = s.setdefault("hooks", {})
strip = lambda a: [g for g in (a or []) if not any("claude-ding" in h.get("command", "") for h in g.get("hooks", []))]
for ev in ("Stop", "Notification"):
    hooks[ev] = strip(hooks.get(ev))
    if mode == "install" and (ev == "Stop" or notify == "1"):
        hooks[ev].append({"hooks": [{"type": "command", "command": cmd}]})
    if not hooks[ev]:
        del hooks[ev]
if not hooks:
    del s["hooks"]
json.dump(s, open(tmp, "w"), indent=2); open(tmp, "a").write("\n")
PY
  else
    rm -f "$tmp"
    say "Couldn't find jq, node or python3 to edit $file."
    say "Add this to it manually:"
    say "{\"hooks\":{\"Stop\":[{\"hooks\":[{\"type\":\"command\",\"command\":\"$cmd\"}]}]}}"
    return 1
  fi
  mv "$tmp" "$file"
}

# ---------- uninstall ----------
if [ "$UNINSTALL" = 1 ]; then
  edit_settings "$HOME/.claude/settings.json" uninstall
  edit_settings "$PWD/.claude/settings.local.json" uninstall
  rm -rf "$DEST"
  say "${g}✓${r} claude-ding removed."
  exit 0
fi

# ---------- fetch files ----------
SRC_DIR=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "$(dirname "${BASH_SOURCE[0]}")/play.sh" ]; then
  SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"   # running from a clone
fi
mkdir -p "$DEST/sounds"
if [ -n "$SRC_DIR" ]; then
  cp "$SRC_DIR/play.sh" "$DEST/play.sh"
  cp "$SRC_DIR"/sounds/*.wav "$DEST/sounds/"
else
  printf 'Downloading sounds' >&2
  curl -fsSL "$REPO_RAW/play.sh" -o "$DEST/play.sh"
  for s in "${SOUNDS[@]}"; do
    curl -fsSL "$REPO_RAW/sounds/$s.wav" -o "$DEST/sounds/$s.wav"; printf '.' >&2
  done
  printf '\n' >&2
fi
chmod +x "$DEST/play.sh"

DESCS=("two soft bell notes" "one clean high note" "short bubbly pop" "rising wobble" "8-bit coin" "three quick ticks"
       "friendly wooden phrase" "deep bell, long tail" "8-bit level up" "water drop")

# ---------- sound preview (stops the previous one on every move) ----------
PREVIEW_PID=""
player_exec() { # replaces the current (sub)shell with the player, so killing its PID stops the sound
  local f="$1"
  if command -v afplay >/dev/null 2>&1; then exec afplay "$f"
  elif command -v pw-play >/dev/null 2>&1; then exec pw-play "$f"
  elif command -v paplay >/dev/null 2>&1; then exec paplay "$f"
  elif command -v aplay >/dev/null 2>&1; then exec aplay -q "$f"
  elif command -v powershell.exe >/dev/null 2>&1; then
    local w="$f"; command -v cygpath >/dev/null 2>&1 && w="$(cygpath -w "$f")"
    command -v wslpath >/dev/null 2>&1 && w="$(wslpath -w "$f")"
    exec powershell.exe -NoProfile -c "(New-Object Media.SoundPlayer '$w').PlaySync()"
  fi
}
stop_preview() { if [ -n "$PREVIEW_PID" ]; then kill "$PREVIEW_PID" 2>/dev/null || true; PREVIEW_PID=""; fi; }
preview() { stop_preview; (player_exec "$DEST/sounds/$1.wav" >/dev/null 2>&1) & PREVIEW_PID=$!; }

cleanup() { stop_preview; printf '\033[?25h' >&2; }
trap cleanup EXIT
trap 'cleanup; printf "\n" >&2; exit 130' INT TERM

# ---------- arrow-key menu ----------
# menu <play_sounds 0|1> <default index> <label>...   -> sets MENU_IDX
menu() {
  local sounds="$1" sel="$2"; shift 2
  local opts=("$@") n=$# i key rest last=-1
  printf '\033[?25l' >&2
  for i in "${!opts[@]}"; do printf '\n' >&2; done
  while :; do
    printf '\033[%dA' "$n" >&2
    for i in "${!opts[@]}"; do
      if [ "$i" = "$sel" ]; then printf '\r\033[2K  %s❯ %s%s\n' "$c" "${opts[$i]}" "$r" >&2
      else printf '\r\033[2K    %s\n' "${opts[$i]}" >&2; fi
    done
    if [ "$sounds" = 1 ] && [ "$sel" != "$last" ]; then preview "${SOUNDS[$sel]}"; fi
    last=$sel
    key=""; IFS= read -rsn1 key <"$TTY" || true
    case "$key" in
      $'\e') rest=""; IFS= read -rsn2 rest <"$TTY" || true
             case "$rest" in '[A'|'OA') sel=$(( (sel - 1 + n) % n )) ;; '[B'|'OB') sel=$(( (sel + 1) % n )) ;; esac ;;
      k|w) sel=$(( (sel - 1 + n) % n )) ;;
      j|s) sel=$(( (sel + 1) % n )) ;;
      ' ') last=-1 ;;                                  # space: play again
      [1-9]) [ "$key" -le "$n" ] && sel=$((key - 1)) ;;
      0) [ "$n" -ge 10 ] && sel=9 ;;
      q) cleanup; exit 130 ;;
      ''|$'\r'|$'\n') break ;;                     # Enter
    esac
  done
  printf '\033[%dA\033[J\033[?25h' "$n" >&2         # collapse the list
  MENU_IDX=$sel
}

resolve_sound() { # number or name -> full name
  local v="$1" s
  if [[ "$v" =~ ^[0-9]+$ ]] && [ "$v" -ge 1 ] && [ "$v" -le ${#SOUNDS[@]} ]; then echo "${SOUNDS[$((v-1))]}"; return 0; fi
  for s in "${SOUNDS[@]}"; do
    if [ "${s#*-}" = "$v" ] || [ "$s" = "$v" ]; then echo "$s"; return 0; fi
  done
  return 0
}

[ -n "$TTY" ] && { say ""; say "${b}🔔 claude-ding${r}  ${d}a sound when Claude Code finishes${r}"; say ""; }

# ---------- choose sound ----------
if [ -n "$SOUND" ]; then
  CHOSEN="$(resolve_sound "$SOUND")"
  [ -n "$CHOSEN" ] || { say "Unknown sound: $SOUND"; exit 1; }
elif [ -z "$TTY" ]; then
  CHOSEN="${SOUNDS[0]}"
else
  say "${b}Pick a sound${r}  ${d}↑/↓ to listen · space to replay · enter to choose${r}"
  labels=()
  for i in "${!SOUNDS[@]}"; do labels+=("$(printf '%-9s %s%s' "${SOUNDS[$i]#*-}" "$d" "${DESCS[$i]}")"); done
  menu 1 0 "${labels[@]}"
  stop_preview
  CHOSEN="${SOUNDS[$MENU_IDX]}"
  printf '\033[1A\r\033[2K' >&2
  say "${g}✓${r} Sound: ${b}${CHOSEN#*-}${r}"
fi

# ---------- choose scope ----------
if [ -z "$SCOPE" ]; then
  if [ -n "$TTY" ]; then
    say "${b}Where to install?${r}"
    menu 0 0 "Global        ${d}every project · ~/.claude/settings.json" \
             "This project  ${d}only $(basename "$PWD") · .claude/settings.local.json"
    [ "$MENU_IDX" = 1 ] && SCOPE=project || SCOPE=global
    printf '\033[1A\r\033[2K' >&2
    say "${g}✓${r} Scope: ${b}$([ "$SCOPE" = global ] && echo global || echo "this project")${r}"
  else
    SCOPE=global
  fi
fi
case "$SCOPE" in
  global) SETTINGS="$HOME/.claude/settings.json" ;;
  project) SETTINGS="$PWD/.claude/settings.local.json" ;;
  *) say "Unknown scope: $SCOPE (use global or project)"; exit 1 ;;
esac

if [ -z "$NOTIFY" ]; then
  NOTIFY=1
  if [ -n "$TTY" ]; then
    say "${b}Also ding when Claude is waiting for your input?${r}"
    menu 0 0 "Yes  ${d}task done + needs you" "No   ${d}only when a task is done"
    [ "$MENU_IDX" = 1 ] && NOTIFY=0
    printf '\033[1A\r\033[2K' >&2
    say "${g}✓${r} Waiting-for-you ding: ${b}$([ "$NOTIFY" = 1 ] && echo yes || echo no)${r}"
  fi
fi

CMD="sh \"\$HOME/.claude/claude-ding/play.sh\" $CHOSEN"
edit_settings "$SETTINGS" install "$CMD" "$NOTIFY"

say ""
say "${g}✓${r} Installed ${b}${CHOSEN#*-}${r} → ${SETTINGS/#$HOME/~}"
say "  ${d}Restart Claude Code (or open /hooks) to pick it up. Run the same command again to change the sound.${r}"
