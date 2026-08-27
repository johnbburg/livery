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
