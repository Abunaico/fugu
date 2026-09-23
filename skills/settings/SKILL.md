---
name: settings
argument-hint: "[on|off <feature>... | all | reset]"
description: Turn individual fugu features on or off (HUD segments like git, account, rate meters, reset countdown, pace, cache countdown, cost, mode, the fish; plus the fleet rows, session banner, and watch notifications). Use when the user says "/fugu settings", "fugu config", "hide the cost", "turn off the fish", "disable the banner", or wants to customize what fugu shows.
---

# fugu settings

The bundled CLI (on PATH while fugu is enabled) owns the config file, `~/.fugu/config`:

```bash
fugu-config                    # show every feature and whether it's on
fugu-config off hud.cost hud.git
fugu-config on hud.cost
fugu-config off all            # or: on all
fugu-config reset              # everything back on
```

Arguments the user passed: "$ARGUMENTS"

1. **Arguments given** (e.g. `off hud.cost`, "hide the fish", "turn the banner back on"): map them to feature keys, run `fugu-config on|off <keys>`, and show the resulting table.
2. **No arguments:** run `fugu-config --json` to get the current state, then ask with AskUserQuestion, `multiSelect: true`, three questions, pre-describing each option with its current state (e.g. "Git branch (on)"). The user picks the features they want **on**:
   - "HUD line 1": `hud.fish` (pufferfish), `hud.mode` (effort + style), `hud.git` (git branch), `hud.account` (account)
   - "HUD line 2": `hud.rate` (5h/7d meters), `hud.reset` (reset countdown), `hud.pace` (pace projection), `hud.cache` (cache countdown)
   - "Everything else": `hud.cost` (session cost), `fleet` (subagent rows), `banner` (session banner), `watch` (watch notifications)

   Turn on everything selected and off everything not selected in one `fugu-config on ...` plus one `fugu-config off ...` call. Show the final table.
3. Tell the user: HUD and fleet changes show on the next render, the banner on the next new session, watch within one poll. `/fugu:off` still mutes everything at once, independently of these switches.

`hud.reset` and `hud.pace` only show when `hud.rate` is on. `FUGU_MOOD=off` in the environment also hides the fish.
