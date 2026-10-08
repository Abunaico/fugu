# 🐡 Fugu for VS Code

fugu's HUD is a Claude Code statusLine, and the Claude Code VS Code extension never runs that
hook, so its users don't see it. This extension brings the same data into VS Code. It is
read-only and computes nothing itself: it calls fugu's own `fugu-*` commands and renders what
they return.

## What you get

- **Status bar**: `🐡 49% · $0.75` is context used by this workspace's Claude Code session and
  today's spend on this project. `🐡 ⚠` from 60% context, `🐡 🔥` from 80% (autocompact), with a
  warning background. Hover for the session, model, and what's filling the context; click to
  open the dashboard.
- **Sidebar**: the fish in the Activity Bar opens a docked dashboard that refreshes every 20s
  while it's visible.
- **Dashboard tab**: the same dashboard in an editor tab (**🐡 Fugu: Open Dashboard**).

The dashboard shows spend, sessions, and requests today; the context meter with its autocompact
mark; cost by project; insights (fugu-burn's measured levers, plus Haiku-written patterns when
`model.haiku` is `on`); recent sessions; and your Claude Code accounts. It uses fugu's arcade look
(the same as the `fugu-burn --html` report), switches to its navy dark mode with a dark VS Code
theme, and folds to one column in a narrow sidebar.

Commands (Command Palette, **🐡 Fugu**): Open Dashboard, Show Context Detail, Refresh Now.

## Install

```bash
npx github:Abunaico/fugu --vscode
```

Then reload VS Code (**Developer: Reload Window**). The installer copies this folder together
with fugu's `panel/`, `lib/`, `bin/`, and the fish art into `~/.vscode/extensions/infernored.fugu-status-<version>`,
so the extension is self-contained and keeps working after npx clears its cache.
`npx github:Abunaico/fugu update` refreshes it; `... uninstall` removes it.

**Developing:** symlink the repo folder instead, so edits apply on reload:

```bash
ln -s "$PWD/vscode-ext" ~/.vscode/extensions/fugu-status-dev
```

In the repo, the extension loads `../panel/`; in an installed copy, `./panel/`
(`panel-path.js` picks whichever exists). The installer leaves a symlinked dev install alone
unless you pass `--force`.

## Settings

| Setting | Default | |
|---|---|---|
| `fuguStatus.pollIntervalSeconds` | 20 | status bar refresh (min 5) and sidebar refresh (min 10) |
| `fuguStatus.costPollIntervalSeconds` | 60 | status bar cost refresh (min 15) |
| `fuguStatus.showCost` | true | show today's cost in the status bar |
| `fuguStatus.theme` | `fugu` | `fugu` (arcade look) or `editor` (blend in with your VS Code theme) |
| `fuguStatus.fugu*Path` | bundled | override the `fugu-context`, `fugu-burn`, `fugu-accounts`, `fugu-sessions` binaries |

Haiku insights follow fugu's own setting: `fugu-config set model.haiku on` (or `off`). They run
at most hourly while a dashboard is open; see Privacy in the main [README](../README.md#privacy).

## How it finds your session

The workspace folder's path is passed to `fugu-context --project`, which matches it against
Claude Code's transcript folders under `~/.claude/projects/`. The Claude Code VS Code extension
writes the same transcripts as the CLI, so it works for both. Two open workspaces with very
similar paths can match the same folder.

## Troubleshooting

- **"Some data failed to load: spawn fugu-burn ENOENT"**: an older copy that relied on your shell
  PATH. Reinstall; current versions call their bundled `bin/` by path.
- **`🐡 —`**: no Claude Code session in this workspace yet. Send a message in the Claude Code
  panel, and it appears on the next refresh.
- **Nothing in the status bar**: no folder is open; the item needs a workspace folder.
