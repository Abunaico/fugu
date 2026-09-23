#!/bin/bash
# fugu HUD — Claude Code statusline
# stdin: session JSON. Two lines out: identity, gauges.
# Render path never blocks: git status is served from cache and refreshed
# by a detached background job — a hung SMB mount can never stall the HUD.
# Meme dial: FUGU_MOOD=off deflates the fish. At 90% context the toxin comes out.

input=$(cat)
# /fugu:off drops this marker; always drain stdin first so the pipe never stalls.
[ -f "$HOME/.fugu/disabled" ] && exit 0
echo "$input" | jq -e . >/dev/null 2>&1 || input='{}'

# Per-feature switches (/fugu:settings): `key=off` lines in ~/.fugu/config.
# Parsed in pure bash so a render costs no extra process.
FUGU_OFF=" "
if [ -f "$HOME/.fugu/config" ]; then
  while IFS='=' read -r k v || [ -n "$k" ]; do
    k=${k//[[:space:]]/}; v=${v//[[:space:]]/}
    [ "$v" = off ] && FUGU_OFF="$FUGU_OFF$k "
  done < "$HOME/.fugu/config"
fi
[ "$FUGU_MOOD" = "off" ] && FUGU_OFF="${FUGU_OFF}hud.fish "
feat() { case "$FUGU_OFF" in *" $1 "*) return 1;; esac; }

RED=$'\033[31m'; GRN=$'\033[32m'; YLW=$'\033[33m'; CYN=$'\033[36m'
MAG=$'\033[35m'; DIM=$'\033[2m'; RST=$'\033[0m'; BOLD=$'\033[1m'

strip_ctrl() { tr -d '\000-\037\177'; }

# File mtime in epoch secs. GNU first: on Linux `stat -f` is a real flag
# (filesystem info) that prints junk before failing; BSD rejects -c cleanly.
mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0; }

