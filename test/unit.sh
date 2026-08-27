#!/bin/bash
# Unit tests: pure color math, no terminal required.
LIVERY_SH="${LIVERY_SH:-$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)/livery.sh}"
export LIVERY_FORCE=1
export LIVERY_CONF=/nonexistent-on-purpose
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

echo; printf 'pass=%d fail=%d\n' "$pass" "$fail"; exit $(( fail > 0 ))
