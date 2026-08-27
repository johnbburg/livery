#!/bin/bash
# Terminal tests: every color assertion reads the value back OFF the terminal.
# default_bg is pinned in the fixture config so these test livery's own logic and
# not gnome-terminal's inconsistently-reported default (see README limitations).
LIVERY_SH="${LIVERY_SH:-$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)/livery.sh}"
exec 4>"$1"; CONF="$2"
log(){ printf '%s\n' "$*" >&4; }
P=0; F=0
chk(){ if [[ "$2" == "$3" ]]; then P=$((P+1)); log "  ok   $1  ($3)"; else F=$((F+1)); log "  FAIL $1  got=$3 want=$2"; fi; }

export LIVERY_FORCE=1 LIVERY_CONF="$CONF" LIVERY_CACHE=$(mktemp -d)
source "$LIVERY_SH"

qosc(){ local n="$1" old r; exec 3<>/dev/tty; old=$(stty -g <&3); stty raw -echo <&3
  printf '\033]%s;?\033\\' "$n" >&3; IFS= read -r -d '\' -t 0.4 r <&3
  stty "$old" <&3; exec 3>&- 3<&-; printf '%s' "$r"; }
go(){ cd "$1" || return 1; _livery_hook; }

DEF="${_LIVERY_DEFAULT_BG:-}"
log "pinned default_bg = #$DEF"
chk "config default_bg honoured without querying" "300a24" "$DEF"

log "== negative control: the instrument can fail =="
chk "readback is not a color we never set" "0" "$([[ $(_livery_query_bg) == 123456 ]] && echo 1 || echo 0)"

log "== live query path still works (value may vary; must be valid) =="
lv=$(_livery_query_bg)
chk "query returns a 6-digit hex" "1" "$([[ $lv =~ ^[0-9a-f]{6}$ ]] && echo 1 || echo 0)"

log "== explicit rule, accent tint =="
go "$E/proj-a";  A_COL=$(_livery_blend "$DEF" 61afef 20)
chk "proj-a bg on terminal" "$A_COL" "$(_livery_query_bg)"

log "== longest-prefix override (subdir beats parent) =="
go "$E/proj-a/sub"
chk "sub rule wins, alpha=40" "$(_livery_blend "$DEF" 98c379 40)" "$(_livery_query_bg)"

log "== per-rule alpha, trailing comment tolerated =="
go "$E/proj-b";  B_COL=$(_livery_blend "$DEF" e06c75 30)
chk "proj-b alpha=30" "$B_COL" "$(_livery_query_bg)"

log "== full override (bg/fg/cursor verbatim) =="
go "$E/proj-loud"
chk "loud bg"     "3a0d0d" "$(_livery_query_bg)"
chk "loud fg"     "1" "$([[ $(qosc 10) == *ffff/d7d7/d7d7* ]] && echo 1 || echo 0)"
chk "loud cursor" "1" "$([[ $(qosc 12) == *ffff/5555/5555* ]] && echo 1 || echo 0)"

log "== REGRESSION: stale OSC 10 reply must not poison the bg query =="
printf '\033]10;?\033\\' >/dev/tty; sleep 0.2
chk "bg query skips the stale fg reply" "3a0d0d" "$(_livery_query_bg)"

log "== theme file: the ANSI palette really reaches the terminal (OSC 4) =="
go "$E/proj-theme"
chk "theme bg"      "0b0f14" "$(_livery_query_bg)"
chk "theme fg"      "1" "$([[ $(qosc 10) == *dfdf/e6e6/eeee* ]] && echo 1 || echo 0)"
chk "palette ansi1"  "ff9a9a" "$(_livery_query_color 4 1)"
chk "palette ansi4"  "79b8ff" "$(_livery_query_color 4 4)"
chk "palette ansi12" "a8d3ff" "$(_livery_query_color 4 12)"
untouched=$(_livery_query_color 4 2)
chk "an entry the theme omits is left alone" "1" "$([[ $untouched != ff9a9a && -n $untouched ]] && echo 1 || echo 0)"

log "== OSC 104 restores the palette =="
go "$HOME"
chk "ansi1 no longer the theme value" "0" "$([[ $(_livery_query_color 4 1) == ff9a9a ]] && echo 1 || echo 0)"
chk "ansi4 no longer the theme value" "0" "$([[ $(_livery_query_color 4 4) == 79b8ff ]] && echo 1 || echo 0)"

log "== leaving a project restores the profile's own colors =="
go "$HOME"
chk "bg left the project color"   "0" "$([[ $(_livery_query_bg) == 3a0d0d ]] && echo 1 || echo 0)"
chk "internal state cleared"      ""  "${_LIVERY_CUR_BG:-}"
chk "fg restored to profile"      "1" "$([[ $(qosc 10) == *ffff/ffff/ffff* ]] && echo 1 || echo 0)"
chk "cursor restored to profile"  "1" "$([[ $(qosc 12) == *ffff/ffff/ffff* ]] && echo 1 || echo 0)"

