#!/bin/bash
# fugu test battery — regression guards for every audited defect class.
# Run from the plugin root: bash test/run-tests.sh
set -u
cd "$(dirname "$0")/.." || exit 1
PASS=0; FAIL=0
ok()   { PASS=$((PASS+1)); echo "  ✔ $1"; }
bad()  { FAIL=$((FAIL+1)); echo "  ✘ $1"; }
chk()  { [ "$2" = "$3" ] && ok "$1" || bad "$1 (got: $2, want: $3)"; }

# Sandbox the whole run: no test may read or write the real ~/.claude, ~/.fugu,
# or ~/.cache/fugu, and host env (profiles, API keys, session ids) can't leak in.
SANDBOX=$(mktemp -d)
trap 'rm -rf "$SANDBOX"' EXIT
export HOME="$SANDBOX/home" XDG_CACHE_HOME="$SANDBOX/cache"
mkdir -p "$HOME" "$XDG_CACHE_HOME"
unset CLAUDE_CONFIG_DIR ANTHROPIC_API_KEY CLAUDE_CODE_SESSION_ID CLAUDE_SESSION_ID FUGU_MOOD FUGU_PROFILE_DIRS NO_COLOR COLUMNS FUGU_HUD_WIDTH
strip_ansi() { LC_ALL=C sed $'s/\033\\[[0-9;]*m//g'; }

echo "— statusline degradation —"
out=$(echo 'not json' | ./statusline.sh 2>&1); echo "$out" | grep -q 'jq:' && bad "garbage stdin silent" || ok "garbage stdin silent"
out=$(echo -n '' | ./statusline.sh 2>&1); echo "$out" | grep -qE 'error|expected' && bad "empty stdin silent" || ok "empty stdin silent"
out=$(echo '{}' | ./statusline.sh 2>/dev/null | head -1); echo "$out" | grep -q '📁 ?' && ok "empty cwd → ?" || bad "empty cwd → ? (got: $out)"
out=$(echo '{"workspace":{"current_dir":"/tmp"},"context_window":{"used_tokens":190000,"context_window_size":200000}}' | ./statusline.sh | head -1)
echo "$out" | grep -q '☠️' && ok "toxin ≥90% (95% input)" || bad "toxin ≥90% (95% input)"

echo "— statusline injection —"
out=$(python3 -c 'import json;print(json.dumps({"model":{"display_name":"Ev]0;pwnil"},"workspace":{"current_dir":"/tmp"}}))' | ./statusline.sh | head -1)
case "$out" in *$'\x1b]'*) bad "ESC stripped from model name";; *) ok "ESC stripped from model name";; esac

echo "— statusline render path never blocks —"
grep -n 'git ' statusline.sh | grep -v '(' | grep -qv '#' && bad "inline git found" || ok "git only in background subshell"

echo "— fleet —"
out=$(echo '{"tasks":[{"id":"t1","name":"f","status":"running","tokenCount":42300,"contextWindowSize":200000}]}' | ./subagent-statusline.sh)
echo "$out" | jq -e '.id=="t1"' >/dev/null && ok "row JSON valid" || bad "row JSON valid"
out=$(echo '{"tasks":[{"id":"t2","name":"x","status":"s","tokenCount":"NaN"}]}' | ./subagent-statusline.sh 2>&1)
echo "$out" | grep -q 'integer expression' && bad "NaN tokenCount guarded" || ok "NaN tokenCount guarded"
out=$(echo garbage | ./subagent-statusline.sh 2>&1); [ -z "$out" ] && ok "garbage stdin silent" || bad "garbage stdin silent"
fleet() { echo "$1" | ./subagent-statusline.sh | jq -r .content | strip_ansi; }
out=$(fleet '{"tasks":[{"id":"t1","name":"n","status":"running"}]}')
case "$out" in *'['*) bad "no model: fields don't shift (got: $out)";; *'n ▸ running'*) ok "no model: fields don't shift";; *) bad "no model row (got: $out)";; esac
FT='{"columns":COLS,"tasks":[{"id":"t1","name":"semantic-context-evaluator","status":"running","model":"claude-opus-5-5","tokenCount":42300,"contextWindowSize":200000}]}'
fw() { fleet "${FT/COLS/$1}" | python3 -c 'import sys,unicodedata
l=sys.stdin.read().rstrip("\n"); print(sum(0 if c=="\ufe0f" else (2 if unicodedata.east_asian_width(c) in "WF" else 1) for c in l))'; }
fit=1; for w in 20 30 40 50 60 80; do m=$(fw $w); [ "$m" -le $((w - 8)) ] || { fit=0; bad "fleet fits columns=$w (width $m)"; }; done
[ "$fit" = 1 ] && ok "fleet rows fit columns (20–80)"
chk "wide terminal: full row" "$(fleet "${FT/COLS/120}")" "⚡ semantic-context-evaluator [opus-5-5] ▸ running · 42k 21%"
chk "model drops first" "$(fleet "${FT/COLS/60}")" "⚡ semantic-context-evaluator ▸ running · 42k 21%"
chk "name clipped last" "$(fleet "${FT/COLS/30}")" "⚡ semantic-context-e…"
out=$(fleet '{"columns":20,"tasks":[{"id":"t1","name":"日本語のエージェント名です","status":"running"}]}')
case "$out" in *…) ok "multibyte name clipped cleanly";; *) bad "multibyte name clipped cleanly (got: $out)";; esac
echo "$out" | iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1 && ok "clip never splits a character" || bad "clip split a character"

echo "— radar: carry/resume correctness —"
T=$(mktemp -d); mkdir -p "$T/.claude/projects/-tmp-ct"
F="$T/.claude/projects/-tmp-ct/dddddddd-1111-2222-3333-444444444444.jsonl"
printf '%s\n' '{"type":"user","timestamp":"2026-09-17T01:00:00Z","cwd":"/tmp/ct","message":{"content":"first prompt long enough to pass the two hundred byte size gate for the radar scanner yes indeed truly"}}' > "$F"
printf '{"type":"assistant","timestamp":"2026-09-17T01:00:05Z","message":{"content":[{"type":"text","text":"partial' >> "$F"
chk "mid-line tail counted parseable-only" "$(HOME=$T node bin/fugu-sessions --json | jq -r '.[0].messages')" "1"
printf ' done"}]}}\n{"type":"user","timestamp":"2026-09-17T01:01:00Z","message":{"content":"second"}}\n' >> "$F"
chk "resume after completion (no double)" "$(HOME=$T node bin/fugu-sessions --json | jq -r '.[0].messages')" "3"
printf '{"type":"assistant","timestamp":"2026-09-17T01:02:00Z","message":{"content":[{"type":"text","text":"tail"}]}}' >> "$F"
chk "complete no-newline tail displayed" "$(HOME=$T node bin/fugu-sessions --json | jq -r '.[0].messages')" "4"
printf '\n{"type":"user","timestamp":"2026-09-17T01:03:00Z","message":{"content":"fifth"}}\n' >> "$F"
chk "newline lands + append (no double)" "$(HOME=$T node bin/fugu-sessions --json | jq -r '.[0].messages')" "5"

