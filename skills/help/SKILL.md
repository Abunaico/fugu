---
name: help
description: List fugu's commands and what each one does, including how to customize reports. Use when the user says "/fugu help", "fugu commands", "what can fugu do", "how do I customize reports", or asks which fugu command to use.
---

# fugu help

Run the bundled CLI (on PATH while fugu is enabled) and present what it prints:

```bash
fugu-help --plain
```

- Show the first two lines as a heading, the commands as a two-column table, and the "Customize reports" part as a short section with its three commands. Keep the closing note about what calls a model.
- Then add one line: run `! fugu-help` (or `! fugu-help --puff`) to see FUGU in full color in the terminal. The chat view can't show terminal colors, so don't paste the colored art here.
- Answer any follow-up about a specific command afterward.
- If a command reports "Unknown command", fugu was updated during this session: Claude Code reads a plugin's commands at session start, so start a new session (or resume this one) to pick it up.
