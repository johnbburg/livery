#!/bin/bash
# Unit tests: pure color math, no terminal required.
LIVERY_SH="${LIVERY_SH:-$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)/livery.sh}"
export LIVERY_FORCE=1
export LIVERY_CONF=/nonexistent-on-purpose
# Hermetic: without this, sourcing livery.sh loads whatever profile palette this
# machine has cached, and the repair tests would assert against local state.
export LIVERY_CACHE=$(mktemp -d)
trap 'rm -rf "$LIVERY_CACHE"' EXIT
source ${LIVERY_SH}
pass=0; fail=0
t() { # t <desc> <expected> <actual>
  if [[ "$2" == "$3" ]]; then pass=$((pass+1)); printf '  ok   %-42s %s\n' "$1" "$3"
  else fail=$((fail+1)); printf '  FAIL %-42s got=%s want=%s\n' "$1" "$3" "$2"; fi
}
echo "== _livery_hex =="
t "6-digit passthrough"  "1a2b3c" "$(_livery_hex '#1A2B3C')"
t "no-hash form"         "1a2b3c" "$(_livery_hex '1a2b3c')"
t "3-digit expand"       "1122ee" "$(_livery_hex '#12e')"
t "invalid rejected"     ""       "$(_livery_hex '#zzz' 2>/dev/null)"
t "wrong length"         ""       "$(_livery_hex '#12345' 2>/dev/null)"

echo "== _livery_rgb =="
t "black" "0 0 0"       "$(_livery_rgb '#000000')"
t "white" "255 255 255" "$(_livery_rgb '#ffffff')"
t "mixed" "48 10 36"    "$(_livery_rgb '#300a24')"

echo "== _livery_blend (base #300a24) =="
t "alpha 0   = base"    "300a24" "$(_livery_blend 300a24 61afef 0)"
t "alpha 100 = accent"  "61afef" "$(_livery_blend 300a24 61afef 100)"
t "alpha 18  tint"      "392849" "$(_livery_blend 300a24 61afef 18)"
t "alpha 50  midpoint"  "495d8a" "$(_livery_blend 300a24 61afef 50)"

echo "== _livery_lerp (rounding + endpoints) =="
t "step n lands on target (up)"   "61afef" "$(_livery_lerp 300a24 61afef 16 16)"
t "step n lands on target (down)" "300a24" "$(_livery_lerp 61afef 300a24 16 16)"
t "step 0 is source"              "300a24" "$(_livery_lerp 300a24 61afef 0 16)"
t "no-op from==to"                "300a24" "$(_livery_lerp 300a24 300a24 8 16)"
t "midpoint"                      "495d8a" "$(_livery_lerp 300a24 61afef 8 16)"