# One jq pass for every field. Every value is stripped of C0/C1 controls (ESC,
# CSI, OSC, CR, LF, and the 0x1f separator) before it can reach the terminal.
# resets_at arrives as ISO text (any offset) or epoch; normalized to epoch secs.
IFS=$'\x1f' read -r model cwd used upct size cost h5 h5r d7 d7r sid effort style tpath pc_exp pc_ttl < <(
  echo "$input" | jq -r '
    def ep:
      if . == null or . == "" then ""
      elif type == "number" then (if . > 1e12 then . / 1000 else . end | floor)
      elif (tostring | test("^[0-9]+(\\.[0-9]+)?$")) then (tostring | tonumber | ep)
      else ((tostring | capture("^(?<d>[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2})(\\.[0-9]+)?(?<z>Z|[+-][0-9]{2}:?[0-9]{2})?$")
             | ((.d + "Z") | fromdateiso8601)
               - (if (.z // "Z") == "Z" then 0 else (.z | capture("(?<s>[+-])(?<h>[0-9]{2}):?(?<m>[0-9]{2})")
                   | ((.h | tonumber) * 3600 + (.m | tonumber) * 60) * (if .s == "-" then -1 else 1 end)) end)) // "")
      end;
    def pctnum: if type == "number" then (. + 0.5 | floor) else (. // "") end;
    [
    (.model.display_name // "Claude"),
    (.workspace.current_dir // .cwd // ""),
    (.context_window.used_tokens // .context_window.total_tokens_used
      // (.context_window.current_usage | if type == "object"
           then (.input_tokens // 0) + (.cache_read_input_tokens // 0) + (.cache_creation_input_tokens // 0)
           else null end) // 0),
    (.context_window.used_percentage | pctnum),
    (.context_window.context_window_size // ""),
    (.cost.total_cost_usd // ""),
    (.rate_limits.five_hour.used_percentage | pctnum),
    (.rate_limits.five_hour.resets_at | ep),
    (.rate_limits.seven_day.used_percentage | pctnum),
    (.rate_limits.seven_day.resets_at | ep),
    (.session_id // ""),
    (.effort.level // ""),
    (.output_style.name // ""),
    (.transcript_path // ""),
    (.prompt_cache.expires_at | ep),
    (.prompt_cache.ttl // "")
  ] | map(tostring | gsub("\\p{Cc}"; " ")) | join("\u001f")' 2>/dev/null
)

model=${model:-Claude}
case "$used" in ''|*[!0-9]*) used=0;; esac
case "$upct" in ''|*[!0-9]*) upct="";; esac
case "$h5r" in *[!0-9]*) h5r="";; esac
case "$d7r" in *[!0-9]*) d7r="";; esac
case "$pc_exp" in *[!0-9]*) pc_exp="";; esac
sid=${sid//[!A-Za-z0-9-]/}
now=$(date +%s)

# All cache writes are skipped unless we own a real (non-symlink) cache dir, so a
# shared or pre-planted XDG_CACHE_HOME can't be used to redirect them.
cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/fugu"
mkdir -p "$cache_dir" 2>/dev/null && chmod 700 "$cache_dir" 2>/dev/null
cache_ok=""; [ -d "$cache_dir" ] && [ ! -L "$cache_dir" ] && [ -O "$cache_dir" ] && cache_ok=1

dur() { # secs → 43m / 1h28m / 2d4h
  local s=$1
  if   [ "$s" -lt 60 ];    then printf '<1m'
  elif [ "$s" -lt 3600 ];  then printf '%dm' $(( s / 60 ))
  elif [ "$s" -lt 86400 ]; then printf '%dh%02dm' $(( s / 3600 )) $(( s % 3600 / 60 ))
  else printf '%dd%dh' $(( s / 86400 )) $(( s % 86400 / 3600 )); fi
}

# Record the true window size for fugu-context (transcripts don't carry it).
# One tiny write only when the value changes. Only a size Claude Code actually
# reported is recorded, never the fallback.
case "$size" in ''|*[!0-9]*) size="";; esac
if [ -n "$cache_ok" ] && [ -n "$sid" ] && [ -n "$size" ]; then
  wfile="$cache_dir/win-$sid"
  if [ "$(cat "$wfile" 2>/dev/null)" != "$size" ]; then
    [ ! -L "$wfile" ] && printf '%s' "$size" > "$wfile" 2>/dev/null
  fi
fi
[ -z "$size" ] && size=200000
case "$cost" in *[!0-9.]*|'') cost="";; esac

dir="?"
if [ -n "$cwd" ]; then
  dir="${cwd/#$HOME/~}"; dir="${dir##*/}"; [ -z "$dir" ] && dir="/"
fi

# --- git: cached, never inline (SMB mounts here can hang in D-state) ---
git_seg=""
if [ -n "$cwd" ] && [ -n "$cache_ok" ] && feat hud.git; then
  cache="$cache_dir/git-$(printf '%s' "$cwd" | cksum | cut -d' ' -f1)"
  [ -L "$cache" ] && rm -f "$cache"

  age=999
  [ -f "$cache" ] && age=$(( now - $(mtime "$cache") ))
  if [ "$age" -gt 5 ]; then
    # Refresh out of band; this render serves whatever the cache last held.
    # Single-flight lock: a hung mount pins ONE subshell, not one per render.
    lock="$cache.lock"
    if mkdir "$lock" 2>/dev/null; then
      (
        tmp=""
        trap 'rm -f "$tmp" 2>/dev/null; rmdir "$lock" 2>/dev/null' EXIT
        tmp=$(mktemp "$cache_dir/.git-XXXXXX") || exit
        if branch=$(cd "$cwd" 2>/dev/null && git branch --show-current 2>/dev/null) && [ -n "$branch" ]; then
          # Branch names come from the repo (a clone controls them): drop UTF-8 C1
          # controls as well as C0 before they are cached for rendering.
          branch=$(printf '%s' "$branch" | LC_ALL=C sed $'s/\xc2[\x80-\x9f]//g' | tr -d '\000-\037\177')
          if [ -n "$(cd "$cwd" && git status --porcelain 2>/dev/null | head -1)" ]; then m="✗"; else m="✔"; fi
          printf '%s %s' "$branch" "$m" > "$tmp"
        else
          : > "$tmp"
        fi
        mv -f "$tmp" "$cache" && tmp=""
      ) >/dev/null 2>&1 &
      disown 2>/dev/null
    else
      # Reap a stale lock (killed subshell or reboot mid-refresh) after 120s.
      lockage=$(( now - $(mtime "$lock") ))
      [ "$lockage" -gt 120 ] && rmdir "$lock" 2>/dev/null
    fi
  fi
  gitinfo=""
  [ -f "$cache" ] && gitinfo=$(LC_ALL=C sed $'s/\xc2[\x80-\x9f]//g' "$cache" | strip_ctrl)
  [ -n "$gitinfo" ] && git_seg=" ${DIM}·${RST} ${MAG}${gitinfo}${RST}"
fi

# --- account: which login this session bills to ---
# CLAUDE_CONFIG_DIR is inherited from the claude process, so profile launches
# (CLAUDE_CONFIG_DIR=... claude) show their own login. An API key in env overrides OAuth.
acct_seg=""; acct=""; acct_email=""; acct_plan=""
if [ -n "$ANTHROPIC_API_KEY" ]; then
  acct="API key"
else
  IFS=$'\x1f' read -r acct_email acct_plan < <(jq -r '.oauthAccount | select(.emailAddress)
    | [.emailAddress, (.organizationType // "" | sub("^claude_"; ""))]
    | map(tostring | gsub("\\p{Cc}"; " ")) | join("\u001f")' \
    "${CLAUDE_CONFIG_DIR:-$HOME}/.claude.json" 2>/dev/null | head -1)
  acct="$acct_email${acct_plan:+ ($acct_plan)}"
fi
acct_plan_seg=""
if [ -n "$acct" ] && feat hud.account; then
  if [ -n "$acct_email" ]; then
    acct_seg=" ${DIM}·${RST} 👤 ${acct_email}"
    [ -n "$acct_plan" ] && acct_plan_seg=" (${acct_plan})"
  else
    acct_seg=" ${DIM}·${RST} 👤 ${acct}"
  fi
fi

# Last-seen rate limits per account, for fugu-accounts. Written at most once a
# minute (or when a number moves), so the render path stays one stat() per frame.
if [ -n "$cache_ok" ] && [ -n "$acct_email" ] && { [ -n "$h5" ] || [ -n "$d7" ]; }; then
  ufile="$cache_dir/usage-$(printf '%s' "$acct_email" | cksum | cut -d' ' -f1)"
  vals="$h5|$h5r|$d7|$d7r"
  uage=999
  [ -f "$ufile" ] && uage=$(( now - $(mtime "$ufile") ))
  if [ ! -L "$ufile" ] && { [ "$uage" -gt 60 ] || ! grep -qF "\"v\":\"$vals\"" "$ufile" 2>/dev/null; }; then
    utmp=$(mktemp "$cache_dir/.usage-XXXXXX" 2>/dev/null) && {
      jq -nc --arg e "$acct_email" --arg p "$acct_plan" --arg v "$vals" --argjson at "$now" \
        '{email: $e, plan: $p, v: $v, at: $at}' > "$utmp" 2>/dev/null && mv -f "$utmp" "$ufile" || rm -f "$utmp"
    }
  fi
fi

# --- prompt cache: time until it goes cold ---
# Only the transcript's tail is read, so cost stays flat as sessions grow. Cache
# hits refresh the TTL; the TTL tier (5m or 1h) comes from the last cache write.
cache_seg=""
cache_left=""; cache_tier=""
if feat hud.cache && [ -n "$pc_exp" ]; then
  # Newer Claude Code sends prompt_cache.{expires_at,ttl} directly.
  case "$pc_ttl" in 1h) cache_tier=3600;; 5m) cache_tier=300;; *[!0-9]*|'') cache_tier=300;; *) cache_tier=$pc_ttl;; esac
  cache_left=$(( pc_exp - now ))
elif [ -n "$tpath" ] && [ -f "$tpath" ] && feat hud.cache; then
  IFS=$'\x1f' read -r last_ts tier < <(tail -c 262144 "$tpath" 2>/dev/null | grep -E '"type": ?"assistant"' | jq -R -r -s '
    [split("\n")[] | fromjson? | select(.message.usage? and .message.model != "<synthetic>")] as $a
    | if ($a | length) == 0 then "" else
      [ ($a[-1].timestamp // "" | sub("\\.[0-9]+"; "") | (try fromdateiso8601 catch "")),
        ([$a[] | select((.message.usage.cache_creation_input_tokens // 0) > 0)]
          | if length == 0 then "" elif (.[-1].message.usage.cache_creation.ephemeral_1h_input_tokens // 0) > 0 then "3600" else "300" end)
      ] | map(tostring) | join("\u001f") end' 2>/dev/null)
  tfile="$cache_dir/ttl-$sid"
  if [ -n "$tier" ] && [ -n "$sid" ] && [ -n "$cache_ok" ]; then
    [ "$(cat "$tfile" 2>/dev/null)" != "$tier" ] && [ ! -L "$tfile" ] && printf '%s' "$tier" > "$tfile" 2>/dev/null
  elif [ -n "$sid" ]; then
    tier=$(cat "$tfile" 2>/dev/null)
  fi
  case "$tier" in 300|3600) ;; *) tier=300;; esac
  case "$last_ts" in ''|*[!0-9]*) ;; *) cache_tier=$tier; cache_left=$(( last_ts + tier - now ));; esac
fi
if [ -n "$cache_left" ]; then
  if [ "$cache_left" -gt 0 ]; then
    cc="$GRN"; [ "$cache_left" -lt $(( cache_tier / 4 )) ] && cc="$YLW"
    cache_seg=" ${DIM}cache${RST} ${cc}$(dur "$cache_left")${RST}"
  else
    cache_seg=" ${DIM}cache${RST} ${RED}cold${RST}"
  fi
fi

# --- context bar ---
pct=0
if [ -n "$upct" ]; then pct=$upct
elif [ "$size" -gt 0 ]; then pct=$(( used * 100 / size )); fi
[ "$pct" -gt 100 ] && pct=100
if   [ "$pct" -ge 90 ]; then bc="$RED"
elif [ "$pct" -ge 70 ]; then bc="$YLW"
else bc="$GRN"; fi
filled=$(( pct / 10 )); bar=""
for i in 1 2 3 4 5 6 7 8 9 10; do
  if [ "$i" -le "$filled" ]; then bar="${bar}█"; else bar="${bar}░"; fi
done

# --- rate meters ---
rl=""
# Sets M_pct / M_reset / M_pace (colored) for one window; empty when not shown.
meter() { # pct label reset_epoch window_secs
  local p=$1 lbl=$2 reset=$3 win=$4 c="$GRN"
  M_pct=""; M_reset=""; M_pace=""
  case "$p" in ''|*[!0-9]*) return;; esac
  [ "$p" -ge 60 ] && c="$YLW"; [ "$p" -ge 85 ] && c="$RED"
  M_pct=" ${DIM}${lbl}${RST} ${c}${p}%${RST}"
  if [ -n "$reset" ] && [ "$reset" -gt "$now" ]; then
    local left=$(( reset - now )) elapsed
    feat hud.reset && M_reset=" ${DIM}⏰$(dur "$left")${RST}"
    # Linear pace to end of window; skipped in the first 10% where it's noise.
    elapsed=$(( win - left ))
    if feat hud.pace && [ "$p" -gt 0 ] && [ "$elapsed" -gt $(( win / 10 )) ]; then
      local proj=$(( p * win / elapsed )) pc="$DIM"
      [ "$proj" -gt 999 ] && proj=999
      [ "$proj" -ge 85 ] && pc="$YLW"; [ "$proj" -ge 100 ] && pc="$RED"
      [ "$proj" -ge $(( p + 5 )) ] && M_pace=" ${pc}→${proj}%${RST}"
    fi
  fi
}
h5_pct=""; h5_reset=""; h5_pace=""; d7_pct=""; d7_reset=""; d7_pace=""
if feat hud.rate; then
  meter "$h5" 5h "$h5r" 18000;  h5_pct=$M_pct; h5_reset=$M_reset; h5_pace=$M_pace
  meter "$d7" 7d "$d7r" 604800; d7_pct=$M_pct; d7_reset=$M_reset; d7_pace=$M_pace
fi

cost_seg=""
[ -n "$cost" ] && feat hud.cost && cost_seg=" ${DIM}·${RST} ${YLW}\$$(printf '%.2f' "$cost" 2>/dev/null)${RST}"

# --- session mode: effort level, output style (default style stays quiet) ---
mode_seg=""; mode_short=""
if feat hud.mode; then
  mode=""
  [ -n "$effort" ] && mode="$effort"
  [ -n "$style" ] && [ "$style" != "default" ] && mode="${mode:+$mode · }$style"
  [ -n "$mode" ] && mode_seg=" ${DIM}[${mode}]${RST}"
  # Narrow terminals keep just the effort level.
  [ -n "$effort" ] && [ "$mode" != "$effort" ] && mode_short=" ${DIM}[${effort}]${RST}"
fi

# --- mood ---
claw=""
if feat hud.fish; then
  claw="🐡 "
  [ "$pct" -ge 90 ] && claw="🐡☠️ "
fi

# --- layout: fit each line to the terminal width ---
# Claude Code passes COLUMNS and truncates anything wider, which would cut the
# most important gauges off the end. Instead, segments are dropped (or swapped
# for a shorter form) lowest-priority first until the line fits. Priority 99
# never drops. Order of the arrays is display order.
W=${FUGU_HUD_WIDTH:-${COLUMNS:-0}}
case "$W" in ''|*[!0-9]*) W=0;; esac
budget=$(( W - 4 ))

# Visible width: strip our own color codes, then count characters; wide emoji
# take two columns. Character counting needs a UTF-8 locale.
t='🐡'
if [ "${#t}" -ne 1 ]; then
  for loc in C.UTF-8 en_US.UTF-8 C.utf8; do LC_ALL=$loc; t='🐡'; [ "${#t}" -eq 1 ] && break; done 2>/dev/null
fi
vw() {
  local s=$1 e c
  for c in "$RED" "$GRN" "$YLW" "$CYN" "$MAG" "$DIM" "$RST" "$BOLD"; do s=${s//"$c"/}; done
  # One literal pass per emoji: bash 3.2 (macOS /bin/bash) matches [..] brackets
  # byte-wise, which would also eat █ and → (they share a UTF-8 lead byte).
  e=${s//🐡/}; e=${e//📁/}; e=${e//👤/}; e=${e//⏰/}
  VW=$(( ${#s} + ${#s} - ${#e} ))
}

render() { # fits SEG / PRI / ALT / DEP (global arrays), prints one line
  local n=${#SEG[@]} i total min mi best bi p
  local orig=("${SEG[@]}") alt=("${ALT[@]}")
  if [ "$budget" -gt 0 ]; then
    # Drop (or shorten) the lowest-priority segment until the line fits.
    while :; do
      total=0
      for (( i = 0; i < n; i++ )); do [ -n "${SEG[i]}" ] && { vw "${SEG[i]}"; total=$(( total + VW )); }; done
      [ "$total" -le "$budget" ] && break
      min=99; mi=-1
      for (( i = 0; i < n; i++ )); do
        [ -n "${SEG[i]}" ] && [ "${PRI[i]}" -lt "$min" ] && { min=${PRI[i]}; mi=$i; }
      done
      [ "$mi" -lt 0 ] && break
      if [ -n "${ALT[mi]}" ]; then SEG[mi]=${ALT[mi]}; ALT[mi]=""; else SEG[mi]=""; fi
    done
    # Dropping one long segment can free room for a shorter one dropped earlier:
    # put segments back, highest priority first, in full or short form.
    for (( p = 98; p > 0; p-- )); do
      for (( i = 0; i < n; i++ )); do
        [ "${PRI[i]}" -eq "$p" ] && [ -z "${SEG[i]}" ] && [ -n "${orig[i]}" ] || continue
        [ -n "${DEP[i]}" ] && [ -z "${SEG[${DEP[i]}]}" ] && continue
        for cand in "${orig[i]}" "${alt[i]}"; do
          [ -n "$cand" ] || continue
          vw "$cand"; [ $(( total + VW )) -le "$budget" ] && { SEG[i]=$cand; total=$(( total + VW )); break; }
        done
      done
    done
  fi
  # A segment that qualifies another (the plan after the email) goes with it.
  for (( i = 0; i < n; i++ )); do [ -n "${DEP[i]}" ] && [ -z "${SEG[${DEP[i]}]}" ] && SEG[i]=""; done
  local out=""
  for (( i = 0; i < n; i++ )); do out="$out${SEG[i]}"; done
  printf '%s\n' "$out"
}

# SEG: segment · PRI: priority (99 never drops) · ALT: shorter form · DEP: index
# of the segment it qualifies (shown only alongside it)
SEG=( "$claw$BOLD$CYN$model$RST"  "$mode_seg"   " ${DIM}·${RST} 📁 $dir"  "$git_seg"  "$acct_seg"  "$acct_plan_seg" )
PRI=( 99                          3             98                        5           6            4 )
ALT=( ""                          "$mode_short" ""                        ""          ""           "" )
DEP=( ""                          ""            ""                        ""          ""           4 )
render

bar_seg="$bc$bar$RST "
SEG=( "$bar_seg" "$pct%" "$h5_pct" "$h5_reset" "$h5_pace" "$d7_pct" "$d7_reset" "$d7_pace" "$cache_seg" "$cost_seg" )
PRI=( 13         99      50        12          10         40        11          9          20           15 )
ALT=( ""         ""      ""        ""          ""         ""        ""          ""         ""           "" )
DEP=( ""         ""      ""        2           2          ""        5           5          ""           "" )
render