echo "— radar: UTF-8 chunk boundary —"
python3 -c "
import json
l1=json.dumps({'type':'user','timestamp':'2026-09-17T01:00:00Z','cwd':'/tmp/u8','message':{'content':'x'*1048570}})
l2=json.dumps({'type':'assistant','timestamp':'2026-09-17T01:00:01Z','message':{'content':[{'type':'text','text':'🐡'*100}]}},ensure_ascii=False)
l3=json.dumps({'type':'user','timestamp':'2026-09-17T01:00:02Z','message':{'content':'after'}})
open('$T/.claude/projects/-tmp-ct/cccccccc-1111-2222-3333-444444444444.jsonl','w').write(l1+'\n'+l2+'\n'+l3+'\n')
"
chk "emoji straddling 1MB chunk" "$(HOME=$T node bin/fugu-sessions --json | jq -r '.[]|select(.id[0:1]=="c").messages')" "3"
printf '%s\n' '{"type":"assistant","timestamp":"2026-09-17T01:00:09Z","message":{"content":[{"type":"text","text":"more"}]}}' >> "$T/.claude/projects/-tmp-ct/cccccccc-1111-2222-3333-444444444444.jsonl"
chk "resume across utf8 boundary" "$(HOME=$T node bin/fugu-sessions --json | jq -r '.[]|select(.id[0:1]=="c").messages')" "4"

echo "— radar: title injection + type safety —"
printf '%s\n' '{"type":"user","timestamp":"2026-09-17T01:00:00Z","cwd":"/t","message":{"content":"prompt long enough to pass the two hundred byte size gate for the radar scanner ok fine yes"}}' '{"type":"custom-title","customTitle":42}' > "$T/.claude/projects/-tmp-ct/eeeeeeee-1111-2222-3333-444444444444.jsonl"
HOME=$T node bin/fugu-sessions >/dev/null 2>&1 && ok "numeric customTitle no crash" || bad "numeric customTitle no crash"
printf '%s\n' '{"type":"ai-title","aiTitle":"evil]0;pwntitle"}' >> "$T/.claude/projects/-tmp-ct/eeeeeeee-1111-2222-3333-444444444444.jsonl"
out=$(HOME=$T node bin/fugu-sessions 2>/dev/null)
case "$out" in *$'\x1b]0;pwn'*) bad "title ESC stripped";; *) ok "title ESC stripped";; esac

echo "— radar: flags —"
chk "--limit garbage falls back" "$(HOME=$T node bin/fugu-sessions --limit nope --json | jq 'length > 0')" "true"
HOME=$T node bin/fugu-sessions --limit >/dev/null 2>&1 && ok "--limit at argv end no crash" || bad "--limit at argv end no crash"
rm -rf "$T"

echo "— gate C regressions —"
# 0x1f in a field value must not shift downstream fields
out=$(python3 -c 'import json,sys;sys.stdout.write(json.dumps({"model":{"display_name":"A\u001fB"},"workspace":{"current_dir":"/tmp"},"context_window":{"used_tokens":100000,"context_window_size":200000}}))' | ./statusline.sh | sed -n 2p)
echo "$out" | grep -q '50%' && ok "0x1f in value cannot shift fields" || bad "0x1f in value cannot shift fields (got: $out)"
# fast path must serve the same count as the indexing run (no flicker)
T2=$(mktemp -d); mkdir -p "$T2/.claude/projects/-tmp-fp"
FF="$T2/.claude/projects/-tmp-fp/ffffffff-1111-2222-3333-444444444444.jsonl"
printf '%s\n' '{"type":"user","timestamp":"2026-09-17T01:00:00Z","cwd":"/t","message":{"content":"prompt long enough to pass the two hundred byte size gate for the radar scanner ok fine yes truly"}}' > "$FF"
printf '{"type":"assistant","timestamp":"2026-09-17T01:00:05Z","message":{"content":[{"type":"text","text":"complete tail no newline"}]}}' >> "$FF"
a=$(HOME=$T2 node bin/fugu-sessions --json | jq -r '.[0].messages')
b=$(HOME=$T2 node bin/fugu-sessions --json | jq -r '.[0].messages')
chk "fast path serves display state" "$a/$b" "2/2"
# refresh lock: only one background refresh may spawn per window
rm -rf "$T2"
L="${XDG_CACHE_HOME:-$HOME/.cache}/fugu"
cksum_key=$(printf '%s' "/tmp" | cksum | cut -d' ' -f1)
rm -rf "$L/git-$cksum_key" "$L/git-$cksum_key.lock" 2>/dev/null
echo '{"workspace":{"current_dir":"/tmp"}}' | ./statusline.sh >/dev/null
[ -d "$L/git-$cksum_key.lock" ] || sleep 0.3   # first refresh may already have finished
echo '{"workspace":{"current_dir":"/tmp"}}' | ./statusline.sh >/dev/null
n=$(find "$L" -name ".git-*" 2>/dev/null | wc -l | tr -d ' ')
[ "$n" -le 1 ] && ok "no orphaned refresh tmp files" || bad "orphaned refresh tmp files: $n"

echo "— radar: self marker —"
TY=$(mktemp -d); mkdir -p "$TY/.claude/projects/-tmp-y"
SID=aaaaaaaa-1111-2222-3333-444444444444
printf '%s\n' '{"type":"user","timestamp":"2026-09-17T01:00:00Z","cwd":"/tmp/y","message":{"content":"a prompt long enough to clear the radar two hundred byte gate, padded out with more words and then some more words"}}' > "$TY/.claude/projects/-tmp-y/$SID.jsonl"
out=$(HOME=$TY CLAUDE_CODE_SESSION_ID=$SID node bin/fugu-sessions | strip_ansi)
case "$out" in *'◀ you'*) ok "◀ you via CLAUDE_CODE_SESSION_ID";; *) bad "◀ you via CLAUDE_CODE_SESSION_ID";; esac
out=$(HOME=$TY CLAUDE_SESSION_ID=$SID node bin/fugu-sessions | strip_ansi)
case "$out" in *'◀ you'*) ok "◀ you via legacy CLAUDE_SESSION_ID";; *) bad "◀ you via legacy CLAUDE_SESSION_ID";; esac
out=$(HOME=$TY node bin/fugu-sessions | strip_ansi)
case "$out" in *'◀ you'*) bad "no marker without a session id";; *) ok "no marker without a session id";; esac
rm -rf "$TY"

