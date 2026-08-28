#!/bin/sh
# Does this terminal support what livery needs?
#
#   sh tools/terminal-probe.sh
#
# Deliberately POSIX sh: no arrays, no [[ ]], no `read -t`/`-d`, no bashisms.
# It runs under sh, bash (including macOS's bash 3.2) and zsh, and answers the
# terminal question without livery being installed or sourced at all.
#
# It restores every colour it touches, and only those. It deliberately does NOT
# send a global reset (OSC 104 and friends) on the way out: that would clear all
# sixteen palette entries including ones it never looked at, which would wipe a
# palette set by livery or by anything else.

if [ ! -t 0 ] || [ ! -w /dev/tty ]; then
  echo "no controlling terminal -- run this in a terminal window"
  exit 1
fi

old=$(stty -g 2>/dev/null) || { echo "cannot read tty settings"; exit 1; }

# Whatever colour is mid-probe when we are interrupted, so the trap can put it
# back rather than leaving the terminal on the test colour.
fly_code=''; fly_idx=''; fly_spec=''

setcol() {   # code value [index]
  if [ -n "$3" ]; then printf '\033]%s;%s;%s\033\\' "$1" "$3" "$2" > /dev/tty
  else                 printf '\033]%s;%s\033\\' "$1" "$2" > /dev/tty
  fi
}

cleanup() {
  [ -n "$fly_spec" ] && setcol "$fly_code" "$fly_spec" "$fly_idx"
  stty "$old" 2>/dev/null
}
trap cleanup EXIT
trap 'cleanup; exit 130' INT TERM

# Echo off for the WHOLE run, before the first query goes out: otherwise the
# terminal's reply to that first query is echoed onto the screen as garbage.
stty -icanon -echo min 0 time 5 2>/dev/null    # 0.5s read timeout

query() {    # code [index] -> raw reply
  if [ -n "$2" ]; then printf '\033]%s;%s;?\033\\' "$1" "$2" > /dev/tty
  else                 printf '\033]%s;?\033\\' "$1" > /dev/tty
  fi
  dd bs=1 count=64 2>/dev/null < /dev/tty
}

# rgb:RRRR/GGGG/BBBB (components are 1-4 hex digits) -> rrggbb, lowercased.
# Comparing whole normalised colours matters: matching a substring of the reply
# would call a terminal "supported" when it only changed the red channel, or
# when the colour it already had happened to start with the same digits.
norm() {
  _c=$(printf '%s' "$1" \
       | sed -n 's/.*rgb:\([0-9a-fA-F]\{1,4\}\)\/\([0-9a-fA-F]\{1,4\}\)\/\([0-9a-fA-F]\{1,4\}\).*/\1 \2 \3/p')
  [ -z "$_c" ] && return 1
  _out=''
  for _p in $_c; do
    case ${#_p} in
      1) _out="$_out$_p$_p" ;;
      *) _out="$_out$(printf '%s' "$_p" | cut -c1-2)" ;;
    esac
  done
  printf '%s' "$_out" | tr 'ABCDEF' 'abcdef'
}

probe() {    # name code [index]
  name=$1; code=$2; idx=$3
  # The reply must be for the code (and index) we asked about, not just any
  # OSC colour reply that happened to be sitting in the buffer.
  if [ -n "$idx" ]; then want="]$code;$idx;rgb:"; else want="]$code;rgb:"; fi

  before=$(query "$code" "$idx")
  case "$before" in
    *"$want"*) ;;
    *rgb:*) printf '  %-26s replied about a different colour\n' "$name"; return 1 ;;
    *) printf '  %-26s no reply to query\n' "$name"; return 1 ;;
  esac
  orig=$(norm "$before") || { printf '  %-26s unparseable reply\n' "$name"; return 1; }

  fly_code=$code; fly_idx=$idx; fly_spec="#$orig"
  setcol "$code" '#123456' "$idx"
  after=$(query "$code" "$idx")
  setcol "$fly_code" "$fly_spec" "$fly_idx"
  fly_code=''; fly_idx=''; fly_spec=''

  case "$after" in
    *"$want"*) ;;
    *) printf '  %-26s no reply after setting\n' "$name"; return 1 ;;
  esac
  got=$(norm "$after")
  if [ "$got" = "123456" ]; then
    printf '  %-26s YES\n' "$name"
  else
    printf '  %-26s no (asked for 123456, got %s)\n' "$name" "${got:-nothing}"
    return 1
  fi
  return 0
}

printf 'Terminal probe for livery\n'
printf '  TERM=%s  TERM_PROGRAM=%s\n\n' "${TERM:-unset}" "${TERM_PROGRAM:-unset}"

fails=0
probe 'background  (OSC 11)'  11    || fails=$((fails+1))
probe 'foreground  (OSC 10)'  10    || fails=$((fails+1))
probe 'cursor      (OSC 12)'  12    || fails=$((fails+1))
probe 'palette 1   (OSC 4;1)'  4 1  || fails=$((fails+1))
probe 'palette 4   (OSC 4;4)'  4 4  || fails=$((fails+1))
probe 'palette 12  (OSC 4;12)' 4 12 || fails=$((fails+1))

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
