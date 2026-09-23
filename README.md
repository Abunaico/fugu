# 🐡 FUGU: Fleet & Usage Gauge Utility

**Harness chrome for Claude Code.**
Simple as Grokbot. Powerful as Hermes. Meme as OpenClaw. The *abunai* fish:
prepared wrong, it kills. So FUGU watches your gauges, and it inflates as your context fills.

```
🐡 Opus 5.5 [high · Explanatory] · 📁 fugu · main ✔ · 👤 you@example.com (max)
██░░░░░░░░ 17% 5h 62% ⏰1h30m →88% 7d 41% ⏰3d0h →71% cache 52m · $4.12
```

FUGU is a Claude Code plugin. It doesn't wrap, patch, or proxy the `claude` binary. Everything
runs inside the unmodified CLI under your own login, reading files Claude Code already writes to
your disk. No OAuth token handling, no credential intermediation, no network calls. Just chrome.

## What you get

| Piece | What it does |
|---|---|
| **HUD** (`statusline.sh`) | Two-line statusline. Line 1: model, effort level and output style, directory, git branch and dirty flag, the Anthropic account this session bills to. Line 2: color-coded context bar; 5h/7d rate-limit meters with reset countdown (⏰) and where you'll land at the current pace (→); how long until the prompt cache goes cold; session cost. The fish puffs up; the toxin ☠️ comes out at 90% context. |
| **Context + cache viewer** (`bin/fugu-context`) | What is filling the context window, how well the prompt cache is holding, and why it broke when it did. Per-turn usage, hit rate, cache breaks with a likely cause, largest context items, subagent usage. |
| **Accounts** (`bin/fugu-accounts`) | Every Claude Code login on the machine (default config plus profile dirs) with its last-known 5h/7d usage and reset times, side by side. Tells you which account has room without touching a single token. |
| **Fleet dashboard** (`subagent-statusline.sh`) | Every running subagent as `⚡ finder [opus-5] ▸ running · 42k 21%`. Fits the terminal: model, context %, tokens, and status drop in that order, then the name is clipped with `…`. Applied automatically while the plugin is enabled. |
| **Session radar** (`bin/fugu-sessions`) | Cross-project index of every Claude Code session on the machine: age, size, first prompt, resume command. Incremental byte-range indexing, so only new bytes are ever re-read. |
| **Watch** (`bin/fugu-watch`) | Background monitor. Tells you in-session when *another* session finishes its turn, stops on an error, or goes quiet mid-turn (possible stall). |
| **Banner** | SessionStart hook. You'll know it when you see it. |

### Skills

| Skill | Use it for |
|---|---|
| `/fugu:hud` | Check, install, repair, or remove the HUD statusline |
| `/fugu:context` | Context breakdown and cache report for this (or any) session |
| `/fugu:accounts` | Usage across every login on the machine |
| `/fugu:sessions` | Scan the session radar |
| `/fugu:open` | Resume or fork a session into a new tmux/Warp pane |
| `/fugu:fleet` | Explain or tune the subagent dashboard |
| `/fugu:settings` | Turn individual features on or off |
| `/fugu:off`, `/fugu:on` | Mute or unmute everything without uninstalling |
| `/fugu:help` | List every fugu command |

## Install

Inside Claude Code:

```
/plugin marketplace add Abunaico/fugu
/plugin install fugu@fugu-tools
```

Then start a new session and run:

```
/fugu:hud install   # points your statusLine at fugu's launcher (timestamped settings backup)
/fugu:sessions      # scan the radar
/fugu:context       # see what's in your context
```

To try it for one session without installing, clone the repo and load it directly:

```bash
git clone https://github.com/Abunaico/fugu.git
claude --plugin-dir ./fugu
```