echo "— watch monitor —"
node --check bin/fugu-watch 2>/dev/null && ok "fugu-watch syntax" || bad "fugu-watch syntax"
TW=$(mktemp -d); mkdir -p "$TW/.claude/projects/-tmp-w"
FW="$TW/.claude/projects/-tmp-w/99999999-1111-2222-3333-444444444444.jsonl"
printf '%s\n' '{"type":"user","timestamp":"2026-09-17T01:00:00Z","cwd":"/t","message":{"content":"padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding padding"}}' '{"type":"assistant","timestamp":"2026-09-17T01:00:05Z","message":{"content":[{"type":"text","text":"done"}]}}' > "$FW"
out=$(HOME=$TW FUGU_WATCH_ONCE=1 ./bin/fugu-watch)
[ -z "$out" ] && ok "watch silent on startup backlog" || bad "watch silent on startup backlog (got: $out)"
rm -rf "$TW"

echo "— /fugu:off toggle —"
TOFF=$(mktemp -d)
mkdir -p "$TOFF/.fugu" && touch "$TOFF/.fugu/disabled"
out=$(echo '{"workspace":{"current_dir":"/tmp"},"context_window":{"used_tokens":190000,"context_window_size":200000}}' | HOME=$TOFF ./statusline.sh)
[ -z "$out" ] && ok "statusline silent when disabled" || bad "statusline silent when disabled (got: $out)"
out=$(echo '{"tasks":[{"id":"t1","name":"f","status":"running","tokenCount":42300,"contextWindowSize":200000}]}' | HOME=$TOFF ./subagent-statusline.sh)
[ -z "$out" ] && ok "fleet silent when disabled" || bad "fleet silent when disabled (got: $out)"
out=$(HOME=$TOFF ./hooks/banner.sh)
[ -z "$out" ] && ok "banner silent when disabled" || bad "banner silent when disabled (got: $out)"
out=$(HOME=$TOFF FUGU_WATCH_ONCE=1 ./bin/fugu-watch)
[ -z "$out" ] && ok "watch silent when disabled" || bad "watch silent when disabled (got: $out)"
rm -f "$TOFF/.fugu/disabled"
out=$(echo '{"workspace":{"current_dir":"/tmp"}}' | HOME=$TOFF ./statusline.sh | head -1)
[ -n "$out" ] && ok "statusline resumes after /fugu:on" || bad "statusline resumes after /fugu:on"
out=$(echo '{"tasks":[{"id":"t1","name":"f","status":"running"}]}' | HOME=$TOFF ./subagent-statusline.sh)
echo "$out" | jq -e '.id=="t1"' >/dev/null && ok "fleet resumes after /fugu:on" || bad "fleet resumes after /fugu:on"
out=$(HOME=$TOFF ./hooks/banner.sh)
[ -n "$out" ] && ok "banner resumes after /fugu:on" || bad "banner resumes after /fugu:on"
rm -rf "$TOFF"

echo "— context viewer —"
TC=$(mktemp -d); mkdir -p "$TC/.claude/projects/-tmp-cv" "$TC/cache/fugu"
CF="$TC/.claude/projects/-tmp-cv/cccccccc-1111-2222-3333-444444444444.jsonl"
python3 - "$CF" <<'PY'
import json, sys
u = lambda i, r, w5, o: {"input_tokens": i, "cache_read_input_tokens": r, "cache_creation_input_tokens": w5,
                         "cache_creation": {"ephemeral_5m_input_tokens": w5, "ephemeral_1h_input_tokens": 0}, "output_tokens": o}
L = [
  {"type": "custom-title", "customTitle": "Ev\u001b]0;pwn\u0007il"},
  {"type": "user", "uuid": "u1", "timestamp": "2026-09-17T10:00:00Z", "cwd": "/tmp/cv", "message": {"content": "hello"}},
  # one request streamed as two lines: usage must count once
  {"type": "assistant", "uuid": "a1", "timestamp": "2026-09-17T10:00:01Z", "message": {"id": "m1", "model": "claude-x", "usage": u(5, 0, 50000, 100), "content": [{"type": "thinking", "thinking": "hm"}]}},
  {"type": "assistant", "uuid": "a1b", "timestamp": "2026-09-17T10:00:01Z", "message": {"id": "m1", "model": "claude-x", "usage": u(5, 0, 50000, 100), "content": [{"type": "tool_use", "id": "t1", "name": "Bash", "input": {"command": "cat big"}}]}},
  {"type": "user", "uuid": "u2", "timestamp": "2026-09-17T10:00:02Z", "message": {"content": [{"type": "tool_result", "tool_use_id": "t1", "content": "x" * 8000}]}},
  {"type": "assistant", "uuid": "a2", "timestamp": "2026-09-17T10:01:00Z", "message": {"id": "m2", "model": "claude-x", "usage": u(5, 50000, 2000, 50), "content": [{"type": "text", "text": "ok"}]}},
  {"type": "user", "uuid": "u3", "timestamp": "2026-09-17T10:19:00Z", "message": {"content": "again"}},
  {"type": "assistant", "uuid": "a3", "timestamp": "2026-09-17T10:20:00Z", "message": {"id": "m3", "model": "claude-x", "usage": u(5, 0, 53000, 20), "content": [{"type": "text", "text": "back"}]}},
]
with open(sys.argv[1], "w") as f:
    for e in L: f.write(json.dumps(e) + "\n")
    f.write("{not json\n")
PY
cv() { HOME=$TC XDG_CACHE_HOME=$TC/cache CLAUDE_CONFIG_DIR= CLAUDE_CODE_SESSION_ID= node bin/fugu-context "$@"; }
J=$(cv cccccccc-1111-2222-3333-444444444444 --json)
chk "streamed request counted once" "$(echo "$J" | jq -r '.cache.requests')" "3"
chk "hit rate from measured usage" "$(echo "$J" | jq -r '.cache.hitRate * 1000 | floor')" "322"
chk "cold start detected" "$(echo "$J" | jq -r '.cache.breaks[0].reason')" "cold start"
echo "$J" | jq -r '.cache.breaks[1].reason' | grep -q '^TTL expired' && ok "idle TTL break detected" || bad "idle TTL break detected"
chk "current context = last request" "$(echo "$J" | jq -r '.context.current')" "53005"
echo "$J" | jq -e '.context.composition[] | select(.cat=="result: Bash")' >/dev/null && ok "tool result attributed to tool" || bad "tool result attributed to tool"
chk "window assumed without HUD record" "$(echo "$J" | jq -r '.context.windowSource')" "assumed"
printf 1000000 > "$TC/cache/fugu/win-cccccccc-1111-2222-3333-444444444444"
chk "window read from HUD record" "$(cv cccccccc-1111-2222-3333-444444444444 --json | jq -r '.context.window')" "1000000"
out=$(cv --project cv); case "$out" in *$'\x1b]'*) bad "title ESC stripped";; *) ok "title ESC stripped";; esac
echo "$out" | grep -q 'CACHE' && ok "--project finds newest session" || bad "--project finds newest session"
printf '%s\n' '{"type":"system","subtype":"compact_boundary","timestamp":"2026-09-17T10:30:00Z","compactMetadata":{"trigger":"auto","preTokens":53005,"postTokens":4000}}' \
  '{"type":"user","uuid":"s1","isCompactSummary":true,"timestamp":"2026-09-17T10:30:01Z","message":{"content":"summary"}}' >> "$CF"
