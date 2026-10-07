---
name: update
argument-hint: "[check]"
description: Update fugu to the latest release everywhere it is installed (every scope; aimux profiles share one plugin folder). Use when the user says "/fugu update", "update fugu", "upgrade fugu", "is fugu up to date", or asks which fugu version they're on.
---

# Update fugu

Run the bundled CLI (on PATH while fugu is enabled):

```bash
fugu-update --check   # what's installed vs the latest release; changes nothing
fugu-update           # pull the marketplace clone (only if it's a clean main), refresh, update every install
```

Arguments the user passed: "$ARGUMENTS"

- "check", "status", "what version" → `fugu-update --check` only.
- Otherwise run `fugu-update` and show its output as-is.
- If it says it is not pulling because the clone isn't on a clean main, tell the user which branch or changes are in the way; never stash, reset, or switch branches for them.
- Updates load in new sessions. Tell the user to start a new session (or /resume this one) to use the new version.
