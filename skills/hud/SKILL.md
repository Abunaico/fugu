---
name: hud
argument-hint: "[status | install | repair | remove]"
description: Install, check, repair, or remove the fugu HUD statusline. Use when the user says "install the hud", "set up fugu statusline", "is the hud working", "fugu after update", "remove the hud", or the statusline looks broken or stale.
disable-model-invocation: true
---

# fugu HUD

The bundled CLI (on PATH while fugu is enabled) does all of it. Never edit `~/.claude/settings.json` by hand for this.

```bash
fugu-hud            # status: what's wired, which fugu copy is live, other copies, mutes
fugu-hud install    # launcher + one settings key (timestamped backup first)
fugu-hud repair     # re-point at this copy, reinstall, then status
fugu-hud remove     # drop the statusLine key (only if it's fugu's) and the launcher
```

Arguments the user passed: "$ARGUMENTS"

- No argument: run `fugu-hud` (status) and present it. If it reports problems, offer `repair`.
- `install` / `repair` / `remove`: run that, then present the output.

How it works, for questions: settings point at a stable launcher (`~/.fugu/bin/statusline`), not at a plugin copy. Each session start records which fugu copy Claude Code loaded (`~/.fugu/root`) and the launcher runs that copy's `statusline.sh`, so `/plugin update` reaches the HUD with no reinstall. `install` refuses to replace a statusLine that isn't fugu's.

After install or repair, tell the user to look at the bottom of the screen. The settings key is per profile: with `CLAUDE_CONFIG_DIR` set, run it once in each profile.