J=$(cv cccccccc-1111-2222-3333-444444444444 --json)
echo "$J" | jq -e '[.context.composition[].cat] | index("result: Bash") == null' >/dev/null && ok "compaction drops pre-boundary items" || bad "compaction drops pre-boundary items"
chk "compaction recorded" "$(echo "$J" | jq -r '.context.compactions[0].trigger')" "auto"
out=$(cv no-such-session 2>&1); echo "$out" | grep -q 'not found' && ok "unknown session reports cleanly" || bad "unknown session reports cleanly"
rm -rf "$TC"

echo "— HUD gauges —"
TH=$(mktemp -d); mkdir -p "$TH/cache"
printf '%s' '{"oauthAccount":{"emailAddress":"hud@example.com","organizationType":"claude_max"}}' > "$TH/.claude.json"
hud() { HOME=$TH XDG_CACHE_HOME=$TH/cache CLAUDE_CONFIG_DIR= ANTHROPIC_API_KEY= ./statusline.sh | LC_ALL=C sed $'s/\033\\[[0-9;]*m//g'; }
NOW=$(date +%s)
# 5h window 80% elapsed at 60% used → pace projects 75%
out=$(jq -nc --argjson r $((NOW + 3600)) '{session_id:"h-1",workspace:{current_dir:"/tmp"},rate_limits:{five_hour:{used_percentage:60,resets_at:$r}}}' | hud | sed -n 2p)
echo "$out" | grep -qE '⏰(59m|1h00m)' && ok "5h reset countdown" || bad "5h reset countdown (got: $out)"
echo "$out" | grep -qE '→7[45]%' && ok "pace projection" || bad "pace projection (got: $out)"
out=$(jq -nc --argjson r $((NOW + 17000)) '{workspace:{current_dir:"/tmp"},rate_limits:{five_hour:{used_percentage:3,resets_at:$r}}}' | hud | sed -n 2p)
echo "$out" | grep -q '→' && bad "no projection early in window (got: $out)" || ok "no projection early in window"
iso=$(date -u -r $((NOW + 2*86400 + 7200)) +%Y-%m-%dT%H:%M:%S.123456+00:00 2>/dev/null || date -u -d @$((NOW + 2*86400 + 7200)) +%Y-%m-%dT%H:%M:%S.123456+00:00)
out=$(jq -nc --arg r "$iso" '{workspace:{current_dir:"/tmp"},rate_limits:{seven_day:{used_percentage:10,resets_at:$r}}}' | hud | sed -n 2p)
echo "$out" | grep -qE '⏰2d[12]h' && ok "ISO resets_at parsed" || bad "ISO resets_at parsed (got: $out)"
out=$(jq -nc --argjson r $(((NOW + 1800) * 1000)) '{workspace:{current_dir:"/tmp"},rate_limits:{five_hour:{used_percentage:10,resets_at:$r}}}' | hud | sed -n 2p)
echo "$out" | grep -qE '⏰(29|30)m' && ok "epoch-ms resets_at parsed" || bad "epoch-ms resets_at parsed (got: $out)"
out=$(echo '{"workspace":{"current_dir":"/tmp"},"context_window":{"used_percentage":42,"context_window_size":1000000}}' | hud | sed -n 2p)
echo "$out" | grep -q ' 42%' && ok "context % from used_percentage" || bad "context % from used_percentage (got: $out)"
out=$(echo '{"workspace":{"current_dir":"/tmp"},"context_window":{"context_window_size":200000,"current_usage":{"input_tokens":1,"cache_read_input_tokens":99999}}}' | hud | sed -n 2p)
echo "$out" | grep -q ' 50%' && ok "context % from current_usage" || bad "context % from current_usage (got: $out)"
out=$(echo '{"workspace":{"current_dir":"/tmp"},"effort":{"level":"high"},"output_style":{"name":"Explanatory"}}' | hud | head -1)
echo "$out" | grep -qF '[high · Explanatory]' && ok "effort + style shown" || bad "effort + style shown (got: $out)"
out=$(echo '{"workspace":{"current_dir":"/tmp"},"output_style":{"name":"default"}}' | hud | head -1)
echo "$out" | grep -q '\[' && bad "default style hidden (got: $out)" || ok "default style hidden"
TT="$TH/t.jsonl"
ts=$(date -u -r $((NOW - 120)) +%Y-%m-%dT%H:%M:%S.000Z 2>/dev/null || date -u -d @$((NOW - 120)) +%Y-%m-%dT%H:%M:%S.000Z)
printf '{"type":"assistant","timestamp":"%s","message":{"model":"x","usage":{"input_tokens":1,"cache_creation_input_tokens":9,"cache_creation":{"ephemeral_1h_input_tokens":9}}}}\n' "$ts" > "$TT"
out=$(jq -nc --arg t "$TT" '{session_id:"h-2",workspace:{current_dir:"/tmp"},transcript_path:$t}' | hud | sed -n 2p)
echo "$out" | grep -qE 'cache 5[78]m' && ok "1h cache countdown" || bad "1h cache countdown (got: $out)"
printf '{"type":"assistant","timestamp":"2026-01-01T00:00:00.000Z","message":{"model":"x","usage":{"input_tokens":1,"cache_creation_input_tokens":9,"cache_creation":{"ephemeral_5m_input_tokens":9}}}}\n' > "$TT"
out=$(jq -nc --arg t "$TT" '{session_id:"h-3",workspace:{current_dir:"/tmp"},transcript_path:$t}' | hud | sed -n 2p)
echo "$out" | grep -q 'cache cold' && ok "expired cache shows cold" || bad "expired cache shows cold (got: $out)"
jq -nc '{workspace:{current_dir:"/tmp"},rate_limits:{five_hour:{used_percentage:33}}}' | hud >/dev/null
chk "usage recorded per account" "$(cat "$TH"/cache/fugu/usage-* 2>/dev/null | jq -r '.email + " " + .v')" "hud@example.com 33|||"
rm -rf "$TH"

echo "— accounts —"
TA=$(mktemp -d); mkdir -p "$TA/.aimux/profiles/work" "$TA/.aimux/profiles/empty" "$TA/cache/fugu"
R7=$(date -u -r $((NOW + 86400)) +%Y-%m-%dT%H:%M:%S+00:00 2>/dev/null || date -u -d @$((NOW + 86400)) +%Y-%m-%dT%H:%M:%S+00:00)
jq -nc --arg r "$R7" '{oauthAccount:{emailAddress:"me@example.com",organizationType:"claude_max",accountUuid:"u1"},
  cachedUsageUtilization:{fetchedAtMs:1000,accountUuid:"u1",utilization:{five_hour:{utilization:90,resets_at:"2020-01-01T00:00:00+00:00"},seven_day:{utilization:44,resets_at:$r}}}}' > "$TA/.claude.json"