echo "== monotonic fade (no overshoot/backtrack) =="
prev=-1; bad=0
for s in $(seq 0 16); do
  v=$(_livery_lerp 300a24 61afef "$s" 16); r=$((16#${v:0:2}))
  (( r < prev )) && bad=1; prev=$r
done
t "red channel monotonic 48->97" "0" "$bad"

echo "== _livery_msleep (pure-bash, ~200ms) =="
t0=$EPOCHREALTIME; _livery_msleep 200; t1=$EPOCHREALTIME
el=$(awk -v a="$t0" -v b="$t1" 'BEGIN{printf "%d", (b-a)*1000}')
if (( el >= 180 && el <= 320 )); then pass=$((pass+1)); printf '  ok   %-42s %sms\n' "slept ~200ms" "$el"
else fail=$((fail+1)); printf '  FAIL %-42s %sms\n' "slept ~200ms" "$el"; fi

echo "== per-rule alpha (tint mode) =="
# alpha must be accepted as a rule key and beat the global value; it was
# silently rejected as "unknown rule key" while tint used the global alpha.
_cfg=$(mktemp); _dir=$(mktemp -d)
printf 'set default_bg #300a24\nset mode tint\nset alpha 20\nset auto off\nrule %s accent=#98c379 alpha=40\n' "$_dir" > "$_cfg"
LIVERY_CONF="$_cfg" _livery_load_conf 2>/dev/null
warn=$(LIVERY_CONF="$_cfg" _livery_load_conf 2>&1 >/dev/null)
t "alpha is not rejected as unknown" "" "$warn"
_livery_resolve "$_dir" >/dev/null 2>&1
t "per-rule alpha=40 beats global 20" "$(_livery_blend 300a24 98c379 40)" "${_LIVERY_T[bg]}"
printf 'set default_bg #300a24\nset mode tint\nset alpha 20\nset auto off\nrule %s accent=#98c379 alpha=200\n' "$_dir" > "$_cfg"
LIVERY_CONF="$_cfg" _livery_load_conf 2>/dev/null
_livery_resolve "$_dir" >/dev/null 2>&1
t "alpha>100 is clamped, not left invalid" "$(_livery_blend 300a24 98c379 100)" "${_LIVERY_T[bg]}"
t "clamped alpha yields a valid 6-digit colour" "6" "${#_LIVERY_T[bg]}"
rm -rf "$_cfg" "$_dir"

echo "== auto-project contrast repair =="
# An auto project takes a derived background but keeps the terminal profile's
# palette, and the stock Ubuntu palette's bright blue #2a7bde measures 2.51:1 on
# one. The repair has to fix that without re-theming: same hue, least movement.
#
# The subject here is ansi12 rather than ansi4 because the two are solved by
# different rules. ansi12 is text-only, so it has one floor and the least-
# movement search applies. ansi4 is in _LIVERY_ON_COLOR_SLOTS -- programs paint
# it as a background too -- so it is two-sided and covered separately below.
_p_reset() { unset _LIVERY_P; declare -A -g _LIVERY_P; }
_p_set()   { local kv; for kv in "$@"; do _LIVERY_P[${kv%%:*}]=${kv#*:}; done; }
_repaired() { _livery_repair_palette "$1" "$2" | awk -v k="$3" '$1==k{print $2}'; }

_DARKBG=244714          # an auto background: hue 100 at auto_lightness 18
_LIGHTBG=e8f0d8         # the same repair on a light background must darken

_p_reset; _p_set fg:ffffff ansi12:2a7bde ansi7:d0cfcc ansi0:171421 ansi8:5e5c64

# 1. a slot that already clears the floor is left alone -- that is what keeps an
#    auto project visibly different from a configured one
t "slot above the floor is not repaired" "" "$(_repaired $_DARKBG 450 ansi7)"
t "fg above the floor is not repaired"   "" "$(_repaired $_DARKBG 450 fg)"

# 2. the contract: whatever comes back must clear the floor when measured by the
#    independent bash implementation, not just by the awk that produced it
_r4=$(_repaired $_DARKBG 450 ansi12)
t "unreadable slot is repaired"          "6" "${#_r4}"
_c4=$(_livery_contrast "$_r4" $_DARKBG)
if (( ${_c4:-0} >= 450 )); then pass=$((pass+1)); printf '  ok   %-42s %s\n' "repaired slot clears the floor" "$_c4"
else fail=$((fail+1)); printf '  FAIL %-42s %s < 450\n' "repaired slot clears the floor" "$_c4"; fi
# and the original did not, or there was nothing to prove
_c4o=$(_livery_contrast 2a7bde $_DARKBG)
if (( _c4o < 450 )); then pass=$((pass+1)); printf '  ok   %-42s %s\n' "the original was below the floor" "$_c4o"
else fail=$((fail+1)); printf '  FAIL %-42s %s\n' "the original was below the floor" "$_c4o"; fi

# 3. hue is kept: this lightens the profile's own colour, it does not pick a new one
read -r _h0 _ _l0 <<<"$(_livery_rgb_to_hsl 2a7bde)"
read -r _h1 _ _l1 <<<"$(_livery_rgb_to_hsl "$_r4")"
_dh=$(( _h1 > _h0 ? _h1 - _h0 : _h0 - _h1 ))
if (( _dh <= 2 )); then pass=$((pass+1)); printf '  ok   %-42s %s vs %s\n' "hue preserved within rounding" "$_h1" "$_h0"
else fail=$((fail+1)); printf '  FAIL %-42s %s vs %s\n' "hue preserved within rounding" "$_h1" "$_h0"; fi

# 4. direction follows the background, not a hardcoded "lighten"
if (( _l1 > _l0 )); then pass=$((pass+1)); printf '  ok   %-42s L %s -> %s\n' "dark bg lightens the slot" "$_l0" "$_l1"
else fail=$((fail+1)); printf '  FAIL %-42s L %s -> %s\n' "dark bg lightens the slot" "$_l0" "$_l1"; fi
_p_reset; _p_set ansi2:26a269
_r2=$(_repaired $_LIGHTBG 450 ansi2)
read -r _ _ _l2a <<<"$(_livery_rgb_to_hsl 26a269)"
read -r _ _ _l2b <<<"$(_livery_rgb_to_hsl "$_r2")"
if (( _l2b < _l2a )); then pass=$((pass+1)); printf '  ok   %-42s L %s -> %s\n' "light bg darkens the slot" "$_l2a" "$_l2b"
else fail=$((fail+1)); printf '  FAIL %-42s L %s -> %s\n' "light bg darkens the slot" "$_l2a" "$_l2b"; fi
_c2=$(_livery_contrast "$_r2" $_LIGHTBG)
if (( ${_c2:-0} >= 450 )); then pass=$((pass+1)); printf '  ok   %-42s %s\n' "darkened slot clears the floor" "$_c2"
else fail=$((fail+1)); printf '  FAIL %-42s %s < 450\n' "darkened slot clears the floor" "$_c2"; fi

# 5. ansi0/ansi8 are dim text and box drawing. `livery test` exempts them from
#    the threshold, so repairing them would contradict what it reports.
_p_reset; _p_set ansi0:171421 ansi8:5e5c64 ansi12:2a7bde
_out=$(_livery_repair_palette $_DARKBG 450)
t "ansi0 is never repaired" "" "$(printf '%s\n' "$_out" | awk '$1=="ansi0"{print $1}')"
t "ansi8 is never repaired" "" "$(printf '%s\n' "$_out" | awk '$1=="ansi8"{print $1}')"

# 6. no snapshot means no repair -- and must not invent colours
_p_reset
_out=$(_livery_repair_palette $_DARKBG 450); _rc=$?
t "no profile snapshot: no output" "" "$_out"
t "no profile snapshot: fails"     "1" "$_rc"

# 7. a floor no lightness can reach must still improve on the original rather
#    than silently leaving an unreadable colour in place
_p_reset; _p_set ansi12:2a7bde
_rx=$(_repaired $_DARKBG 2000 ansi12)
_cx=$(_livery_contrast "$_rx" $_DARKBG)
if (( ${#_rx} == 6 && _cx > _c4o )); then pass=$((pass+1)); printf '  ok   %-42s %s -> %s\n' "unreachable floor still improves" "$_c4o" "$_cx"
else fail=$((fail+1)); printf '  FAIL %-42s got #%s at %s\n' "unreachable floor still improves" "$_rx" "$_cx"; fi

# 8. the reported case, with the values a real terminal gave back: gnome-terminal
#    3.44 on Ubuntu 22.04 (use-theme-colors, so the palette is the stock one) in
#    an auto project at auto_lightness 18. PS1 paints \w with 01;34, so the path
#    renders with ansi4 or ansi12 depending on bold-is-bright -- both were
#    illegible, and neither was measured anywhere.
_p_reset; _p_set ansi4:12488b ansi12:2a7bde
for _slot in ansi4:117 ansi12:251; do
  _k=${_slot%%:*}; _was=${_slot#*:}
  _got=$(_livery_contrast "${_LIVERY_P[$_k]}" $_DARKBG)
  t "reported: $_k on the auto bg was $_was" "$_was" "$_got"
done
# ansi12 is text-only, so the text floor is the whole contract.
_fix=$(_repaired $_DARKBG 450 ansi12)
_now=$(_livery_contrast "$_fix" $_DARKBG)
if (( ${_now:-0} >= 450 )); then pass=$((pass+1)); printf '  ok   %-42s #%s at %s\n' "ansi12 repaired to legible" "$_fix" "$_now"
else fail=$((fail+1)); printf '  FAIL %-42s #%s at %s\n' "ansi12 repaired to legible" "$_fix" "$_now"; fi

echo "== two-sided repair: slots programs paint as a background =="
# ansi1/ansi4/ansi5 are addressed both as text (\e[31m) and as a background
# (\e[41m). Repairing for the text role alone is what produced the reported
# bug: Symfony Console prints its error block as \e[37;41m -- ansi7 text on an
# ansi1 background -- and lightening ansi1 until it read as text left that block
# at 1.32:1, worse than the profile red it replaced.
_p_reset; _p_set ansi1:c01c28 ansi4:12488b ansi5:a347ba ansi7:d0cfcc
t "ansi1 is two-sided"     "0" "$(_livery_is_on_color_slot ansi1; echo $?)"
t "ansi4 is two-sided"     "0" "$(_livery_is_on_color_slot ansi4; echo $?)"
t "ansi5 is two-sided"     "0" "$(_livery_is_on_color_slot ansi5; echo $?)"
# green/yellow/cyan carry black text by convention, so their lightness already
# suits the background role and constraining them would only cost text contrast
t "ansi2 is not two-sided" "1" "$(_livery_is_on_color_slot ansi2; echo $?)"
t "ansi3 is not two-sided" "1" "$(_livery_is_on_color_slot ansi3; echo $?)"
t "ansi6 is not two-sided" "1" "$(_livery_is_on_color_slot ansi6; echo $?)"
# the bright bank is text-only: \e[101m-style backgrounds are too rare to pay for
t "ansi9 is not two-sided"  "1" "$(_livery_is_on_color_slot ansi9; echo $?)"
t "ansi12 is not two-sided" "1" "$(_livery_is_on_color_slot ansi12; echo $?)"

# the light text that actually lands on those slots is ansi7, not ansi15:
# Symfony emits \e[37m for fg=white
t "on-colour fg is ansi7" "d0cfcc" "$(_livery_on_color_fg)"
# theme values keep their leading '#' until _livery_resolve normalises them,
# so this has to normalise rather than hand back "#c8d1db"
_LIVERY_T[ansi7]='#C8D1DB'
t "on-colour fg is normalised"  "c8d1db" "$(_livery_on_color_fg)"
unset '_LIVERY_T[ansi7]'

# the contract: a repaired two-sided slot holds that text at the on-colour floor
for _k in ansi1 ansi4 ansi5; do
  _fix=$(_repaired $_DARKBG 450 "$_k")
  _on=$(_livery_contrast "$_fix" d0cfcc)
  if (( ${#_fix} == 6 && ${_on:-0} >= 300 )); then
    pass=$((pass+1)); printf '  ok   %-42s #%s at %s\n' "$_k holds light text as a bg" "$_fix" "$_on"
  else
    fail=$((fail+1)); printf '  FAIL %-42s #%s at %s\n' "$_k holds light text as a bg" "$_fix" "$_on"; fi
done

# and the one-sided repair is what broke it: repairing ansi1 for text alone
# drives the background role below the floor, which is the regression guarded here
_p_reset; _p_set ansi1:c01c28 ansi7:d0cfcc
_two=$(_repaired $_DARKBG 450 ansi1)
_one=$(_livery_repair_palette $_DARKBG 450 1 ffffff | awk '$1=="ansi1"{print $2}')
_on_two=$(_livery_contrast "$_two" d0cfcc)
_on_one=$(_livery_contrast "$_one" d0cfcc)
if (( _on_two > _on_one )); then pass=$((pass+1)); printf '  ok   %-42s %s vs %s\n' "two-sided beats text-only on colour" "$_on_two" "$_on_one"
else fail=$((fail+1)); printf '  FAIL %-42s %s vs %s\n' "two-sided beats text-only on colour" "$_on_two" "$_on_one"; fi

# a slot already good in both roles is left at the profile's own value
_p_reset; _p_set ansi1:c01c28 ansi7:d0cfcc
t "two-sided slot fine in both is kept" "" "$(_repaired 0b0f14 200 ansi1)"

# the shipped theme is the case the report came from: check the pair a user
# actually sees, ansi7 text sitting on ansi1
_THEME=themes/high-contrast-dark.conf
if [[ -r $_THEME ]]; then
  _t1=$(_livery_hex "$(awk '$1=="ansi1"{print $2}' $_THEME)")
  _t7=$(_livery_hex "$(awk '$1=="ansi7"{print $2}' $_THEME)")
  _tbg=$(_livery_hex "$(awk '$1=="bg"{print $2}' $_THEME)")
  _terr=$(_livery_contrast "$_t7" "$_t1")
  if (( ${_terr:-0} >= 300 )); then pass=$((pass+1)); printf '  ok   %-42s %s\n' "theme error block is readable" "$_terr"
  else fail=$((fail+1)); printf '  FAIL %-42s %s < 300\n' "theme error block is readable" "$_terr"; fi
  # The light bank carries black text (fg=black;bg=green), and that direction
  # is left without a ceiling on the grounds that the text floor already
  # implies it -- both want a lighter colour. Guard the claim: if it ever stops
  # holding, these slots need a floor of their own.
  _t0=$(_livery_hex "$(awk '$1=="ansi0"{print $2}' $_THEME)")
  for _k in ansi2 ansi3 ansi6 ansi7; do
    _tv=$(_livery_hex "$(awk -v k="$_k" '$1==k{print $2}' $_THEME)")
    _tb=$(_livery_contrast "$_tv" "$_t0")
    if (( ${_tb:-0} >= 300 )); then pass=$((pass+1)); printf '  ok   %-42s %s\n' "theme $_k holds black text" "$_tb"
    else fail=$((fail+1)); printf '  FAIL %-42s %s < 300\n' "theme $_k holds black text" "$_tb"; fi
  done

  # and it must not have bought that by making the text role unreadable
  for _k in ansi1 ansi2 ansi3 ansi4 ansi5 ansi6 ansi7; do
    _tv=$(_livery_hex "$(awk -v k="$_k" '$1==k{print $2}' $_THEME)")
    _tc=$(_livery_contrast "$_tv" "$_tbg")
    if (( ${_tc:-0} >= 400 )); then pass=$((pass+1)); printf '  ok   %-42s %s\n' "theme $_k still reads as text" "$_tc"
    else fail=$((fail+1)); printf '  FAIL %-42s %s < 400\n' "theme $_k still reads as text" "$_tc"; fi
  done
fi

echo "== auto repair is wired into scheme resolution =="
_cfg=$(mktemp); _root=$(mktemp -d); mkdir -p "$_root/someproj" "$_root/named"
_cache=$(mktemp -d)
printf 'fg ffffff\nansi4 12488b\nansi7 d0cfcc\n' > "$_cache/palette"
printf 'set default_bg #300a24\nset auto on\nset auto_root %s\nset auto_lightness 18\nset auto_min_contrast 450\nrule %s/named bg=#101010 ansi4=#12488b\n' \
  "$_root" "$_root" > "$_cfg"
LIVERY_CONF="$_cfg" _livery_load_conf 2>/dev/null
_p_reset; LIVERY_CACHE="$_cache" _livery_resolve "$_root/someproj" >/dev/null 2>&1
t "auto project is flagged as auto"      "1"       "${_LIVERY_R_auto:-}"
t "auto project repaired ansi4"          "$(_repaired "${_LIVERY_T[bg]}" 450 ansi4)" "${_LIVERY_T[ansi4]:-}"
t "auto project left ansi7 to the profile" ""      "${_LIVERY_T[ansi7]:-}"
# a configured rule names its own colours; repair must not touch them
_p_reset; LIVERY_CACHE="$_cache" _livery_resolve "$_root/named" >/dev/null 2>&1
t "configured rule is not flagged auto"  ""        "${_LIVERY_R_auto:-}"
t "configured rule keeps its own ansi4"  "12488b"  "${_LIVERY_T[ansi4]:-}"
t "configured rule repairs nothing"      ""        "${_LIVERY_R_repaired:-}"
# and the whole thing is switchable, which is what restores the documented
# "profile palette untouched" signal
printf 'set default_bg #300a24\nset auto on\nset auto_root %s\nset auto_contrast off\n' "$_root" > "$_cfg"
LIVERY_CONF="$_cfg" _livery_load_conf 2>/dev/null
_p_reset; LIVERY_CACHE="$_cache" _livery_resolve "$_root/someproj" >/dev/null 2>&1
t "auto_contrast off repairs nothing"    ""        "${_LIVERY_R_repaired:-}"
t "auto_contrast off still sets a bg"    "6"       "${#_LIVERY_T[bg]}"
rm -rf "$_cfg" "$_root" "$_cache"

echo "== option validation =="
# These values reach bash arithmetic in the reporting paths, where a non-numeric
# one is a syntax error, not a warning. They have to be rejected at load.
_cfg=$(mktemp)
printf 'set auto_min_contrast abc\nset min_contrast 7x\nset auto_contrast maybe\nset mode sideways\nset fade_steps -4\nset on_color_contrast wat\n' > "$_cfg"
_warn=$(LIVERY_CONF="$_cfg" _livery_load_conf 2>&1 >/dev/null)
LIVERY_CONF="$_cfg" _livery_load_conf 2>/dev/null
t "bad auto_min_contrast falls back" "450"  "$_LIVERY_O_auto_min_contrast"
t "bad min_contrast falls back"      "700"  "$_LIVERY_O_min_contrast"
t "bad auto_contrast falls back"     "on"   "$_LIVERY_O_auto_contrast"
t "bad mode falls back"              "dark" "$_LIVERY_O_mode"
t "negative fade_steps falls back"   "16"   "$_LIVERY_O_fade_steps"
t "bad on_color_contrast falls back" "300"  "$_LIVERY_O_on_color_contrast"
_n=$(printf '%s\n' "$_warn" | grep -c 'livery:')
t "each bad value warns once"        "6"    "$_n"
# and a good config must stay silent, or the warnings mean nothing
printf 'set auto_min_contrast 500\nset mode tint\nset auto_contrast off\nset on_color_contrast 450\n' > "$_cfg"
_warn=$(LIVERY_CONF="$_cfg" _livery_load_conf 2>&1 >/dev/null)
t "valid values warn about nothing"  ""     "$_warn"
LIVERY_CONF="$_cfg" _livery_load_conf 2>/dev/null
t "valid auto_min_contrast is kept"  "500"  "$_LIVERY_O_auto_min_contrast"
t "valid on_color_contrast is kept"  "450"  "$_LIVERY_O_on_color_contrast"
rm -f "$_cfg"

echo; printf 'pass=%d fail=%d\n' "$pass" "$fail"; exit $(( fail > 0 ))
