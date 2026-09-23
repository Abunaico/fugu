---
name: help
description: List fugu's commands and what each one does. Use when the user says "/fugu help", "fugu commands", "what can fugu do", or asks which fugu command to use.
---

# fugu help

Show this table as-is, then answer any follow-up question about a specific command.

| Command | What it does |
|---|---|
| `/fugu:hud` | Check the HUD statusline; `install`, `repair`, `remove` |
| `/fugu:settings` | Turn individual features on or off (HUD segments, fleet rows, banner, watch) |
| `/fugu:context` | What's filling this session's context, and how the prompt cache is holding |
| `/fugu:accounts` | Every Claude Code login on this machine with its 5h/7d usage and reset times |
| `/fugu:sessions` | Session radar: every session across projects, newest first |
| `/fugu:open` | Resume or fork a session into a new tmux/Warp pane |
| `/fugu:fleet` | Explain or tune the subagent fleet rows |
| `/fugu:off`, `/fugu:on` | Mute or unmute everything at once |
| `/fugu:help` | This list |

CLIs behind them (on PATH while fugu is enabled, usable in any terminal): `fugu-hud`, `fugu-config`, `fugu-context`, `fugu-accounts`, `fugu-sessions`.

If a command above reports "Unknown command", fugu was updated during this session: Claude Code reads a plugin's commands at session start, so start a new session (or resume this one) to pick it up.