Updates reach the HUD on their own. Claude Code only lets a plugin ship the subagent row
renderer, so the main statusLine is a user setting holding a path. `/fugu:hud` points it at a
small launcher, `~/.fugu/bin/statusline`, rather than at a plugin copy. Each session start records
which fugu copy Claude Code loaded, and the launcher runs that one. After `/plugin update`, the
next session is on the new version with no reinstall. `/fugu:hud` with no argument reports
what's wired, which copy is live, and any leftover copies. The fleet dashboard needs no setup.

**Uninstall:** `/fugu:hud remove` (it only removes a statusLine that is fugu's), then remove the
plugin. Caches live in `~/.cache/fugu` and `~/.fugu`.

## Context + cache viewer

```bash
fugu-context                        # this session
fugu-context <session-id>           # any session
fugu-context --project myrepo       # newest session in a project
fugu-context --turns 30 --top 15    # more history, more items
fugu-context --json                 # machine-readable
```

```
CONTEXT
  █████████████████████████░░░░░ 166k / 200k  83%
  autocompact at 80% · threshold passed

  hooks & attachments      ≈   74k  44% ████████████████
  system prompt + tools        63k  38% ██████████████░░
  result: Bash             ≈   16k  10% ███░░░░░░░░░░░░░
  ...

CACHE
  hit rate 96% over 29 requests · input billed at 17% of uncached
  read 3.85M · write 140k (5m 0 / 1h 140k) · uncached 58 · output 27k

  cache breaks (1)
  14:02  rewrote   90k  cold start
```

What's measured and what's estimated:

- **Measured:** every usage number, the hit rate, the per-turn table, and cache breaks. These come
  straight from the API usage Claude Code records in the session transcript (deduplicated per
  request, since one streamed response is logged as several lines).
- **Estimated (`≈`):** the per-category breakdown and largest items. Content is sized by character
  count, then scaled so the categories add up to the measured window. "System prompt + tools" is
  the first request's measured size minus the first prompt.
- **Cache breaks** are requests that rewrote a large part of the prefix instead of reading it. The
  cause is inferred: idle past the cache TTL (5m or 1h), a compaction, a model switch, or a changed
  prefix (tools, MCP servers, or system prompt changed mid-session).
- **"Input billed at X% of uncached"** applies the standard cache multipliers (read 0.1×, 5m write
  1.25×, 1h write 2×) to your actual token mix. It's model-agnostic; no price table involved.
- **Window size** is recorded by the HUD on each render, since transcripts don't carry it. Without
  the HUD it's assumed (200k, or 1M if the session ever went past 200k). Override with `--window`.

## HUD gauges

- **`5h 62% ⏰1h30m →88%`**: 62% used, the window resets in 1h30m, and at the current pace
  you'll end the window around 88%. The projection is linear and stays hidden for the first
  10% of a window, where it's noise. It turns yellow at 85% and red at 100%.
- **`cache 52m`**: time until the prompt cache expires. Every request refreshes it. `cold` means
  the next message rewrites the whole context at the cache-write price. It uses Claude Code's own
  `prompt_cache.expires_at` when present; on older versions it falls back to the last cache
  write in the transcript (only the last 256 KB is read).
- **`[high · Explanatory]`**: effort level and output style. The default style isn't shown.
- **Fits the terminal.** Claude Code passes `COLUMNS` and cuts off anything wider, so the HUD
  sheds detail as the terminal narrows instead of losing the end of the line: pace projections
  go first, then reset countdowns, the bar, cost, and cache; on line 1 the output style, plan,
  git, and account. Segments that fit again come back. `FUGU_HUD_WIDTH` overrides the width.

## Accounts

```
🐡 fugu accounts — 3 profiles

  ● you@example.com      max   5h ███░░░  45% ⏰2h10m  7d ██░░░░  31% ⏰4d6h   3m ago  default
    you@work.example     team  5h ░░░░░░   4% ⏰4h02m  7d █░░░░░  12% ⏰2d1h   1h ago  work
    side@example.com     pro   5h    —                 7d    —                never seen  side
```

Usage per account is the newest of two readings: what the HUD saw the last time it rendered for
that account, and the utilization Claude Code caches in the profile's `.claude.json`. A window
whose reset time has passed shows 0%. Profiles are found in `~/.claude.json`, `$CLAUDE_CONFIG_DIR`,
`~/.aimux/profiles/*`, `~/.claude-profiles/*`, and `$FUGU_PROFILE_DIRS` (colon-separated). To
work as another account, start Claude Code with that profile: `CLAUDE_CONFIG_DIR=<dir> claude`.
fugu never copies or swaps credentials.

## Settings

Every feature can be switched off on its own. Run `/fugu:settings` for a picker, or use the CLI:

```bash
fugu-config                      # every feature and its state
fugu-config off hud.cost hud.git # hide segments
fugu-config on hud.cost
fugu-config reset                # everything back on
```

| Key | Controls |
|---|---|
| `hud.fish` | the pufferfish (and the skull at 90%) |
| `hud.mode` | effort level and output style |
| `hud.git` | git branch and dirty flag |
| `hud.account` | active Anthropic account |
| `hud.rate` | 5h/7d rate-limit meters |
| `hud.reset` | reset countdown on the meters |
| `hud.pace` | pace projection on the meters |
| `hud.cache` | prompt-cache countdown |
| `hud.cost` | session cost |
| `fleet` | subagent fleet rows |
| `banner` | session start banner |
| `watch` | cross-session watch notifications |

State lives in `~/.fugu/config` as `key=off` lines (anything not listed is on), so you can
also edit it by hand. The HUD parses it in pure bash, so a switched-off feature costs nothing and
also skips its work (no git refresh, no transcript read). Changes apply on the next render.

## Knobs

- `FUGU_MOOD=off` deflates the fish (why would you). Same as `fugu-config off hud.fish`.
- `/fugu:off` and `/fugu:on` toggle a marker file (`~/.fugu/disabled`) that the HUD, fleet
  dashboard, banner, and watcher all check on every run. A live `fugu-watch` goes quiet within
  one poll, no restart needed.
- The HUD never runs git inline. Git status is cached for 5s per directory and refreshed by a
  detached background job, so a hung network mount can't stall the render.
- The account segment follows `CLAUDE_CONFIG_DIR`, so each profile shows its own login. If
  `ANTHROPIC_API_KEY` is set it shows `API key` instead (the key itself is never printed).
- `fugu-sessions --project <substr> --limit N --json --active --search <text> --reindex`.
  The cache lives at `~/.fugu/sessions-cache.json`: one full scan, then warm scans in tens of
  milliseconds.

## Privacy

FUGU only reads files on your machine that Claude Code already wrote: session transcripts under
`~/.claude/projects` and the account profile in `.claude.json` (email, org name, plan type; never
tokens). It writes only to `~/.cache/fugu` (git status, window size, cache TTL tier, and last-seen usage per
account) and `~/.fugu` (settings and the radar index), both private to your user, and skips writing
if the cache dir isn't owned by you. Nothing leaves your machine. Text that comes from transcripts,
repos, or config (titles, paths, branch names, emails, model names) is stripped of terminal control
characters, including C1 and carriage returns, before it reaches your terminal or Claude's context.

## Requirements

`jq`, `node`, macOS or Linux, and Claude Code. The rate meters need a Pro/Max login and appear
after the first response. The test battery also uses `python3`.

## Development

```bash
bash test/run-tests.sh
```

The battery covers degraded input, terminal-escape injection, the non-blocking render path,
incremental indexing edge cases, the off/on toggle, and the context viewer's usage math. Add a
test with every fix.

## License

MIT. See [LICENSE](LICENSE).

FUGU runs alongside Claude Code; it is not affiliated with or endorsed by Anthropic. Each user
authenticates with their own account. Don't point it at other people's sessions.