printf '%s' '{"oauthAccount":{"emailAddress":"w\u001b]0;x\u0007@corp.com","organizationType":"claude_team"}}' > "$TA/.aimux/profiles/work/.claude.json"
printf '{}' > "$TA/.aimux/profiles/empty/.claude.json"
k=$(printf '%s' 'me@example.com' | cksum | cut -d' ' -f1)
jq -nc --argjson at "$NOW" '{email:"me@example.com",plan:"max",v:"12|||",at:$at}' > "$TA/cache/fugu/usage-$k"
acc() { HOME=$TA XDG_CACHE_HOME=$TA/cache CLAUDE_CONFIG_DIR= FUGU_PROFILE_DIRS= node bin/fugu-accounts "$@"; }
J=$(acc --json)
chk "profiles discovered" "$(echo "$J" | jq -r 'length')" "3"
chk "newest reading wins per window" "$(echo "$J" | jq -r '.[] | select(.profile=="default") | "\(.usage.h5) \(.usage.d7)"')" "12 44"
chk "default profile active" "$(echo "$J" | jq -r '.[] | select(.active) | .profile')" "default"
chk "logged-out profile has no email" "$(echo "$J" | jq -r '.[] | select(.profile=="empty") | .email')" "null"
out=$(acc); case "$out" in *$'\x1b]'*) bad "account ESC stripped";; *) ok "account ESC stripped";; esac
jq '.cachedUsageUtilization.utilization.seven_day.resets_at = "2020-01-01T00:00:00+00:00"' "$TA/.claude.json" > "$TA/x" && mv "$TA/x" "$TA/.claude.json"
chk "reset window reads 0" "$(acc --json | jq -r '.[] | select(.profile=="default") | .usage.d7')" "0"
rm -rf "$TA"

echo "— settings —"
TS=$(mktemp -d); mkdir -p "$TS/.fugu"
printf '%s' '{"oauthAccount":{"emailAddress":"s@example.com","organizationType":"claude_pro"}}' > "$TS/.claude.json"
NOW=$(date +%s)
SJ=$(jq -nc --argjson r $((NOW + 3600)) '{workspace:{current_dir:"/tmp"},effort:{level:"high"},cost:{total_cost_usd:1.5},
  rate_limits:{five_hour:{used_percentage:60,resets_at:$r}}}')
cfgrun() { printf '%s\n' "$@" > "$TS/.fugu/config"; echo "$SJ" | HOME=$TS XDG_CACHE_HOME=$TS/cache ./statusline.sh | strip_ansi; }
out=$(cfgrun); for want in '🐡' '[high]' '👤 s@example.com' '5h 60%' '⏰' '→' '$1.50'; do
  case "$out" in *"$want"*) ;; *) bad "all features on by default (missing $want)"; break;; esac; done
case "$out" in *'🐡'*'[high]'*'$1.50'*) ok "all features on by default";; esac
chkoff() { local key=$1 gone=$2 out; out=$(cfgrun "$key=off"); case "$out" in *"$gone"*) bad "$key=off hides it (got: $out)";; *) ok "$key=off hides it";; esac; }
chkoff hud.fish '🐡'; chkoff hud.mode '[high]'; chkoff hud.account '👤'; chkoff hud.cost '$1.50'
chkoff hud.reset '⏰'; chkoff hud.pace '→'; chkoff hud.rate '5h'
out=$(cfgrun 'hud.rate = off'); case "$out" in *'5h'*) bad "config tolerates spaces";; *) ok "config tolerates spaces";; esac
out=$(cfgrun 'hud.cost=off' 'garbage line' 'hud.fish=maybe'); case "$out" in *'🐡'*) ok "unknown values ignored";; *) bad "unknown values ignored";; esac
printf 'fleet=off\n' > "$TS/.fugu/config"
out=$(echo '{"tasks":[{"id":"t1","name":"f","status":"running"}]}' | HOME=$TS ./subagent-statusline.sh); [ -z "$out" ] && ok "fleet=off yields default rows" || bad "fleet=off yields default rows"
printf 'banner=off\n' > "$TS/.fugu/config"
out=$(HOME=$TS ./hooks/banner.sh); [ -z "$out" ] && ok "banner=off silent" || bad "banner=off silent"
printf 'watch=off\n' > "$TS/.fugu/config"
out=$(HOME=$TS FUGU_WATCH_ONCE=1 ./bin/fugu-watch); [ -z "$out" ] && ok "watch=off silent" || bad "watch=off silent"
rm -f "$TS/.fugu/config"
HOME=$TS node bin/fugu-config off hud.cost fleet >/dev/null
chk "fugu-config writes key=off" "$(grep -cE '^[a-z.]+=off$' "$TS/.fugu/config")" "2"
chk "fugu-config file is private" "$(stat -c %a "$TS/.fugu/config" 2>/dev/null || stat -f %Lp "$TS/.fugu/config")" "600"
HOME=$TS node bin/fugu-config on hud.cost >/dev/null
chk "fugu-config on removes key" "$(HOME=$TS node bin/fugu-config --json | jq -r '[.["hud.cost"], .fleet] | map(tostring) | join(" ")')" "true false"
HOME=$TS node bin/fugu-config off nope >/dev/null 2>&1; chk "unknown feature rejected" "$?" "2"
HOME=$TS node bin/fugu-config reset >/dev/null
chk "reset turns all on" "$(HOME=$TS node bin/fugu-config --json | jq '[.[]] | all')" "true"
rm -rf "$TS"

