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

b=$'\033[1m' d=$'\033[2m' g=$'\033[32m' r=$'\033[0m'
say() { printf '%s\n' "$*"; }

# Interactive input must come from the terminal: under `curl | bash` stdin is the script.
TTY=""
if [ -r /dev/tty ] && { : </dev/tty; } 2>/dev/null; then TTY=/dev/tty; fi
ask() { local reply=""; printf '%s' "$1" >&2; [ -n "$TTY" ] && IFS= read -r reply <"$TTY" || true; printf '%s' "$reply"; }

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

preview() { sh "$DEST/play.sh" "$1"; }

# ---------- choose sound ----------
resolve_sound() { # number or name -> full name
  local v="$1" s
  if [[ "$v" =~ ^[0-9]+$ ]] && [ "$v" -ge 1 ] && [ "$v" -le ${#SOUNDS[@]} ]; then echo "${SOUNDS[$((v-1))]}"; return; fi
  for s in "${SOUNDS[@]}"; do
    if [ "${s#*-}" = "$v" ] || [ "$s" = "$v" ]; then echo "$s"; return 0; fi
  done
  return 0
}

if [ -n "$SOUND" ]; then
  CHOSEN="$(resolve_sound "$SOUND")"
  [ -n "$CHOSEN" ] || { say "Unknown sound: $SOUND"; exit 1; }
elif [ -z "$TTY" ]; then
  CHOSEN="${SOUNDS[0]}"
else
  say ""
  say "${b}🔔 claude-ding${r}  ${d}a sound when Claude Code finishes${r}"
  say ""
  for i in "${!SOUNDS[@]}"; do printf '  %2d  %s\n' $((i+1)) "${SOUNDS[$i]#*-}"; done
  say ""
  CHOSEN=""
  while [ -z "$CHOSEN" ]; do
    n="$(ask "Type a number to listen (1-${#SOUNDS[@]}): ")"
    s="$(resolve_sound "$n")"
    [ -n "$s" ] || { say "  ${d}pick 1-${#SOUNDS[@]}${r}"; continue; }
    preview "$s"
    yn="$(ask "  ♪ ${s#*-}. Use it? [Y/n] ")"
    case "$yn" in [nN]*) ;; *) CHOSEN="$s" ;; esac
  done
fi

# ---------- choose scope ----------
if [ -z "$SCOPE" ]; then
  if [ -n "$TTY" ]; then
    say ""
    say "  1  Global          ${d}every project (~/.claude/settings.json)${r}"
    say "  2  This project    ${d}only $(basename "$PWD") (.claude/settings.local.json)${r}"
    case "$(ask "Where to install? [1] ")" in 2) SCOPE=project ;; *) SCOPE=global ;; esac
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
    case "$(ask "Also ding when Claude is waiting for your input? [Y/n] ")" in [nN]*) NOTIFY=0 ;; esac
  fi
fi

CMD="sh \"\$HOME/.claude/claude-ding/play.sh\" $CHOSEN"
edit_settings "$SETTINGS" install "$CMD" "$NOTIFY"

say ""
say "${g}✓${r} Installed ${b}${CHOSEN#*-}${r} → ${SETTINGS/#$HOME/~}"
say "  ${d}Restart Claude Code (or open /hooks) to pick it up. Run the same command again to change the sound.${r}"
