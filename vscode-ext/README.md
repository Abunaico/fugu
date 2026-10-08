# Fugu Status (VS Code)

Minimum-viable status bar item for people driving Claude Code through the
official **Claude Code** VS Code extension (not the terminal CLI), who never
see fugu's terminal HUD.

Shows context-window usage for the current workspace's Claude Code session,
read from `fugu-context --json` — no new computation, just a read-only poll
of data fugu already produces.

## Requirements

- fugu installed and `fugu-context` on PATH (same requirement as the fugu
  skills/CLI).
- The official `anthropic.claude-code` VS Code extension, used at least once
  in the open workspace (so a session transcript exists under
  `~/.claude/projects/`).

## Install (dev/local)

```bash
cd vscode-ext
/Applications/Visual\ Studio\ Code.app/Contents/Resources/app/bin/code \
  --install-extension $(pwd) 2>/dev/null || \
  npx --yes @vscode/vsce package && \
  code --install-extension fugu-status-0.1.0.vsix
```

Simplest path for now: symlink or copy this folder into
`~/.vscode/extensions/fugu-status-0.1.0/` and reload VS Code.

## What it does

- Polls `fugu-context --project <workspace path> --json` every
  `fuguStatus.pollIntervalSeconds` (default 20s).
- Renders `<icon> NN%` in the status bar, with a tooltip breakdown (title,
  model, top context categories).
- Turns the status bar item warning-colored at ≥80% (fugu's autocompact
  threshold).
- Click to see a one-line summary; `Fugu: Refresh Now` command to force a
  poll.

## What it deliberately doesn't do (yet)

No 5h/weekly limits, no cost/burn, no multi-account, no fleet view. Those
each map to another existing `fugu-*` JSON command and are cheap follow-ons,
not a redesign — see `../CLAUDE.md` / `../README.md` for what's available.

## Known limitation

`fugu-context` resolves "which session" via `--project <substr>`, matched
against the transcript directory name (which encodes the session's cwd).
This extension passes the workspace folder's absolute path, which fugu
normalizes internally — but if two open workspaces share a very similar
path, the match could be ambiguous. Not handled in this MVP.