echo "— hardening (review fixes) —"
TX=$(mktemp -d)
hasctl() { LC_ALL=C grep -q $'\x1b\\|\r\\|\xc2[\x80-\x9f]'; }
out=$(python3 -c 'import json;print(json.dumps({"model":{"display_name":"Op\u009b2J\u009d0;T\u009c"},"effort":{"level":"hi\rFAKE"},"output_style":{"name":"\u001b]0;x\u0007"},"workspace":{"current_dir":"/tmp/d\u009bx\ry"}}))' | HOME=$TX XDG_CACHE_HOME=$TX/c ./statusline.sh | LC_ALL=C sed $'s/\033\\[[0-9;]*m//g')
echo "$out" | hasctl && bad "HUD strips C1 + CR from stdin fields" || ok "HUD strips C1 + CR from stdin fields"
chk "HUD stays two lines" "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" "2"
printf '%s' '{"oauthAccount":{"emailAddress":"a\u009b31m\u009d0;pwn\u009c\rEVIL@x.com"}}' > "$TX/.claude.json"
out=$(echo '{"workspace":{"current_dir":"/tmp"}}' | HOME=$TX XDG_CACHE_HOME=$TX/c ./statusline.sh | LC_ALL=C sed $'s/\033\\[[0-9;]*m//g')
echo "$out" | hasctl && bad "HUD strips C1 from account email" || ok "HUD strips C1 from account email"
G="$TX/repo"; mkdir -p "$G"; git -C "$G" init -q 2>/dev/null; git -C "$G" checkout -q -b "$(printf 'main\xc2\x9d0;OWNED\xc2\x9c')" 2>/dev/null
echo "{\"workspace\":{\"current_dir\":\"$G\"}}" | HOME=$TX XDG_CACHE_HOME=$TX/c ./statusline.sh >/dev/null; sleep 1
out=$(echo "{\"workspace\":{\"current_dir\":\"$G\"}}" | HOME=$TX XDG_CACHE_HOME=$TX/c ./statusline.sh | head -1 | LC_ALL=C sed $'s/\033\\[[0-9;]*m//g')
case "$out" in *main*) echo "$out" | hasctl && bad "C1 stripped from git branch" || ok "C1 stripped from git branch";; *) ok "C1 stripped from git branch (git refused name)";; esac
NOW=$(date +%s)
out=$(jq -nc '{workspace:{current_dir:"/tmp"},rate_limits:{five_hour:{used_percentage:62.5}}}' | HOME=$TX XDG_CACHE_HOME=$TX/c ./statusline.sh | sed -n 2p | strip_ansi)
echo "$out" | grep -q '5h 63%' && ok "percentages rounded" || bad "percentages rounded (got: $out)"
off=$(date -u -r $((NOW + 7200 - 5*3600)) +%Y-%m-%dT%H:%M:%S.5-05:00 2>/dev/null || date -u -d @$((NOW + 7200 - 5*3600)) +%Y-%m-%dT%H:%M:%S.5-05:00)
out=$(jq -nc --arg r "$off" '{workspace:{current_dir:"/tmp"},rate_limits:{five_hour:{used_percentage:10,resets_at:$r}}}' | HOME=$TX XDG_CACHE_HOME=$TX/c ./statusline.sh | sed -n 2p | strip_ansi)
echo "$out" | grep -qE '⏰(1h59m|2h00m)' && ok "non-UTC ISO offset parsed" || bad "non-UTC ISO offset parsed (got: $out)"
out=$(jq -nc --arg r "$((NOW + 1800))" '{workspace:{current_dir:"/tmp"},rate_limits:{five_hour:{used_percentage:10,resets_at:$r}}}' | HOME=$TX XDG_CACHE_HOME=$TX/c ./statusline.sh | sed -n 2p | strip_ansi)
echo "$out" | grep -qE '⏰(29|30)m' && ok "epoch-as-string parsed" || bad "epoch-as-string parsed (got: $out)"
out=$(jq -nc --argjson r $((NOW + 17000)) '{workspace:{current_dir:"/tmp"},rate_limits:{five_hour:{used_percentage:99,resets_at:$r}}}' | HOME=$TX XDG_CACHE_HOME=$TX/c ./statusline.sh | sed -n 2p | strip_ansi)
echo "$out" | grep -q '→' && bad "no projection before 10% (99% used)" || ok "no projection before 10% (99% used)"
out=$(jq -nc --argjson r $((NOW + 16000)) '{workspace:{current_dir:"/tmp"},rate_limits:{five_hour:{used_percentage:99,resets_at:$r}}}' | HOME=$TX XDG_CACHE_HOME=$TX/c ./statusline.sh | sed -n 2p | strip_ansi)
echo "$out" | grep -qE '→(88[0-9]|89[0-9])%' && ok "steep pace projects past 100%" || bad "steep pace projects past 100% (got: $out)"
out=$(jq -nc --argjson r $((NOW + 4*86400)) '{workspace:{current_dir:"/tmp"},rate_limits:{seven_day:{used_percentage:30,resets_at:$r}}}' | HOME=$TX XDG_CACHE_HOME=$TX/c ./statusline.sh | sed -n 2p | strip_ansi)
echo "$out" | grep -qE '7d 30% ⏰(3d23h|4d0h) →(69|70)%' && ok "7d projection uses 7d window" || bad "7d projection uses 7d window (got: $out)"
printf '{"type":"user","message":{"content":"hi"}}\n' > "$TX/u.jsonl"
out=$(jq -nc --arg t "$TX/u.jsonl" '{session_id:"x-1",workspace:{current_dir:"/tmp"},transcript_path:$t}' | HOME=$TX XDG_CACHE_HOME=$TX/c ./statusline.sh 2>&1 | sed -n 2p | strip_ansi)
case "$out" in *cache*) bad "no assistant lines → no cache gauge (got: $out)";; *) ok "no assistant lines → no cache gauge";; esac
ts=$(date -u -r $((NOW - 60)) +%Y-%m-%dT%H:%M:%S.000Z 2>/dev/null || date -u -d @$((NOW - 60)) +%Y-%m-%dT%H:%M:%S.000Z)
python3 - "$TX/big.jsonl" "$ts" <<'PY'
import json, sys
with open(sys.argv[1], "w") as f:
    pad = json.dumps({"type": "assistant", "message": {"model": "x", "usage": {"input_tokens": 1}, "content": [{"type": "text", "text": "y" * 300000}]}})
    f.write(pad + "\n")
    f.write(json.dumps({"type": "assistant", "timestamp": sys.argv[2], "message": {"model": "x", "usage": {"input_tokens": 1, "cache_creation_input_tokens": 5, "cache_creation": {"ephemeral_5m_input_tokens": 5}}}}) + "\n")
