# 🔔 claude-ding

A tiny sound when Claude Code finishes a task, so you can stop staring at the terminal.

```bash
curl -fsSL https://raw.githubusercontent.com/nmamizerov/claude-ding/main/install.sh | bash
```

The installer lets you listen to 10 sounds, pick one, and choose where to install it:

- **Global**: every project (`~/.claude/settings.json`)
- **This project**: only the current folder (`.claude/settings.local.json`, not committed)

It can also ding when Claude stops to wait for your permission or input.
Restart Claude Code afterwards. To change the sound, run the same command again.

## Sounds

| # | name | | # | name |
|---|------|-|---|------|
| 1 | chime | | 6 | blip |
| 2 | ping | | 7 | marimba |
| 3 | pop | | 8 | bell |
| 4 | bubble | | 9 | levelup |
| 5 | coin | | 10 | droplet |

All sounds are synthesized from scratch by [`tools/generate_sounds.py`](tools/generate_sounds.py). No samples, no licensing questions.

## Skip the questions

```bash
curl -fsSL https://raw.githubusercontent.com/nmamizerov/claude-ding/main/install.sh | bash -s -- --sound marimba --scope global
```

| flag | |
|---|---|
| `--sound <1-10\|name>` | which sound |
| `--scope <global\|project>` | where to install |
| `--no-notify` | only ding when a task is done, not when Claude waits for you |
| `--uninstall` | remove the hooks (global + current project) and the files |

## How it works

It adds a [`Stop` hook](https://docs.claude.com/en/docs/claude-code/hooks) (and optionally a `Notification` hook) to your Claude Code settings:

```json
{
  "hooks": {
    "Stop": [
      { "hooks": [{ "type": "command", "command": "sh \"$HOME/.claude/claude-ding/play.sh\" 07-marimba" }] }
    ]
  }
}
```

Sounds and `play.sh` live in `~/.claude/claude-ding/`. Your existing settings and hooks are kept as they are.

Playback uses whatever the system has: `afplay` on macOS, `pw-play` / `paplay` / `aplay` on Linux, PowerShell on Windows (Git Bash or WSL). The sound plays in the background, so Claude is never slowed down.

## Uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/nmamizerov/claude-ding/main/install.sh | bash -s -- --uninstall
```

## License

MIT
