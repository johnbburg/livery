#!/bin/bash
# Default run is headless: it spawns no windows and steals no keyboard focus.
#
#   ./test/run-tests.sh                  unit + logic + headless-safety
#   ./test/run-tests.sh --real-terminal  also drive a real gnome-terminal
#
# --real-terminal opens a terminal window that takes focus while it runs, and
# stray keystrokes land in it, so only use it when you are not typing.
set -u
HERE=$(cd "${BASH_SOURCE[0]%/*}" && pwd)
export LIVERY_SH="${LIVERY_SH:-$(cd "$HERE/.." && pwd)/livery.sh}"
REAL=0; [[ ${1:-} == --real-terminal ]] && REAL=1
rc=0

bash -n "$LIVERY_SH" || { echo "syntax error in $LIVERY_SH"; exit 1; }

echo "== unit: colour math, no terminal =="
bash "$HERE/unit.sh" || rc=1

echo
echo "== logic: livery.sh against a mock terminal on a pty =="
python3 "$HERE/logic.py" || rc=1

echo
echo "== cli: probe, doctor, audit and reload against the mock terminal =="
python3 "$HERE/cli.py" || rc=1

echo
echo "== awk portability: the contrast maths must not need GNU extensions =="
if command -v mawk >/dev/null; then
  tmpd=$(mktemp -d); ln -sf "$(command -v mawk)" "$tmpd/awk"
  got=$(PATH="$tmpd:$PATH" LIVERY_FORCE=1 LIVERY_CONF=/nonexistent bash -c \
        "source '$LIVERY_SH'; _livery_contrast ffffff 000000")
  if [ "$got" = "2100" ]; then echo "  ok   contrast under mawk = $got"
  else echo "  FAIL contrast under mawk = $got (want 2100)"; rc=1; fi
  # The repair solves a lightness ramp in awk rather than forking
  # _livery_contrast per candidate, so it carries its own copy of the luminance
  # maths -- and has to agree with the bash one on both awks, or `livery test`
  # would report a different figure than the one the repair aimed at.
  repair_probe='
    source "$LIVERY_SH"
    _LIVERY_P[ansi12]=2a7bde
    read -r _ fixed ratio <<<"$(_livery_repair_palette 244714 450)"
    printf "%s %s %s" "$fixed" "$ratio" "$(_livery_contrast "$fixed" 244714)"'
  # The two-sided search carries a second copy of the same maths -- the contrast
  # of the light text sitting *on* the slot -- so it needs its own probe. awk
  # reports the slot against the background; bash re-measures both roles.
  oncolor_probe='
    source "$LIVERY_SH"
    _LIVERY_P[ansi1]=c01c28
    _LIVERY_P[ansi7]=d0cfcc
    read -r _ fixed ratio <<<"$(_livery_repair_palette 244714 450 300 d0cfcc | grep ^ansi1)"
    printf "%s %s %s %s" "$fixed" "$ratio" "$(_livery_contrast "$fixed" 244714)" \
      "$(_livery_contrast "$fixed" d0cfcc)"'
  for awkname in default mawk; do
    if [ "$awkname" = mawk ]; then p="$tmpd:$PATH"; else p="$PATH"; fi
    got=$(PATH="$p" LIVERY_FORCE=1 LIVERY_CONF=/nonexistent LIVERY_SH="$LIVERY_SH" \
          LIVERY_CACHE="$tmpd/cache" bash -c "$repair_probe")
    set -- $got
    if [ "${1:-}" = "7eafeb" ] && [ -n "${2:-}" ] && [ "${2:-}" = "${3:-}" ]; then
      echo "  ok   repair under $awkname awk = #$1, awk and bash agree at $2"
    else
      echo "  FAIL repair under $awkname awk = '$got' (want '7eafeb 464 464')"; rc=1
    fi
    got=$(PATH="$p" LIVERY_FORCE=1 LIVERY_CONF=/nonexistent LIVERY_SH="$LIVERY_SH" \
          LIVERY_CACHE="$tmpd/cache" bash -c "$oncolor_probe")
    set -- $got
    if [ "${1:-}" = "df2533" ] && [ "${2:-}" = "${3:-}" ] && [ "${4:-0}" -ge 300 ]; then
      echo "  ok   two-sided under $awkname awk = #$1, holds light text at $4"
    else
      echo "  FAIL two-sided under $awkname awk = '$got' (want 'df2533 224 224 303')"; rc=1
    fi
  done
  rm -rf "$tmpd"
else
  echo "  SKIP mawk not installed; GNU-extension regressions cannot be caught here"
fi

echo
echo "== prompt: interactive shell must still draw prompts and echo input =="
python3 "$HERE/prompt.py" || rc=1

echo
echo "== headless safety: sourcing must be silent with no tty =="
e=$(setsid bash -c "LIVERY_FORCE=1 source '$LIVERY_SH'; cd /tmp; _livery_hook" 2>&1 >/dev/null </dev/null)
if [[ -z $e ]]; then echo "  ok   no stderr in a no-tty shell"; else echo "  FAIL stderr: $e"; rc=1; fi

if (( REAL )); then
  echo
  echo "== real terminal: gnome-terminal, colours read back off the tty =="
  if command -v gnome-terminal >/dev/null; then
    E=$(mktemp -d); export E
    mkdir -p "$E"/proj-a/sub "$E"/proj-b "$E"/proj-loud "$E"/auto/alpha-proj "$E"/auto/beta-proj
    cat > "$E/conf" <<CONF
set default_bg  #300a24
set mode        tint          # this suite covers tint mode; logic.py covers dark
set alpha       20
set fade_ms     80
set fade_steps  6
set auto        on
set auto_root   $E/auto
rule $E/proj-a      accent=#61afef
rule $E/proj-a/sub  accent=#98c379 alpha=40
rule $E/proj-b      accent=#e06c75 alpha=30   # trailing comment
rule $E/proj-loud   bg=#3a0d0d fg=#ffd7d7 cursor=#ff5555
rule $E/proj-theme  theme=tstpal
CONF
    mkdir -p "$E/themes" "$E/proj-theme"
    cat > "$E/themes/tstpal.conf" <<'THEME'
bg      #0b0f14
fg      #dfe6ee
cursor  #ffcc66
ansi1   #ff9a9a
ansi4   #79b8ff
ansi12  #a8d3ff
THEME
    gnome-terminal --wait --geometry=60x14 --title="livery real-terminal tests" -- \
      env E="$E" LIVERY_SH="$LIVERY_SH" LIVERY_THEMES="$E/themes" \
      bash "$HERE/tty.sh" "$E/out.txt" "$E/conf"
    cat "$E/out.txt"
    grep -q '^pass=[0-9]* fail=0$' "$E/out.txt" || rc=1
    rm -rf "$E"
  else
    echo "  SKIP no gnome-terminal on PATH"
  fi
else
  echo
  echo "  (skipped the real-terminal suite; pass --real-terminal to include it)"
fi

echo
[[ $rc == 0 ]] && echo "ALL SUITES PASSED" || echo "FAILURES PRESENT"
exit $rc