PY
out=$(jq -nc --arg t "$TX/big.jsonl" '{session_id:"x-2",workspace:{current_dir:"/tmp"},transcript_path:$t}' | HOME=$TX XDG_CACHE_HOME=$TX/c ./statusline.sh | sed -n 2p | strip_ansi)
echo "$out" | grep -qE 'cache [34]m' && ok "truncated first tail line skipped" || bad "truncated first tail line skipped (got: $out)"
printf '%s' '{"oauthAccount":{"emailAddress":"sym@example.com"}}' > "$TX/.claude.json"
mkdir -p "$TX/c/fugu"; k=$(printf '%s' 'sym@example.com' | cksum | cut -d' ' -f1)
echo keep > "$TX/victim"; ln -s "$TX/victim" "$TX/c/fugu/usage-$k"
jq -nc '{workspace:{current_dir:"/tmp"},rate_limits:{five_hour:{used_percentage:5}}}' | HOME=$TX XDG_CACHE_HOME=$TX/c ./statusline.sh >/dev/null
chk "symlinked usage file not followed" "$(cat "$TX/victim")" "keep"
ln -s "$TX/victim" "$TX/c/fugu/win-x-3"
jq -nc '{session_id:"x-3",workspace:{current_dir:"/tmp"},context_window:{context_window_size:1000000}}' | HOME=$TX XDG_CACHE_HOME=$TX/c ./statusline.sh >/dev/null
chk "symlinked window file not followed" "$(cat "$TX/victim")" "keep"
out=$(echo '{"workspace":{"current_dir":"/tmp"}}' | HOME=$TX XDG_CACHE_HOME=$TX/c ANTHROPIC_API_KEY=sk-secret-1234 ./statusline.sh | head -1)
case "$out" in *'API key'*) case "$out" in *sk-secret*|*sym@*) bad "API key mode hides key and email";; *) ok "API key mode hides key and email";; esac;; *) bad "API key mode shown (got: $out)";; esac
# fugu-context: hostile transcript strings and string-typed numbers
mkdir -p "$TX/.claude/projects/-tmp-h"; HF="$TX/.claude/projects/-tmp-h/eeeeeeee-1111-2222-3333-444444444444.jsonl"
python3 - "$HF" <<'PY'
import json, sys
L = [{"type": "user", "cwd": "/tmp/\u001b]0;CWD\u0007", "message": {"content": "hi"}},
     {"type": "assistant", "timestamp": "2026-09-17T10:00:00Z", "message": {"id": "m1", "model": "\u001b]0;MODEL\u0007", "usage": {"input_tokens": "\u001b]0;USAGE\u0007", "cache_read_input_tokens": 5}}},
     {"type": "system", "subtype": "compact_boundary", "compactMetadata": {"trigger": "\u001b]0;TRIG\u0007", "preTokens": "\u001b]0;PRE\u0007"}}]
open(sys.argv[1], "w").write("".join(json.dumps(e) + "\n" for e in L))
PY
out=$(HOME=$TX node bin/fugu-context eeeeeeee-1111-2222-3333-444444444444 2>&1)
case "$out" in *$'\x1b]'*) bad "fugu-context strips transcript strings";; *) ok "fugu-context strips transcript strings";; esac
out=$(HOME=$TX node bin/fugu-sessions 2>&1); case "$out" in *$'\x1b]'*) bad "radar strips project path";; *) ok "radar strips project path";; esac
chk "radar cache is private" "$(stat -c %a "$TX/.fugu/sessions-cache.json" 2>/dev/null || stat -f %Lp "$TX/.fugu/sessions-cache.json")" "600"
chk "radar cache dir is private" "$(stat -c %a "$TX/.fugu" 2>/dev/null || stat -f %Lp "$TX/.fugu")" "700"
rm -rf "$TX"

echo "— accounts: discovery —"
TP=$(mktemp -d); mkdir -p "$TP/extra/one" "$TP/parent/two" "$TP/.aimux/profiles/work"
printf '{}' > "$TP/.claude.json"
for d in extra/one parent/two .aimux/profiles/work; do printf '{"oauthAccount":{"emailAddress":"%s@x.com"}}' "${d##*/}" > "$TP/$d/.claude.json"; done
J=$(HOME=$TP XDG_CACHE_HOME=$TP/c FUGU_PROFILE_DIRS="$TP/extra/one:$TP/parent" node bin/fugu-accounts --json)
chk "FUGU_PROFILE_DIRS: dir and parent-of-dirs" "$(echo "$J" | jq -r '[.[].profile] | sort | join(",")')" "default,one,two,work"
J=$(HOME=$TP XDG_CACHE_HOME=$TP/c CLAUDE_CONFIG_DIR="$TP/.aimux/profiles/work" node bin/fugu-accounts --json)
chk "CLAUDE_CONFIG_DIR marks active profile" "$(echo "$J" | jq -r '[.[] | select(.active) | .profile] | join(",")')" "work"
mkdir -p "$TP/.aimux/profiles/$(printf 'w\033]0;DIR\007')"; printf '{}' > "$TP/.aimux/profiles/$(printf 'w\033]0;DIR\007')/.claude.json"
out=$(HOME=$TP XDG_CACHE_HOME=$TP/c CLAUDE_CONFIG_DIR="$TP/extra/one" node bin/fugu-accounts 2>&1)
case "$out" in *$'\x1b]'*) bad "accounts strips profile dir";; *) ok "accounts strips profile dir";; esac
rm -rf "$TP"

echo "— responsive layout —"
TR=$(mktemp -d); NOW=$(date +%s)
printf '%s' '{"oauthAccount":{"emailAddress":"someone.long@example.com","organizationType":"claude_max"}}' > "$TR/.claude.json"
RJ=$(jq -nc --argjson r5 $((NOW+5400)) --argjson r7 $((NOW+3*86400)) --argjson pe $((NOW+3100)) '{model:{display_name:"Opus 5.5"},
  workspace:{current_dir:"/tmp"},context_window:{used_percentage:17},effort:{level:"high"},output_style:{name:"Explanatory"},cost:{total_cost_usd:4.12},
  rate_limits:{five_hour:{used_percentage:62,resets_at:$r5},seven_day:{used_percentage:41,resets_at:$r7}},prompt_cache:{expires_at:$pe,ttl:"1h"}}')
hudw() { echo "$RJ" | HOME=$TR XDG_CACHE_HOME=$TR/c COLUMNS=$1 ./statusline.sh | strip_ansi; }
cols() { python3 -c 'import sys,unicodedata
print(max(sum(0 if c=="️" else (2 if unicodedata.east_asian_width(c) in "WF" else 1) for c in l.rstrip("\n")) for l in sys.stdin))'; }
fit=1; for w in 30 40 50 60 70 80 100; do m=$(hudw $w | cols); [ "$m" -le $((w - 4)) ] || { fit=0; bad "fits COLUMNS=$w (widest line $m)"; }; done
[ "$fit" = 1 ] && ok "every line fits its width (30–100 cols)"
out=$(echo "$RJ" | HOME=$TR XDG_CACHE_HOME=$TR/c ./statusline.sh | strip_ansi)
case "$out" in *'Explanatory'*'(max)'*'→'*'$4.12'*) ok "no COLUMNS: nothing dropped";; *) bad "no COLUMNS: nothing dropped (got: $out)";; esac
out=$(hudw 60); case "$out" in *'→'*) bad "pace drops before meters (60 cols)";; *'5h 62%'*'7d 41%'*) ok "pace drops before meters (60 cols)";; *) bad "meters kept at 60 cols (got: $out)";; esac
out=$(hudw 30); case "$out" in *'5h 62%'*) ok "5h meter survives 30 cols";; *) bad "5h meter survives 30 cols (got: $out)";; esac
orphan=""; for w in 40 45 50 55; do out=$(hudw $w | head -1); case "$out" in *'(max)'*) case "$out" in *'👤'*) ;; *) orphan="$orphan $w";; esac;; esac; done
[ -z "$orphan" ] && ok "plan never shown without account" || bad "plan shown without account at:$orphan"
orphan=""; for w in 40 50 60; do out=$(hudw $w | sed -n 2p); case "$out" in *'⏰'*) case "$out" in *'5h 62% ⏰'*|*'7d 41% ⏰'*) ;; *) orphan="$orphan $w";; esac;; esac; done
[ -z "$orphan" ] && ok "reset never orphaned from its meter" || bad "reset orphaned at:$orphan"
out=$(FUGU_HUD_WIDTH=40 bash -c 'echo "$0" | HOME='"$TR"' XDG_CACHE_HOME='"$TR"'/c COLUMNS=200 ./statusline.sh' "$RJ" | strip_ansi | cols)
[ "$out" -le 36 ] && ok "FUGU_HUD_WIDTH overrides COLUMNS" || bad "FUGU_HUD_WIDTH overrides COLUMNS (widest $out)"
out=$(hudw 170 | sed -n 2p); echo "$out" | grep -qE 'cache 5[01]m' && ok "cache countdown from prompt_cache.expires_at" || bad "cache countdown from prompt_cache.expires_at (got: $out)"
out=$(jq -nc --argjson pe $((NOW-5)) '{workspace:{current_dir:"/tmp"},prompt_cache:{expires_at:$pe,ttl:"5m"}}' | HOME=$TR XDG_CACHE_HOME=$TR/c ./statusline.sh | sed -n 2p | strip_ansi)
echo "$out" | grep -q 'cache cold' && ok "expired prompt_cache shows cold" || bad "expired prompt_cache shows cold (got: $out)"
rm -rf "$TR"

