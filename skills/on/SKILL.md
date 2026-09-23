---
name: on
description: Turn fugu back on after /fugu:off. Use when the user says "/fugu on", "turn fugu back on", "enable fugu", "un-mute fugu", "unquiet fugu".
disable-model-invocation: true
---

# Turn fugu on

Removes the marker `/fugu:off` drops:

```bash
rm -f ~/.fugu/disabled
```

Tell the user: HUD and fleet rows resume on the next render, the banner returns on the
next new session, and `fugu-watch` (if already running) resumes notifications within one
poll interval — no restart needed either way.

If fugu was never installed (no `~/.fugu` dir, `jq -e '.statusLine'` empty on
`~/.claude/settings.json`), this command has nothing to do — point the user at
`/fugu:hud` instead.
