#!/bin/bash
# fugu session banner — SessionStart hook.
# stdout from a SessionStart hook is added to Claude's context, so keep it tiny.
# NOTE: this hook's stdout enters model context — treat as a trust boundary.
# Any dynamic value added here must be control-char-stripped first.
# Record which fugu copy Claude Code loaded this session, for the HUD launcher
# (~/.fugu/bin/statusline). Done before any mute check so updates are picked up
# even while fugu is quiet. One write, only when the copy changed.
if [ -n "$CLAUDE_PLUGIN_ROOT" ] && [ -f "$CLAUDE_PLUGIN_ROOT/statusline.sh" ]; then
  mkdir -p "$HOME/.fugu" 2>/dev/null && chmod 700 "$HOME/.fugu" 2>/dev/null
  cur=""; read -r cur < "$HOME/.fugu/root" 2>/dev/null
  if [ "$cur" != "$CLAUDE_PLUGIN_ROOT" ] && [ ! -L "$HOME/.fugu/root" ]; then
    ( umask 077; printf '%s\n' "$CLAUDE_PLUGIN_ROOT" > "$HOME/.fugu/root" ) 2>/dev/null
  fi
fi
# /fugu:off drops this marker — go fully silent, don't even spend the find().
[ -f "$HOME/.fugu/disabled" ] && exit 0
# /fugu:settings: banner=off in ~/.fugu/config.
grep -qE '^[[:space:]]*banner[[:space:]]*=[[:space:]]*off[[:space:]]*$' "$HOME/.fugu/config" 2>/dev/null && exit 0
n=$(find "$HOME/.claude/projects" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d ' ')
cat <<EOF
🐡 fugu served. ABUNAI — HANDLE WITH CARE.
Session radar covers ${n} project dirs — /fugu:sessions to scan.
EOF
