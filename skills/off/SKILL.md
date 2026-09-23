---
name: off
description: Turn fugu off — silences the HUD statusline, fleet dashboard, session banner, and cross-session watch notifications without uninstalling the plugin. Use when the user says "/fugu off", "turn off fugu", "disable fugu", "mute fugu", "quiet fugu".
disable-model-invocation: true
---

# Turn fugu off

Drops one marker file. `statusline.sh`, `subagent-statusline.sh`, `hooks/banner.sh`, and
`bin/fugu-watch` all check it on every invocation and go silent (drain stdin, exit 0 /
return early — no output, no error).

```bash
mkdir -p ~/.fugu && touch ~/.fugu/disabled
```

This is reversible and touches nothing in `~/.claude/settings.json` — the statusLine and
hook wiring stay installed, they just render nothing. Tell the user:

- HUD and fleet rows go blank on the very next render.
- The session banner stops appearing in new sessions.
- `fugu-watch` (if running in the background) stops emitting notifications within one
  poll interval (default 15s) — no restart needed.

To turn it back on: `/fugu:on`.
