#!/bin/sh
# Does this terminal support what livery needs?
#
#   sh tools/terminal-probe.sh
#
# Deliberately POSIX sh: no arrays, no [[ ]], no `read -t`/`-d`, no bashisms.
# It runs under sh, bash (including macOS's bash 3.2) and zsh, and answers the
# terminal question without livery being installed or sourced at all.
#
# It sets a colour, reads it back, then restores the original. Nothing is left
# changed. If your terminal ignores the sequences, the worst case is no output
# and a short wait.

if [ ! -t 0 ] || [ ! -w /dev/tty ]; then
  echo "no controlling terminal -- run this in a terminal window"
  exit 1
fi

old=$(stty -g 2>/dev/null) || { echo "cannot read tty settings"; exit 1; }
restore() { stty "$old" 2>/dev/null; }
trap 'restore; exit 130' INT TERM

# Query OSC $1 (optionally palette index $2), echo the raw reply.
query() {
  if [ -n "$2" ]; then printf '\033]%s;%s;?\033\\' "$1" "$2" > /dev/tty
  else                 printf '\033]%s;?\033\\' "$1" > /dev/tty
  fi
  stty -icanon -echo min 0 time 5 2>/dev/null      # 0.5s timeout
  dd bs=1 count=64 2>/dev/null < /dev/tty
}

setcol() {
  if [ -n "$3" ]; then printf '\033]%s;%s;%s\033\\' "$1" "$3" "$2" > /dev/tty
  else                 printf '\033]%s;%s\033\\' "$1" "$2" > /dev/tty
  fi
}

# name, OSC code, optional palette index
probe() {
  name=$1; code=$2; idx=$3
  before=$(query "$code" "$idx")
  case "$before" in
    *rgb:*) ;;
    *) printf '  %-26s no reply to query\n' "$name"; return 1 ;;
  esac
  orig=$(printf '%s' "$before" | sed -n 's/.*rgb:\([0-9a-fA-F]*\)\/\([0-9a-fA-F]*\)\/\([0-9a-fA-F]*\).*/\1 \2 \3/p')
  setcol "$code" '#123456' "$idx"
  after=$(query "$code" "$idx")
  # restore: rebuild the original spec from the reply we captured
  set -- $orig
  if [ -n "$1" ]; then
    setcol "$code" "rgb:$1/$2/$3" "$idx"
  fi
  case "$after" in
    *rgb:1212*|*rgb:12*) printf '  %-26s YES\n' "$name" ;;
    *) printf '  %-26s no (set had no effect)\n' "$name"; return 1 ;;
  esac
  return 0
}

printf 'Terminal probe for livery\n'
printf '  TERM=%s  TERM_PROGRAM=%s\n\n' "${TERM:-unset}" "${TERM_PROGRAM:-unset}"

fails=0
probe 'background  (OSC 11)' 11    || fails=$((fails+1))
probe 'foreground  (OSC 10)' 10    || fails=$((fails+1))
probe 'cursor      (OSC 12)' 12    || fails=$((fails+1))
probe 'palette 1   (OSC 4;1)'  4 1 || fails=$((fails+1))
probe 'palette 4   (OSC 4;4)'  4 4 || fails=$((fails+1))
probe 'palette 12  (OSC 4;12)' 4 12|| fails=$((fails+1))

printf '\033]104\033\\\033]110\033\\\033]111\033\\\033]112\033\\' > /dev/tty
restore

printf '\n'
if [ "$fails" -eq 0 ]; then
  printf 'All supported. livery will work in this terminal.\n'
  printf 'The remaining question is your shell: livery needs bash 4+ (macOS\n'
  printf 'ships 3.2), and there is no zsh port yet.\n'
elif [ "$fails" -lt 6 ]; then
  printf '%s of 6 unsupported. Backgrounds may work while prompt colours do not,\n' "$fails"
  printf 'or vice versa. Paste this output into an issue.\n'
else
  printf 'None supported -- this terminal ignores these sequences entirely.\n'
  printf 'livery cannot work here. Try a different terminal (iTerm2, kitty,\n'
  printf 'WezTerm, gnome-terminal) before investing any further.\n'
fi