echo "— hud install / launcher —"
TH=$(mktemp -d); mkdir -p "$TH/.claude"
hudcli() { HOME=$TH CLAUDE_CONFIG_DIR= node bin/fugu-hud "$@"; }
printf '%s' '{"permissions":{"allow":["Bash(ls)"]},"model":"opus"}' > "$TH/.claude/settings.json"
hudcli install >/dev/null
chk "install points settings at launcher" "$(jq -r .statusLine.command "$TH/.claude/settings.json")" "$TH/.fugu/bin/statusline"
chk "install keeps other keys" "$(jq -c '[.permissions.allow[0], .model]' "$TH/.claude/settings.json")" '["Bash(ls)","opus"]'
ls "$TH/.claude/"settings.json.bak.* >/dev/null 2>&1 && ok "install backs up settings" || bad "install backs up settings"
[ -x "$TH/.fugu/bin/statusline" ] && ok "launcher executable" || bad "launcher executable"
chk "root seeded to this copy" "$(cat "$TH/.fugu/root")" "$PWD"
out=$(echo '{"workspace":{"current_dir":"/tmp"}}' | HOME=$TH XDG_CACHE_HOME=$TH/c "$TH/.fugu/bin/statusline" | strip_ansi | head -1)
case "$out" in *'📁 tmp'*) ok "launcher renders the HUD";; *) bad "launcher renders the HUD (got: $out)";; esac
hudcli status >/dev/null; chk "status healthy → exit 0" "$?" "0"
# a plugin update moves the copy: the next session records it, the launcher follows
NEW="$TH/newcopy"; mkdir -p "$NEW"; printf '#!/bin/bash\ncat >/dev/null; echo NEWCOPY\n' > "$NEW/statusline.sh"
HOME=$TH CLAUDE_PLUGIN_ROOT=$NEW ./hooks/banner.sh >/dev/null
chk "session start records loaded copy" "$(cat "$TH/.fugu/root")" "$NEW"
chk "launcher follows the recorded copy" "$(echo '{}' | HOME=$TH "$TH/.fugu/bin/statusline")" "NEWCOPY"
mkdir -p "$TH/.fugu"; touch "$TH/.fugu/disabled"; NEW2="$TH/newer"; mkdir -p "$NEW2"; cp "$NEW/statusline.sh" "$NEW2/"
HOME=$TH CLAUDE_PLUGIN_ROOT=$NEW2 ./hooks/banner.sh >/dev/null; rm -f "$TH/.fugu/disabled"
chk "copy recorded even while muted" "$(cat "$TH/.fugu/root")" "$NEW2"
rm -rf "$NEW2"
chk "launcher falls back when recorded copy is gone" "$(echo '{"workspace":{"current_dir":"/tmp"}}' | HOME=$TH XDG_CACHE_HOME=$TH/c "$TH/.fugu/bin/statusline" | strip_ansi | head -1 | grep -c '📁 tmp')" "1"
HOME=$TH CLAUDE_PLUGIN_ROOT="$TH/nope" ./hooks/banner.sh >/dev/null
chk "bogus plugin root not recorded" "$(cat "$TH/.fugu/root")" "$NEW2"
# migration from a fixed-path install; foreign statusLine is refused
jq --arg c "$PWD/statusline.sh" '.statusLine = {type:"command",command:$c,refreshInterval:10}' "$TH/.claude/settings.json" > "$TH/x" && mv "$TH/x" "$TH/.claude/settings.json"
hudcli status >/dev/null; chk "status flags fixed-path install → exit 1" "$?" "1"
hudcli repair >/dev/null
chk "repair migrates to launcher, keeps refresh" "$(jq -c '[.statusLine.command == "'"$TH"'/.fugu/bin/statusline", .statusLine.refreshInterval]' "$TH/.claude/settings.json")" "[true,10]"
jq '.statusLine = {type:"command",command:"~/my-own-line.sh"}' "$TH/.claude/settings.json" > "$TH/x" && mv "$TH/x" "$TH/.claude/settings.json"
hudcli install >/dev/null 2>&1; chk "install refuses foreign statusLine" "$?" "1"
hudcli remove >/dev/null; chk "remove leaves foreign statusLine" "$(jq -r .statusLine.command "$TH/.claude/settings.json")" "~/my-own-line.sh"
jq 'del(.statusLine)' "$TH/.claude/settings.json" > "$TH/x" && mv "$TH/x" "$TH/.claude/settings.json"
hudcli install >/dev/null; hudcli remove >/dev/null
chk "remove drops fugu's statusLine" "$(jq -r '.statusLine // "none"' "$TH/.claude/settings.json")" "none"
[ -e "$TH/.fugu/bin/statusline" ] && bad "remove deletes launcher" || ok "remove deletes launcher"
printf '{not json' > "$TH/.claude/settings.json"
hudcli install >/dev/null 2>&1; chk "invalid settings refused" "$?" "1"
chk "invalid settings untouched" "$(cat "$TH/.claude/settings.json")" "{not json"
printf '{}' > "$TH/real.json"; rm -f "$TH/.claude/settings.json"; ln -s "$TH/real.json" "$TH/.claude/settings.json"
hudcli install >/dev/null
[ -L "$TH/.claude/settings.json" ] && [ "$(jq -r '.statusLine.command | length > 0' "$TH/real.json")" = true ] && ok "symlinked settings edited at target" || bad "symlinked settings edited at target"
rm -rf "$TH"

echo ""
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