log "== auto mode for unlisted projects =="
go "$E/auto/alpha-proj"; A=$(_livery_query_bg)
chk "alpha-proj got a color" "1" "$([[ $A =~ ^[0-9a-f]{6}$ && $A != "$DEF" ]] && echo 1 || echo 0)"
go "$E/auto/beta-proj";  B=$(_livery_query_bg)
chk "beta-proj got a different color" "0" "$([[ $A == "$B" ]] && echo 1 || echo 0)"
go "$HOME"; go "$E/auto/alpha-proj"
chk "auto color stable for same name" "$A" "$(_livery_query_bg)"
mkdir -p "$E/auto/alpha-proj/deep/deeper"; go "$E/auto/alpha-proj/deep/deeper"
chk "nested dir inherits project color" "$A" "$(_livery_query_bg)"

log "== idempotency: hook twice in the same dir =="
go "$E/proj-a"; b4=$(_livery_query_bg); _livery_hook
chk "no change on repeat prompt" "$b4" "$(_livery_query_bg)"

log "== timing with production defaults =="
_LIVERY_O_fade_ms=260; _LIVERY_O_fade_steps=16
go "$HOME"; t0=$EPOCHREALTIME; go "$E/proj-b"; t1=$EPOCHREALTIME
ms=$(awk -v a=$t0 -v b=$t1 'BEGIN{printf "%d",(b-a)*1000}')
log "  fade wall-clock: ${ms}ms (target 260)"
chk "fade within 2x of target"    "1" "$([[ $ms -ge 200 && $ms -le 520 ]] && echo 1 || echo 0)"
chk "lands exactly on target"     "$B_COL" "$(_livery_query_bg)"

log "== livery off / on =="
livery off >/dev/null
chk "off leaves the project color" "0" "$([[ $(_livery_query_bg) == "$B_COL" ]] && echo 1 || echo 0)"
livery on  >/dev/null
chk "on restores the project color" "$B_COL" "$(_livery_query_bg)"

log "== unknown config keys are reported, not executed =="
bad=$(mktemp); printf 'set bogus_key 1\nnotadirective foo\n' >"$bad"
warn=$(LIVERY_CONF="$bad" bash -c "export LIVERY_FORCE=1; source '$LIVERY_SH'" 2>&1 >/dev/null)
chk "warns on unknown option"    "1" "$([[ $warn == *'unknown option "bogus_key"'* ]] && echo 1 || echo 0)"
chk "warns on unknown directive" "1" "$([[ $warn == *'unknown directive "notadirective"'* ]] && echo 1 || echo 0)"
rm -f "$bad"

log "== status / test output formatting =="
go "$E/proj-b"; st=$(livery status 2>&1)
chk "status: default is one color"  "1" "$([[ $(grep -c '^default  : #[0-9a-f]\{6\}$' <<<"$st") == 1 ]] && echo 1 || echo 0)"
chk "status: current is one color"  "1" "$([[ $(grep -c '^current  : #[0-9a-f]\{6\}$' <<<"$st") == 1 ]] && echo 1 || echo 0)"
tt=$(livery test "$E/proj-loud" 2>&1)
chk "test: fg rendered once"     "1" "$([[ $tt == *'fg=#ffd7d7'* ]] && echo 1 || echo 0)"
chk "test: cursor rendered once" "1" "$([[ $tt == *'cursor=#ff5555'* ]] && echo 1 || echo 0)"

log "== REGRESSION: project->project must not re-init (would flash to default) =="
rm -f "$LIVERY_CACHE/default_bg"
_LIVERY_INIT_CALLS=0
_livery_init_default_bg(){ _LIVERY_INIT_CALLS=$((_LIVERY_INIT_CALLS+1)); return 1; }
go "$E/proj-a"; go "$E/proj-b"; go "$E/proj-a"
chk "init never re-entered mid-session" "0" "$_LIVERY_INIT_CALLS"
chk "colors correct after 3 hops" "$A_COL" "$(_livery_query_bg)"

log "== re-source does not double-install the hook =="
n1=$(grep -o _livery_hook <<<"$PROMPT_COMMAND" | wc -l)
source "$LIVERY_SH"
chk "hook count unchanged" "$n1" "$(grep -o _livery_hook <<<"$PROMPT_COMMAND" | wc -l)"

livery reset >/dev/null
log ""; log "pass=$P fail=$F"
rm -rf "$LIVERY_CACHE"
