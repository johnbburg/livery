# livery.sh — Terminal Project Colors
# Recolors the terminal background when you cd into a configured project.
# Source from ~/.bashrc:   source ~/projects/livery/livery.sh
#
# Verified against: gnome-terminal 3.44 / VTE 0.68 (OSC 10/11/12 set+query,
# OSC 110/111/112 reset). Degrades to a no-op where those are unsupported.

# interactive only (LIVERY_FORCE=1 bypasses this, for the test suite)
if [[ -z ${LIVERY_FORCE:-} ]]; then case $- in *i*) ;; *) return 0 2>/dev/null || exit 0 ;; esac; fi

LIVERY_CONF="${LIVERY_CONF:-$HOME/.config/livery/livery.conf}"
LIVERY_CACHE="${LIVERY_CACHE:-$HOME/.cache/livery}"
LIVERY_THEMES="${LIVERY_THEMES:-$HOME/.config/livery/themes}"

# ---------------------------------------------------------------- options ----
_livery_defaults() {
  _LIVERY_O_enable=on    _LIVERY_O_mode=dark
  _LIVERY_O_lightness=10 _LIVERY_O_saturation=70   # derived backgrounds (mode=dark)
  _LIVERY_O_alpha=18                               # mode=tint only
  _LIVERY_O_fade_ms=260  _LIVERY_O_fade_steps=16
  _LIVERY_O_auto=on      _LIVERY_O_auto_root="$HOME/projects"
  _LIVERY_O_auto_lightness=18   # auto projects sit above the configured band
  _LIVERY_O_auto_contrast=on    # lighten profile palette slots the auto bg makes unreadable
  _LIVERY_O_auto_min_contrast=450                  # the floor that repair aims for (4.50:1)
  _LIVERY_O_title=off    _LIVERY_O_default_bg=
  _LIVERY_O_min_contrast=700                       # warn below 7.00:1
  _LIVERY_O_on_color_contrast=300  # floor for light text sitting *on* a slot
}

# An ANSI slot is addressed in two roles: as text (`\e[31m`) and as a background
# (`\e[41m`). Contrast against the project background covers the first role and
# says nothing about the second, and the two pull opposite ways -- lightening a
# slot until it is legible as text is exactly what makes it illegible under the
# text a program puts on it.
#
# These are the slots programs pair with *light* text, so they have a ceiling as
# well as a floor. Symfony Console's error block -- composer, drush, every
# Drupal tool -- emits `\e[37;41m`, ansi7 on ansi1; its debug formatter emits
# `bg=blue;fg=white`. ansi7 is omitted because it *is* the light text.
#
# Green, yellow and cyan are omitted for a stronger reason than convention:
# their pairing is black text (`fg=black;bg=green`, `fg=black;bg=yellow`), and
# that direction needs no ceiling because it does not oppose the text floor.
# Both constraints want a lighter colour, so clearing one clears the other.
# Swept exhaustively over hue, saturation and lightness against the shipped
# theme's background: of the 65016 values that clear min_contrast at 7:1 as
# text, the worst holds ansi0 at 5.55:1, well above this floor. Only the
# light-text direction pulls against the text floor, so only it needs a
# ceiling -- constraining the light bank as well would cost text contrast to
# fix nothing. `livery test` guards the claim rather than restating it.
#
# The bright bank is omitted: `\e[101m`-style bright backgrounds are rare enough
# that constraining ansi9..ansi15 would cost text contrast for nothing.
_LIVERY_ON_COLOR_SLOTS=(ansi1 ansi4 ansi5)

_livery_is_on_color_slot() {    # slot -> 0 if it is used as a background
  local s
  for s in "${_LIVERY_ON_COLOR_SLOTS[@]}"; do [[ $1 == "$s" ]] && return 0; done
  return 1
}

# The text a program actually puts on one of those slots. Symfony emits `\e[37m`
# for `fg=white`, which is ansi7 -- not ansi15 -- so ansi7 is what has to stay
# legible. Falls back to the profile's ansi7, then to white.
_livery_on_color_fg() {
  local v h
  v="${_LIVERY_T[ansi7]:-}"
  [[ -z $v ]] && v="${_LIVERY_P[ansi7]:-}"
  # Theme values are not normalised until _livery_resolve runs, so this can be
  # reached with a leading '#' still on it.
  h=$(_livery_hex "${v:-ffffff}") || h=ffffff
  printf '%s' "$h"
}

# ------------------------------------------------------------ color helpers --
# All integer math; no bc/awk dependency.

# Render a color for display: "#rrggbb", or a fallback when unset.
_livery_fmt() { if [[ -n $1 ]]; then printf '#%s' "$1"; else printf '%s' "${2:-<default>}"; fi; }

_livery_expand_tilde() { case "$1" in "~"/*) printf '%s' "$HOME${1#\~}" ;; *) printf '%s' "$1" ;; esac; }

# "#rgb" | "#rrggbb" | "rrggbb" -> "rrggbb" (lowercase), or empty if invalid
_livery_hex() {
  local h="${1#\#}"
  h="${h,,}"
  case "$h" in
    [0-9a-f][0-9a-f][0-9a-f]) printf '%s%s%s%s%s%s' "${h:0:1}" "${h:0:1}" "${h:1:1}" "${h:1:1}" "${h:2:1}" "${h:2:1}" ;;
    [0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f][0-9a-f]) printf '%s' "$h" ;;
    *) return 1 ;;
  esac
}

# hex -> "R G B" decimal
_livery_rgb() { local h; h=$(_livery_hex "$1") || return 1; printf '%d %d %d' "0x${h:0:2}" "0x${h:2:2}" "0x${h:4:2}"; }

# --- HSL, for deriving dark backgrounds -------------------------------------
# Integer math, hue in degrees 0-359, saturation and lightness in percent.
# Blending a near-black background toward a bright accent always *raises*
# luminance, which is wrong for a dark theme. Pinning lightness instead keeps
# each project's hue distinguishable at a consistently dark level.

_livery_rgb_to_hsl() {          # hex -> "H S L"
  local r g b mx mn d l sat hue
  read -r r g b <<<"$(_livery_rgb "$1")" || return 1
  mx=$r; (( g > mx )) && mx=$g; (( b > mx )) && mx=$b
  mn=$r; (( g < mn )) && mn=$g; (( b < mn )) && mn=$b
  d=$(( mx - mn ))
  l=$(( (mx + mn) * 50 / 255 ))
  if (( d == 0 )); then
    hue=0; sat=0
  else
    if (( mx + mn <= 255 )); then sat=$(( d * 100 / (mx + mn) ))
    else                          sat=$(( d * 100 / (510 - mx - mn) )); fi
    if   (( mx == r )); then hue=$(( ((g - b) * 60 + (d/2)) / d ));       (( hue < 0 )) && hue=$(( hue + 360 ))
    elif (( mx == g )); then hue=$(( ((b - r) * 60 + (d/2)) / d + 120 ))
    else                     hue=$(( ((r - g) * 60 + (d/2)) / d + 240 )); fi
    hue=$(( (hue % 360 + 360) % 360 ))
  fi
  printf '%d %d %d' "$hue" "$sat" "$l"
}

_livery_hue_channel() {         # helper: p q hue(0-359 scaled by 1000) -> 0-255
  local p=$1 q=$2 t=$3
  (( t < 0 ))     && t=$(( t + 360000 ))
  (( t >= 360000 )) && t=$(( t - 360000 ))
  if   (( t < 60000  )); then printf '%d' $(( (p + (q - p) * t / 60000) * 255 / 1000 ))
  elif (( t < 180000 )); then printf '%d' $(( q * 255 / 1000 ))
  elif (( t < 240000 )); then printf '%d' $(( (p + (q - p) * (240000 - t) / 60000) * 255 / 1000 ))
  else                        printf '%d' $(( p * 255 / 1000 ))
  fi
}

_livery_hsl_to_hex() {          # H S L -> hex
  local h=$1 s=$2 l=$3 q p
  (( l < 0 )) && l=0; (( l > 100 )) && l=100
  (( s < 0 )) && s=0; (( s > 100 )) && s=100
  if (( s == 0 )); then
    printf '%02x%02x%02x' $(( l * 255 / 100 )) $(( l * 255 / 100 )) $(( l * 255 / 100 )); return 0
  fi
  # work in per-mille to keep precision without floats
  if (( l < 50 )); then q=$(( l * (100 + s) / 10 ))
  else                  q=$(( (l + s - l * s / 100) * 10 )); fi
  p=$(( 2 * l * 10 - q ))
  printf '%02x%02x%02x' \
    "$(_livery_hue_channel "$p" "$q" $(( h * 1000 + 120000 )))" \
    "$(_livery_hue_channel "$p" "$q" $(( h * 1000 )))" \
    "$(_livery_hue_channel "$p" "$q" $(( h * 1000 - 120000 )))"
}

# Keep hue, force lightness (and optionally cap saturation).
_livery_at_lightness() {        # hex target_L [max_S] -> hex
  local h s l
  read -r h s l <<<"$(_livery_rgb_to_hsl "$1")" || return 1
  [[ -n ${3:-} ]] && (( s > $3 )) && s=$3
  _livery_hsl_to_hex "$h" "$s" "$2"
}

# WCAG relative luminance and contrast ratio. Needs a real power function, so
# this shells out to awk; it runs in `livery test`/`doctor`, never in the fade.
_livery_contrast() {            # hex hex -> ratio x100 (e.g. 1057 = 10.57:1)
  local a b ar ag ab br bg bb
  a=$(_livery_hex "$1") || return 1
  b=$(_livery_hex "$2") || return 1
  read -r ar ag ab <<<"$(_livery_rgb "$a")" || return 1
  read -r br bg bb <<<"$(_livery_rgb "$b")" || return 1
  # Channels are passed in as decimals: strtonum() is a GNU awk extension and
  # mawk, which is the default awk on many Debian/Ubuntu systems, lacks it.
  awk -v ar="$ar" -v ag="$ag" -v ab="$ab" -v br="$br" -v bg="$bg" -v bb="$bb" '
    function chan(v) { v = v/255; return (v <= 0.03928) ? v/12.92 : ((v+0.055)/1.055)^2.4 }
    BEGIN { la = 0.2126*chan(ar) + 0.7152*chan(ag) + 0.0722*chan(ab)
            lb = 0.2126*chan(br) + 0.7152*chan(bg) + 0.0722*chan(bb)
            if (la < lb) { t = la; la = lb; lb = t }
            printf "%d", ((la+0.05)/(lb+0.05))*100 + 0.5 }'
}

# blend base toward accent by pct (0..100)
_livery_blend() {
  local base="$1" accent="$2" pct="$3" br bg bb ar ag ab
  read -r br bg bb <<<"$(_livery_rgb "$base")"   || return 1
  read -r ar ag ab <<<"$(_livery_rgb "$accent")" || return 1
  printf '%02x%02x%02x' \
    $(( (br*(100-pct) + ar*pct + 50) / 100 )) \
    $(( (bg*(100-pct) + ag*pct + 50) / 100 )) \
    $(( (bb*(100-pct) + ab*pct + 50) / 100 ))
}

# linear interpolation from -> to at step/total
_livery_lerp() {
  local f="$1" t="$2" s="$3" n="$4" fr fg fb tr tg tb
  read -r fr fg fb <<<"$(_livery_rgb "$f")" || return 1
  read -r tr tg tb <<<"$(_livery_rgb "$t")" || return 1
  printf '%02x%02x%02x' \
    $(( fr + ((tr-fr)*s + (n/2)*((tr>=fr)*2-1) ) / n )) \
    $(( fg + ((tg-fg)*s + (n/2)*((tg>=fg)*2-1) ) / n )) \
    $(( fb + ((tb-fb)*s + (n/2)*((tb>=fb)*2-1) ) / n ))
}

# ----------------------------------------------------------------- plumbing --
# Can we talk to a controlling terminal? Probed once and memoised. The probe is
# wrapped so that a failing ">/dev/tty" redirection cannot leak a shell error --
# redirections are applied left to right, so an inline "2>/dev/null" is too late.
_livery_tty_ok() {
  if [[ -z ${_LIVERY_TTY_OK:-} ]]; then
    case "$TERM" in
      dumb|linux|''|unknown) _LIVERY_TTY_OK=0 ;;
      *) if { : >/dev/tty; } 2>/dev/null; then _LIVERY_TTY_OK=1; else _LIVERY_TTY_OK=0; fi ;;
    esac
  fi
  [[ $_LIVERY_TTY_OK == 1 ]]
}
# Real escape bytes, not "\033" for printf %b to interpret. Concatenating two
# %b-style sequences merges "\033\" + "\033" into "\033\\033", which %b reads as
# ESC + backslash + the literal text "033" -- so only the first sequence in a
# batched write survives and the rest is printed to the screen as garbage.
_LIVERY_ESC=$'\033'
_LIVERY_BEL=$'\007'
_livery_osc() {          # OSC body -> full sequence with ST terminator
  printf '%s]%s%s\\' "$_LIVERY_ESC" "$1" "$_LIVERY_ESC"
}
_livery_emit() { _livery_tty_ok && { printf '%s' "$1" >/dev/tty; } 2>/dev/null; return 0; }

# Sub-second sleep without forking. The fd MUST be allocated at source time:
# running "exec {var}<> <(:)" inside PROMPT_COMMAND kills an interactive shell
# outright -- it stops writing its prompt and stops echoing input. Allocating
# once up front and only reading here is safe. Falls back to sleep(1).
_livery_init_sleepfd() {
  [[ -n ${_LIVERY_SLEEPFD:-} ]] && return 0
  { exec {_LIVERY_SLEEPFD}<> <(:); } 2>/dev/null
  [[ -n ${_LIVERY_SLEEPFD:-} ]] || _LIVERY_SLEEPFD=none
  return 0
}

_livery_msleep() {
  local ms=$1 spec
  (( ms <= 0 )) && return 0
  printf -v spec '%d.%03d' $(( ms/1000 )) $(( ms%1000 ))
  if [[ ${_LIVERY_SLEEPFD:-none} == none ]]; then
    sleep "$spec"
  else
    read -r -t "$spec" -u "$_LIVERY_SLEEPFD" _ 2>/dev/null
  fi
  return 0
}

# Query the terminal's current background. Echoes hex, or nothing on failure.
# Guarded: short timeout, strict validation, stty always restored.
# Query any OSC colour: code 10/11/12, or code 4 with a palette index.
# Reads until it sees a reply matching the code it asked about -- a stale reply
# left in the buffer by another program would otherwise be accepted as the
# answer, poisoning every later comparison.
_livery_query_color() {
  local code="$1" idx="${2:-}" old reply want tries=0 r g b
  _livery_tty_ok || return 1
  { exec 3<>/dev/tty; } 2>/dev/null || return 1
  old=$(stty -g <&3 2>/dev/null) || { exec 3>&-; return 1; }
  stty raw -echo <&3 2>/dev/null
  if [[ -n $idx ]]; then
    printf '\033]%s;%s;?\033\\' "$code" "$idx" >&3; want="]$code;$idx;rgb:"
  else
    printf '\033]%s;?\033\\' "$code" >&3;          want="]$code;rgb:"
  fi
  while (( tries++ < 4 )); do
    IFS= read -r -d '\' -t 0.4 reply <&3 2>/dev/null || break
    [[ $reply == *"$want"* ]] && break
    reply=
  done
  stty "$old" <&3 2>/dev/null
  exec 3>&- 3<&-
  [[ $reply =~ rgb:([0-9a-fA-F]+)/([0-9a-fA-F]+)/([0-9a-fA-F]+) ]] || return 1
  r=${BASH_REMATCH[1]}; g=${BASH_REMATCH[2]}; b=${BASH_REMATCH[3]}
  printf '%s%s%s' "${r:0:2}" "${g:0:2}" "${b:0:2}"
}

_livery_query_bg() { _livery_query_color 11; }

# gnome-terminal has been observed reporting two different "default"
# backgrounds for the same profile (#300a24 and #380c2a, exactly 7/6 apart),
# switching between them within the first seconds of a window's life. The cause
# is not established: it tracks neither elapsed time nor focus/backdrop state
# consistently. Sampling three times and taking the most common answer removes
# one-off bad captures; setting default_bg in the config avoids the query
# entirely and is the reliable option.
_livery_query_bg_mode() {
  local a b c
  a=$(_livery_query_bg) || return 1
  _livery_msleep 80; b=$(_livery_query_bg) || { printf '%s' "$a"; return 0; }
  [[ $a == "$b" ]] && { printf '%s' "$a"; return 0; }
  _livery_msleep 80; c=$(_livery_query_bg) || { printf '%s' "$b"; return 0; }
  if   [[ $c == "$a" ]]; then printf '%s' "$a"
  elif [[ $c == "$b" ]]; then printf '%s' "$b"
  else printf '%s' "$c"; fi          # three different answers: trust the newest
}

# The profile default bg: config > cache > live query.
# _livery_init_default_bg must run in the CURRENT shell (never in a $(...) subshell)
# so the memo sticks. If it were reached lazily from inside _livery_resolve, the
# OSC 111 below would fire mid-session and flash the window to the default color.
_livery_init_default_bg() {
  local h cache="$LIVERY_CACHE/default_bg"
  if [[ -n ${_LIVERY_O_default_bg:-} ]] && h=$(_livery_hex "$_LIVERY_O_default_bg"); then
    _LIVERY_DEFAULT_BG=$h; return 0
  fi
  if [[ -r $cache ]] && h=$(_livery_hex "$(<"$cache")" 2>/dev/null); then
    _LIVERY_DEFAULT_BG=$h; return 0
  fi
  _livery_emit "$(_livery_osc 111)"     # reset first, so we read the true default
  if h=$(_livery_query_bg_mode); then
    mkdir -p "$LIVERY_CACHE" 2>/dev/null && printf '%s\n' "$h" >"$cache" 2>/dev/null
    _LIVERY_DEFAULT_BG=$h; return 0
  fi
  return 1
}

_livery_default_bg() {
  [[ -n ${_LIVERY_DEFAULT_BG:-} ]] || _livery_init_default_bg || return 1
  printf '%s' "$_LIVERY_DEFAULT_BG"
}

# --------------------------------------------------------- profile palette ---
# Auto projects take a derived background but keep the terminal profile's own
# text colours, and whether those are readable on that background is not
# something livery can assume. The stock Ubuntu palette's blue is #12488b: on an
# auto background it measures 1.17:1, and on the profile's own background
# 1.95:1, so the prompt path is illegible either way unless something overrides
# it. Configured rules override it by hand; auto projects have nobody to do
# that, so livery repairs the slots its own background makes unreadable.
#
# Repair needs the profile's values, which only the terminal knows. Reading them
# costs one OSC query per slot, so it happens once per machine and is cached on
# disk. It must happen while the palette is still the profile's own -- at source
# time, before any project colour is applied -- which is why a reset precedes
# it and why it is never reached lazily from the hook: a snapshot taken then
# would record whichever project was on screen.
#
# ansi0 and ansi8 are omitted deliberately: they are dim text and box drawing,
# and `livery test` already exempts them from the readability threshold. bold is
# omitted because no OSC query reports it.
_LIVERY_PROFILE_SLOTS=(fg ansi1 ansi2 ansi3 ansi4 ansi5 ansi6 ansi7
                       ansi9 ansi10 ansi11 ansi12 ansi13 ansi14 ansi15)

declare -A _LIVERY_P 2>/dev/null || true      # the profile's own text colours

_livery_profile_cache() { printf '%s/palette' "$LIVERY_CACHE"; }

# Disk only, never a query -- safe to reach from the prompt hook.
_livery_load_profile_cache() {
  (( ${#_LIVERY_P[@]} )) && return 0
  local cache k v h
  cache=$(_livery_profile_cache)
  [[ -r $cache ]] || return 1
  while read -r k v _; do
    [[ -z $k || $k == '#'* ]] && continue
    _livery_is_color_key "$k" || continue
    h=$(_livery_hex "$v") || continue
    _LIVERY_P[$k]="$h"
  done < "$cache"
  (( ${#_LIVERY_P[@]} ))
}

_livery_init_profile_palette() {
  _livery_load_profile_cache && return 0
  local cache k h idx got=0
  cache=$(_livery_profile_cache)
  _livery_tty_ok || return 1
  # Read the profile's own values, not some project's: clear the palette and
  # foreground first. Only reached on a cold cache.
  _livery_emit "$(_livery_osc 104)$(_livery_osc 110)"
  for k in "${_LIVERY_PROFILE_SLOTS[@]}"; do
    if [[ $k == fg ]]; then h=$(_livery_query_color 10)      || continue
    else idx=${k#ansi};     h=$(_livery_query_color 4 "$idx") || continue; fi
    _LIVERY_P[$k]="$h"; got=$((got+1))
  done
  (( got )) || return 1
  if mkdir -p "$LIVERY_CACHE" 2>/dev/null; then
    { for k in "${_LIVERY_PROFILE_SLOTS[@]}"; do
        [[ -n ${_LIVERY_P[$k]:-} ]] && printf '%s %s\n' "$k" "${_LIVERY_P[$k]}"
      done; } > "$cache" 2>/dev/null
  fi
  return 0
}

# Each repaired slot keeps its own hue and saturation and moves the shortest
# distance in lightness that clears the floor, so the palette stays recognisably
# the profile's -- brighter, not re-themed. Slots already clearing the floor are
# left alone and reset to the profile, which is what keeps an auto project
# visibly different from a configured one.
#
# The slots in _LIVERY_ON_COLOR_SLOTS are solved differently, because they have
# two constraints rather than one. Lightening such a slot until it is legible as
# text is what makes it illegible under the light text a program puts on it, so
# there the on-colour floor is the hard one: the search takes the value with the
# most contrast against the background from among those that still hold that
# text, rather than the least movement from the profile. Where the two floors
# cannot both be met the slot is emitted anyway, below its text floor, and
# `livery test`/`audit` report it -- the same treatment a one-sided slot gets
# when no lightness at its hue works.
#
# The whole set is solved in a single awk pass. _livery_contrast forks awk per
# call, so searching a lightness ramp per slot from the prompt hook would mean
# hundreds of forks on every cd; one fork measures at ~14 ms added to the
# directory change that triggers it, against a 260 ms fade. awk prints the exact hex whose channels it
# measured, using the same luminance formula and the same rounding to hundredths
# that _livery_contrast uses, so a repaired colour measures at or above the
# floor when `livery test` re-measures it in bash.
_livery_repair_palette() {      # bg floor [on_floor] [on_fg] -> "key hex ratio"
  local bg="$1" floor="$2" onfloor="${3:-}" onfg="${4:-}" k pairs= r g b
  local dual= fr fg_ fb
  read -r r g b <<<"$(_livery_rgb "$bg")" || return 1
  [[ -z $onfloor ]] && onfloor="${_LIVERY_O_on_color_contrast:-300}"
  [[ $onfloor =~ ^[0-9]+$ ]] || onfloor=300
  [[ -z $onfg ]] && onfg=$(_livery_on_color_fg)
  onfg=$(_livery_hex "$onfg") || onfg=ffffff
  read -r fr fg_ fb <<<"$(_livery_rgb "$onfg")" || return 1
  for k in "${_LIVERY_PROFILE_SLOTS[@]}"; do
    [[ -n ${_LIVERY_P[$k]:-} ]] && pairs+="$k:${_LIVERY_P[$k]} "
  done
  [[ -n $pairs ]] || return 1
  for k in "${_LIVERY_ON_COLOR_SLOTS[@]}"; do dual+="$k "; done
  # Channels go in as decimals: strtonum() is a GNU awk extension and mawk,
  # the default awk on many Debian/Ubuntu systems, lacks it.
  awk -v pairs="$pairs" -v br="$r" -v bgc="$g" -v bb="$b" -v floor="$floor" \
      -v dual="$dual" -v onfloor="$onfloor" -v fr="$fr" -v fg="$fg_" -v fb="$fb" '
    function h2d(x,   i,n,d){ n=0
      for(i=1;i<=length(x);i++){ d=index("0123456789abcdef",tolower(substr(x,i,1)))-1; n=n*16+d }
      return n }
    function chan(v){ v=v/255; return (v <= 0.03928) ? v/12.92 : ((v+0.055)/1.055)^2.4 }
    function lum(r,g,b){ return 0.2126*chan(r)+0.7152*chan(g)+0.0722*chan(b) }
    function ratio(r,g,b,   la,lb,t){ la=lum(r,g,b); lb=BGL
      if(la<lb){ t=la; la=lb; lb=t }
      return int(((la+0.05)/(lb+0.05))*100+0.5) }
    # Contrast of the light text a program puts *on* this colour, not of the
    # colour against the background.
    function onratio(r,g,b,   la,lb,t){ la=lum(r,g,b); lb=FGL
      if(la<lb){ t=la; la=lb; lb=t }
      return int(((la+0.05)/(lb+0.05))*100+0.5) }
    function rgb2hsl(r,g,b,   mx,mn,d,h,s,l){
      r=r/255; g=g/255; b=b/255
      mx=(r>g)?r:g; if(b>mx) mx=b
      mn=(r<g)?r:g; if(b<mn) mn=b
      l=(mx+mn)/2; d=mx-mn
      if(d==0){ h=0; s=0 }
      else{
        s=(l<0.5)? d/(mx+mn) : d/(2-mx-mn)
        if(mx==r)      h=(g-b)/d
        else if(mx==g) h=(b-r)/d+2
        else           h=(r-g)/d+4
        h=h*60; if(h<0) h=h+360
      }
      HH=h; SS=s*100; LL=l*100 }
    function hc(p,q,t){ if(t<0) t=t+1; if(t>1) t=t-1
      if(t<1/6) return p+(q-p)*6*t
      if(t<1/2) return q
      if(t<2/3) return p+(q-p)*(2/3-t)*6
      return p }
    function hsl2rgb(h,s,l,   q,p,r,g,b){    # sets RR GG BB
      h=h/360; s=s/100; l=l/100
      if(s==0){ r=l; g=l; b=l }
      else{
        q=(l<0.5)? l*(1+s) : l+s-l*s
        p=2*l-q
        r=hc(p,q,h+1/3); g=hc(p,q,h); b=hc(p,q,h-1/3)
      }
      RR=int(r*255+0.5); GG=int(g*255+0.5); BB=int(b*255+0.5) }
    function try(h,s,l,   rr){
      if(l<0) l=0; if(l>100) l=100
      hsl2rgb(h,s,l); rr=ratio(RR,GG,BB)
      CR=RR; CG=GG; CB=BB
      return rr }
    BEGIN{
      BGL=lum(br,bgc,bb)
      FGL=lum(fr,fg,fb)
      rgb2hsl(br,bgc,bb)
      # Move away from the background, not into it: the first direction tried is
      # the one with room. Both are tried at each distance, so a slot the
      # preferred direction cannot fix is still found.
      dir1=(LL<50)? 1 : -1
      nd=split(dual,D," ")
      for(i=1;i<=nd;i++) ISDUAL[D[i]]=1
      n=split(pairs,P," ")
      # ansi7 is the light text those two-sided slots have to hold, and this
      # pass can repair ansi7 itself. Solve it first and constrain against the
      # value that will actually render, not the profile value it is about to
      # stop being -- otherwise the slots are solved against one colour and
      # `livery test` measures them against another.
      for(i=1;i<=n;i++){
        split(P[i],kv,":")
        if(kv[1]!="ansi7") continue
        hex=kv[2]
        r0=h2d(substr(hex,1,2)); g0=h2d(substr(hex,3,2)); b0=h2d(substr(hex,5,2))
        if(ratio(r0,g0,b0)>=floor){ FGL=lum(r0,g0,b0); break }
        rgb2hsl(r0,g0,b0); h=HH; s=SS; l0=LL
        bestr=-1; bl=l0
        for(d=1; d<=100; d++){
          for(w=0; w<2; w++){
            l=l0 + d*((w==0)? dir1 : -dir1)
            if(l<0 || l>100) continue
            rr=try(h,s,l)
            if(rr>bestr){ bestr=rr; bl=l }
            if(rr>=floor){ FGL=lum(CR,CG,CB); d=101; w=2 }
          }
        }
        # Unreachable floor: ansi7 ends up at its best available value, so that
        # is the one to constrain against.
        if(bestr>=0 && bestr<floor){ try(h,s,bl); FGL=lum(CR,CG,CB) }
        break
      }
      for(i=1;i<=n;i++){
        split(P[i],kv,":"); key=kv[1]; hex=kv[2]
        r0=h2d(substr(hex,1,2)); g0=h2d(substr(hex,3,2)); b0=h2d(substr(hex,5,2))
        if(key in ISDUAL){
          # Two floors. Already clearing both means leave it at the profile.
          if(ratio(r0,g0,b0)>=floor && onratio(r0,g0,b0)>=onfloor) continue
          rgb2hsl(r0,g0,b0); h=HH; s=SS
          bestr=-1; bestc=""
          for(l=0; l<=100; l++){
            rr=try(h,s,l)
            if(onratio(CR,CG,CB) < onfloor) continue
            if(rr>bestr){ bestr=rr; bestc=sprintf("%02x%02x%02x",CR,CG,CB) }
          }
          # Nothing at this hue holds the text -- fall through to the one-sided
          # search rather than emit a colour chosen against no constraint.
          if(bestc!=""){ printf "%s %s %d\n", key, bestc, bestr; continue }
        }
        if(ratio(r0,g0,b0)>=floor) continue
        rgb2hsl(r0,g0,b0); h=HH; s=SS; l0=LL
        bestr=-1; bestc=""; done=0
        for(d=1; d<=100 && !done; d++){
          for(w=0; w<2 && !done; w++){
            l=l0 + d*((w==0)? dir1 : -dir1)
            if(l<0 || l>100) continue
            rr=try(h,s,l); cand=sprintf("%02x%02x%02x",CR,CG,CB)
            if(rr>bestr){ bestr=rr; bestc=cand }
            if(rr>=floor){ printf "%s %s %d\n", key, cand, rr; done=1 }
          }
        }
        # No lightness at this hue clears the floor. Emit the closest available
        # and let `livery test`/`audit` report it as still low, rather than
        # silently leaving the unreadable original in place.
        if(!done && bestc!="") printf "%s %s %d\n", key, bestc, bestr
      }
    }'
}

# -------------------------------------------------------------------- title ---
# The tab label comes from the terminal title. Setting it from PROMPT_COMMAND
# does not survive: a stock Ubuntu ~/.bashrc puts its own "\e]0;\u@\h: \w\a"
# inside PS1, which is emitted *after* PROMPT_COMMAND and overwrites it. So
# livery appends its own title escape to the end of PS1 instead -- the last
# title escape a prompt emits is the one that sticks -- and only updates a
# variable from the hook. This also means the title is reasserted on every
# prompt, so it comes back on its own after a program (Claude Code included)
# sets a title of its own.
_LIVERY_TITLE=

# PS1 undergoes parameter expansion, so keep the label free of anything that
# could expand or move the cursor.
_livery_safe_label() {
  # '/' and '~' are safe here: PS1 does parameter, command and arithmetic
  # expansion plus quote removal, but not tilde expansion or path handling.
  local v="${1//[^A-Za-z0-9._+~\/ -]/-}"
  printf '%s' "${v:0:40}"
}

_livery_install_title() {
  [[ -n ${PS1:-} ]] || return 0
  case "$PS1" in *_LIVERY_TITLE*) return 0 ;; esac      # already installed
  _LIVERY_PS1_ORIG="$PS1"
  PS1="$PS1"'\[\e]0;${_LIVERY_TITLE}\a\]'
  return 0
}

_livery_remove_title() {
  if [[ -n ${_LIVERY_PS1_ORIG:-} ]]; then
    PS1="$_LIVERY_PS1_ORIG"; _LIVERY_PS1_ORIG=
  fi
  return 0
}

# What the tab should say for the current directory.
_livery_set_title() {
  [[ $_LIVERY_O_title == on ]] || return 0
  local t="$1"
  if [[ -z $t ]]; then
    # not a project: the basename is what fits in a tab
    if   [[ $PWD == "$HOME" ]]; then t='~'
    elif [[ $PWD == / ]];      then t='/'
    else                            t="${PWD##*/}"
    fi
  fi
  _LIVERY_TITLE=$(_livery_safe_label "$t")
  return 0
}

# ------------------------------------------------------------------- config --
_livery_load_conf() {
  _livery_defaults
  _LIVERY_PATHS=(); _LIVERY_OPTS=()
  [[ -r $LIVERY_CONF ]] || return 0
  local kw a b rest
  while read -r kw a rest; do
    case "$kw" in
      ''|'#'*) continue ;;
      set)
        case "$a" in
          enable|mode|alpha|lightness|saturation|fade_ms|fade_steps|auto|auto_root|auto_lightness|auto_contrast|auto_min_contrast|title|default_bg|min_contrast|on_color_contrast)
            b=${rest%%[[:space:]]#*}; b=${b%"${b##*[![:space:]]}"}
            [[ $a == auto_root ]] && b=$(_livery_expand_tilde "$b")
            printf -v "_LIVERY_O_$a" '%s' "$b" ;;
          *) printf 'livery: unknown option "%s" in %s\n' "$a" "$LIVERY_CONF" >&2 ;;
        esac ;;
      rule)
        a=$(_livery_expand_tilde "$a"); a=${a%/}
        _LIVERY_PATHS+=("$a"); _LIVERY_OPTS+=("$rest") ;;
      *) printf 'livery: unknown directive "%s" in %s\n' "$kw" "$LIVERY_CONF" >&2 ;;
    esac
  done < "$LIVERY_CONF"

  # These reach bash arithmetic in the reporting paths, where a non-numeric
  # value is a syntax error rather than a warning. Check them once, here.
  local o d n v
  for o in lightness:10 saturation:70 alpha:18 fade_ms:260 fade_steps:16 \
           auto_lightness:18 min_contrast:700 auto_min_contrast:450 \
           on_color_contrast:300; do
    d=${o#*:}; n="_LIVERY_O_${o%%:*}"; v=${!n}
    if [[ ! $v =~ ^[0-9]+$ ]]; then
      printf 'livery: %s must be a number, got "%s" -- using %s\n' "${o%%:*}" "$v" "$d" >&2
      printf -v "$n" '%s' "$d"
    fi
  done
  for o in enable:on auto:on auto_contrast:on title:off; do
    d=${o#*:}; n="_LIVERY_O_${o%%:*}"; v=${!n}
    case "$v" in on|off) ;;
      *) printf 'livery: %s must be on|off, got "%s" -- using %s\n' "${o%%:*}" "$v" "$d" >&2
         printf -v "$n" '%s' "$d" ;;
    esac
  done
  case "$_LIVERY_O_mode" in dark|tint) ;;
    *) printf 'livery: mode must be dark|tint, got "%s" -- using dark\n' \
         "$_LIVERY_O_mode" >&2
       _LIVERY_O_mode=dark ;;
  esac
}

# --------------------------------------------------------- scheme resolution --
# Accents are hue sources only. Their own brightness is discarded: the derived
# background is the accent's hue pinned to `lightness`, so every project stays
# equally dark while remaining distinguishable.
_LIVERY_PALETTE=(e06c75 d19a66 e5c07b 98c379 56b6c2 61afef 7aa2f7 c678dd
                 d16d9e a0785a b5cea8 22d3ee f472b6 7f9cc0)

declare -A _LIVERY_T 2>/dev/null || true      # the resolved theme

# Auto colours live in their own lightness band, above the one configured
# projects use. Competing for hues does not work: at a shared lightness the
# perceptual difference between two dark colours is dominated by lightness, so
# an auto colour 20 degrees of hue away from a client still reads as the same
# colour. Separating by lightness instead puts every auto colour clear of every
# configured one, and makes "lighter" mean "not one of the projects I named".
_LIVERY_AUTO_HUES=(0 20 40 60 80 100 120 140 160 180 200 220 240 260 280 300 320 340)

_livery_auto_accent() {   # stable name -> a hue from the ring
  local n; n=$(cksum <<<"$1"); n=${n%% *}
  _livery_hsl_to_hex "${_LIVERY_AUTO_HUES[$(( n % ${#_LIVERY_AUTO_HUES[@]} ))]}" 55 50
}

_livery_is_color_key() {
  case "$1" in
    bg|fg|cursor|bold) return 0 ;;
    ansi[0-9]|ansi1[0-5]) return 0 ;;
    *) return 1 ;;
  esac
}
_livery_is_theme_key() {
  _livery_is_color_key "$1" && return 0
  case "$1" in accent|lightness|saturation|alpha) return 0 ;; *) return 1 ;; esac
}

_livery_theme_file() { printf '%s/%s.conf' "$LIVERY_THEMES" "$1"; }

# Load a theme file into _LIVERY_T. Parsed, never sourced; unknown keys warn.
_livery_load_theme() {
  local name="$1" f k v
  f=$(_livery_theme_file "$name")
  if [[ ! -r $f ]]; then
    printf 'livery: no theme "%s" (looked in %s)\n' "$name" "$f" >&2
    return 1
  fi
  while read -r k v _; do
    # read -r k v _ already discards any trailing comment into _, so v must NOT
    # be comment-stripped here: every colour value starts with '#'.
    [[ -z $k || $k == '#'* ]] && continue
    [[ -z $v ]] && continue
    if _livery_is_theme_key "$k"; then _LIVERY_T[$k]="$v"
    else printf 'livery: theme %s: unknown key "%s"\n' "$name" "$k" >&2; fi
  done < "$f"
  return 0
}

# Resolve $1 (a directory) -> fills _LIVERY_T and _LIVERY_R_*
_livery_resolve() {
  local dir="$1" i best=-1 bestlen=-1 p
  _LIVERY_T=()
  _LIVERY_R_label= _LIVERY_R_fade_ms="$_LIVERY_O_fade_ms" _LIVERY_R_theme=
  _LIVERY_R_auto= _LIVERY_R_repaired= _LIVERY_R_profile_unknown=

  for i in "${!_LIVERY_PATHS[@]}"; do            # longest-prefix wins
    p="${_LIVERY_PATHS[i]}"
    if [[ $dir == "$p" || $dir == "$p"/* ]] && (( ${#p} > bestlen )); then
      best=$i; bestlen=${#p}
    fi
  done

  local -a opts=()
  local label= accent= kv k v is_auto=
  if (( best >= 0 )); then
    label="${_LIVERY_PATHS[best]##*/}"
    read -r -a opts <<<"${_LIVERY_OPTS[best]}"
  elif [[ $_LIVERY_O_auto == on && -n $_LIVERY_O_auto_root && $dir == "$_LIVERY_O_auto_root"/* ]]; then
    label="${dir#"$_LIVERY_O_auto_root"/}"; label="${label%%/*}"
    accent=$(_livery_auto_accent "$label"); is_auto=1; _LIVERY_R_auto=1
  else
    return 1                                     # no scheme: caller resets
  fi

  # A theme file provides the base; inline rule keys override it. The two are
  # tracked separately because the background has its own precedence: a shared
  # theme supplies the text palette while each project's accent supplies the
  # background hue, so an inline accent must beat the theme's own bg. Otherwise
  # every project using one theme would end up the same colour.
  local theme_bg= theme_accent= inline_bg= inline_accent=
  for kv in "${opts[@]}"; do
    [[ $kv == '#'* ]] && break
    [[ ${kv%%=*} == theme ]] && { _LIVERY_R_theme="${kv#*=}"; _livery_load_theme "$_LIVERY_R_theme" || return 1; }
  done
  theme_bg="${_LIVERY_T[bg]:-}"; theme_accent="${_LIVERY_T[accent]:-}"
  for kv in "${opts[@]}"; do
    [[ $kv == '#'* ]] && break
    k=${kv%%=*}; v=${kv#*=}
    case "$k" in
      theme) ;;
      fade_ms) _LIVERY_R_fade_ms=$v ;;
      label)   label=$v ;;
      bg)      inline_bg=$v;     _LIVERY_T[bg]="$v" ;;
      accent)  inline_accent=$v; _LIVERY_T[accent]="$v" ;;
      *) if _livery_is_theme_key "$k"; then _LIVERY_T[$k]="$v"
         else printf 'livery: unknown rule key "%s" for %s\n' "$k" "$label" >&2; fi ;;
    esac
  done

  local light="${_LIVERY_T[lightness]:-${is_auto:+$_LIVERY_O_auto_lightness}}"
  light="${light:-$_LIVERY_O_lightness}"
  local satcap="${_LIVERY_T[saturation]:-$_LIVERY_O_saturation}"
  local alpha="${_LIVERY_T[alpha]:-$_LIVERY_O_alpha}"
  # Percentages, so bound them. An out-of-range alpha produced a wider-than-six
  # digit "colour" that normalisation then dropped, which used to leave the
  # previous project's background in place.
  [[ $light  =~ ^[0-9]+$ ]] || light=10
  [[ $satcap =~ ^[0-9]+$ ]] || satcap=70
  [[ $alpha  =~ ^[0-9]+$ ]] || alpha=18
  (( light  > 100 )) && light=100
  (( satcap > 100 )) && satcap=100
  (( alpha  > 100 )) && alpha=100

  # background precedence, highest first:
  #   inline bg  >  inline accent  >  theme bg  >  theme accent  >  auto accent
  local use_accent=
  if   [[ -n $inline_bg     ]]; then _LIVERY_T[bg]="$inline_bg"
  elif [[ -n $inline_accent ]]; then use_accent=$inline_accent
  elif [[ -n $theme_bg      ]]; then _LIVERY_T[bg]="$theme_bg"
  elif [[ -n $theme_accent  ]]; then use_accent=$theme_accent
  elif [[ -n $accent        ]]; then use_accent=$accent
  fi
  if [[ -n $use_accent ]]; then
    if [[ $_LIVERY_O_mode == tint ]]; then
      local dbg; dbg=$(_livery_default_bg) || return 1
      _LIVERY_T[bg]=$(_livery_blend "$dbg" "$use_accent" "$alpha") || return 1
    else
      _LIVERY_T[bg]=$(_livery_at_lightness "$use_accent" "$light" "$satcap") || return 1
    fi
  fi

  # An auto project has no rule to override the prompt colours, so the profile
  # palette is what it gets -- and a background it never chose can push that
  # palette below legibility. Repair the slots this background breaks, leaving
  # the rest reset to the profile. Configured rules are untouched: they name
  # their own colours and `livery audit` measures them.
  if [[ -n $is_auto && $_LIVERY_O_auto_contrast == on && -n ${_LIVERY_T[bg]:-} ]]; then
    local floor="$_LIVERY_O_auto_min_contrast" rk rv rr
    [[ $floor =~ ^[0-9]+$ ]] || floor=450
    if _livery_load_profile_cache; then
      while read -r rk rv rr; do
        [[ -z $rk || -n ${_LIVERY_T[$rk]:-} ]] && continue
        _LIVERY_T[$rk]="$rv"
        _LIVERY_R_repaired+="$rk "
      done < <(_livery_repair_palette "${_LIVERY_T[bg]}" "$floor")
    else
      _LIVERY_R_profile_unknown=1
    fi
  fi

  # normalise every colour; drop and warn on anything unparseable
  local norm
  for k in bg fg cursor bold ansi0 ansi1 ansi2 ansi3 ansi4 ansi5 ansi6 ansi7 \
           ansi8 ansi9 ansi10 ansi11 ansi12 ansi13 ansi14 ansi15; do
    v="${_LIVERY_T[$k]:-}"
    [[ -z $v ]] && continue
    if norm=$(_livery_hex "$v"); then _LIVERY_T[$k]="$norm"
    else printf 'livery: bad colour "%s" for %s in %s\n' "$v" "$k" "${label:-?}" >&2
         unset "_LIVERY_T[$k]"; fi
  done
  unset '_LIVERY_T[accent]' '_LIVERY_T[lightness]' '_LIVERY_T[saturation]' '_LIVERY_T[alpha]'

  [[ $_LIVERY_R_fade_ms =~ ^[0-9]+$ ]] || _LIVERY_R_fade_ms="$_LIVERY_O_fade_ms"
  _LIVERY_R_label="$label"
  return 0
}

# ------------------------------------------------------------------- apply ----
_livery_fade_bg() {   # from -> to over fade_steps / $3 ms
  local from="$1" to="$2" ms="$3" n="$_LIVERY_O_fade_steps" s c
  [[ $n =~ ^[0-9]+$ ]] || n=16
  if [[ -z $from || $n -le 1 || $ms -le 0 ]]; then _livery_emit "$(_livery_osc "11;#$to")"; return 0; fi
  local per=$(( ms / n )); (( per < 1 )) && per=1
  for (( s=1; s<=n; s++ )); do
    c=$(_livery_lerp "$from" "$to" "$s" "$n") || break
    _livery_emit "$(_livery_osc "11;#$c")"
    (( s < n )) && _livery_msleep "$per"
  done
  _livery_emit "$(_livery_osc "11;#$to")"    # land exactly on target
  return 0
}

# Everything except the background is applied in one write, before the fade, so
# text is never rendered against a half-transitioned palette.
_livery_emit_theme_except_bg() {
  local out= i k
  # Every slot this theme does not define is RESET, not left alone. Emitting
  # only the keys present would let a partial theme inherit the previous
  # project's foreground and palette, which is both wrong and invisible.
  # Reset and set go out in one write, so the terminal never renders between.
  if [[ -n ${_LIVERY_T[fg]:-} ]];     then out+=$(_livery_osc "10;#${_LIVERY_T[fg]}")
  else                                     out+=$(_livery_osc 110); fi
  if [[ -n ${_LIVERY_T[cursor]:-} ]]; then out+=$(_livery_osc "12;#${_LIVERY_T[cursor]}")
  else                                     out+=$(_livery_osc 112); fi
  if [[ -n ${_LIVERY_T[bold]:-} ]];   then out+=$(_livery_osc "5;0;#${_LIVERY_T[bold]}")
  else                                     out+=$(_livery_osc 105); fi
  out+=$(_livery_osc 104)                  # whole palette back to profile first
  for i in {0..15}; do
    k="ansi$i"
    [[ -n ${_LIVERY_T[$k]:-} ]] && out+=$(_livery_osc "4;$i;#${_LIVERY_T[$k]}")
  done
  _livery_emit "$out"
  return 0
}

_livery_apply() {
  local dir="$1"
  if _livery_resolve "$dir"; then
    _livery_emit_theme_except_bg
    local bg="${_LIVERY_T[bg]:-}" dbg
    if [[ -n $bg ]]; then
      if [[ $bg != "${_LIVERY_CUR_BG:-}" ]]; then
        _livery_fade_bg "${_LIVERY_CUR_BG:-$(_livery_default_bg)}" "$bg" "$_LIVERY_R_fade_ms"
        _LIVERY_CUR_BG="$bg"
      fi
    elif [[ -n ${_LIVERY_CUR_BG:-} ]]; then
      # This scheme names no background -- a foreground-only rule, or one whose
      # background was dropped as unparseable. That means the profile's own
      # background, not whatever the previous project left behind.
      if dbg=$(_livery_default_bg); then
        _livery_fade_bg "$_LIVERY_CUR_BG" "$dbg" "$_LIVERY_R_fade_ms"
      fi
      _livery_emit "$(_livery_osc 111)"
      _LIVERY_CUR_BG=
    fi
    _livery_set_title "$_LIVERY_R_label"
    _LIVERY_LABEL="$_LIVERY_R_label"
  else
    _livery_reset
  fi
  return 0
}

_livery_reset() {
  local dbg
  if [[ -n ${_LIVERY_CUR_BG:-} ]] && dbg=$(_livery_default_bg); then
    _livery_fade_bg "$_LIVERY_CUR_BG" "$dbg" "$_LIVERY_O_fade_ms"
  fi
  # 104 = whole ANSI palette, 105 = bold, 110/111/112 = fg/bg/cursor
  _livery_emit "$(_livery_osc 104)$(_livery_osc 105)$(_livery_osc 110)$(_livery_osc 111)$(_livery_osc 112)"
  _LIVERY_CUR_BG= ; _LIVERY_LABEL=
  _livery_set_title ''
  return 0
}

# -------------------------------------------------------------------- hook ----
_livery_hook() {
  [[ $_LIVERY_O_enable == on ]] || return 0
  [[ $PWD == "${_LIVERY_LAST_PWD:-}" ]] && return 0
  _LIVERY_LAST_PWD="$PWD"
  _livery_apply "$PWD"
  return 0
}

# ------------------------------------------------------------------- livery CLI --
_livery_ratio_fmt() {           # ratio x100 -> "N.NN"
  printf '%s.%02s' "$(( ${1:-0} / 100 ))" "$(printf '%02d' $(( ${1:-0} % 100 )))"
}

# One colour row: key, value, measured contrast against the background, and a
# flag when it falls under the threshold that applies to it.
_livery_report_row() {          # key hex bg threshold [note]
  local k="$1" v="$2" bg="$3" thr="$4" note="${5:-}" ratio flag= onr= oncol=
  if [[ -z $bg || $k == bg ]]; then
    printf '  %-8s #%s%s\n' "$k" "$v" "$note"; return 0
  fi
  ratio=$(_livery_contrast "$v" "$bg" 2>/dev/null)
  # Each slot is judged against the floor that governs it. ansi0/ansi8 are
  # structural -- dim text and box drawing, not body text -- so no readability
  # threshold applies. A two-sided slot is governed by the on-colour floor
  # instead: the two pull opposite ways, and holding the text a program puts on
  # it is the constraint that cannot be met any other way. Its text figure is
  # still printed, just not held to the text threshold, the same way a
  # structural slot's is.
  case "$k" in
    ansi0|ansi8) flag='  (structural)' ;;
    *) if _livery_is_on_color_slot "$k"; then flag='  (two-sided)'
       else (( ${ratio:-0} < thr )) && flag='  LOW'; fi ;;
  esac
  # A slot programs paint as a background is measured in that role too: the
  # figure above is the colour against the background, this one is the light
  # text a program puts on the colour. Reporting only the first is how an
  # illegible `\e[37;41m` error block measured clean.
  if _livery_is_on_color_slot "$k"; then
    onr=$(_livery_contrast "$v" "$(_livery_on_color_fg)" 2>/dev/null)
    oncol="   text on it $(_livery_ratio_fmt "${onr:-0}"):1"
    (( ${onr:-0} < _LIVERY_O_on_color_contrast )) && flag+=' LOW-ON-COLOUR'
  fi
  printf '  %-8s #%s   contrast vs bg %s:1%s%s%s\n' \
    "$k" "$v" "$(_livery_ratio_fmt "${ratio:-0}")" "$oncol" "$note" "$flag"
}

_livery_report_theme() {        # print the resolved theme with contrast figures
  local k v bg thr note nrep=0 nprof=0
  bg="${_LIVERY_T[bg]:-}"
  printf '  %-8s %s\n' 'label' "${_LIVERY_R_label:-<none>}"
  [[ -n ${_LIVERY_R_theme:-} ]] && printf '  %-8s %s\n' 'theme' "$_LIVERY_R_theme"

  # An auto project is measured against the floor livery repairs to, not against
  # min_contrast: min_contrast is the target for themes written by hand, and
  # nothing here was written by hand.
  thr="$_LIVERY_O_min_contrast"
  if [[ -n ${_LIVERY_R_auto:-} && $_LIVERY_O_auto_contrast == on ]]; then
    thr="$_LIVERY_O_auto_min_contrast"
    for k in $_LIVERY_R_repaired; do nrep=$((nrep+1)); done
    for k in "${_LIVERY_PROFILE_SLOTS[@]}"; do
      [[ -n ${_LIVERY_P[$k]:-} && -z ${_LIVERY_T[$k]:-} ]] && nprof=$((nprof+1))
    done
    if [[ -n ${_LIVERY_R_profile_unknown:-} ]]; then
      printf '  %-8s the profile palette is unknown, so nothing was repaired --\n' 'auto'
      printf '  %-8s run "livery forget" in a terminal that answers OSC 4.\n' ''
    else
      printf '  %-8s contrast floor %s:1  (%s slots repaired, %s left at the profile'"'"'s own)\n' \
        'auto' "$(_livery_ratio_fmt "$thr")" "$nrep" "$nprof"
    fi
  fi

  for k in bg fg cursor bold ansi0 ansi1 ansi2 ansi3 ansi4 ansi5 ansi6 ansi7 \
           ansi8 ansi9 ansi10 ansi11 ansi12 ansi13 ansi14 ansi15; do
    v="${_LIVERY_T[$k]:-}"
    if [[ -n $v ]]; then
      note=
      case " $_LIVERY_R_repaired " in
        *" $k "*) note="  (repaired from #${_LIVERY_P[$k]})" ;;
      esac
      _livery_report_row "$k" "$v" "$bg" "$thr" "$note"
    elif [[ -n ${_LIVERY_R_auto:-} && -n ${_LIVERY_P[$k]:-} ]]; then
      # Left alone, so it is whatever the profile says. Measured all the same:
      # unmeasured is how the unreadable slots went unnoticed.
      _livery_report_row "$k" "${_LIVERY_P[$k]}" "$bg" "$thr" '  (profile)'
    fi
  done
}

livery() {
  case "${1:-status}" in
    status)
      printf 'config   : %s%s\n' "$LIVERY_CONF" "$( [[ -r $LIVERY_CONF ]] || printf ' (missing)' )"
      printf 'themes   : %s (%s found)\n' "$LIVERY_THEMES" \
        "$(ls -1 "$LIVERY_THEMES"/*.conf 2>/dev/null | wc -l)"
      printf 'enable   : %s   mode=%s lightness=%s sat<=%s fade=%sms/%s  auto=%s title=%s\n' \
        "$_LIVERY_O_enable" "$_LIVERY_O_mode" "$_LIVERY_O_lightness" "$_LIVERY_O_saturation" \
        "$_LIVERY_O_fade_ms" "$_LIVERY_O_fade_steps" "$_LIVERY_O_auto" "$_LIVERY_O_title"
      printf 'auto_root: %s   auto_contrast=%s floor=%s.%02s:1\n' "$_LIVERY_O_auto_root" \
        "$_LIVERY_O_auto_contrast" "$(( _LIVERY_O_auto_min_contrast / 100 ))" \
        "$(printf '%02d' $(( _LIVERY_O_auto_min_contrast % 100 )))"
      if [[ $_LIVERY_O_auto == on && $_LIVERY_O_auto_contrast == on ]]; then
        if (( ${#_LIVERY_P[@]} )); then
          printf 'palette  : %s of %s profile slots known (%s)\n' \
            "${#_LIVERY_P[@]}" "${#_LIVERY_PROFILE_SLOTS[@]}" "$(_livery_profile_cache)"
        else
          printf 'palette  : unknown -- the terminal did not answer; auto projects keep\n'
          printf '           the profile palette unrepaired. Run "livery forget" to retry.\n'
        fi
      fi
      printf 'rules    : %s\n' "${#_LIVERY_PATHS[@]}"
      printf 'default  : %s\n' "$(_livery_fmt "${_LIVERY_DEFAULT_BG:-}" '<unknown - query failed>')"
      printf 'current  : %s\n' "$(_livery_fmt "${_LIVERY_CUR_BG:-}")"
      local live; live=$(_livery_query_bg)
      printf 'live bg  : %s  (read back from the terminal)\n' "$(_livery_fmt "$live" '<no reply>')"
      if [[ -z ${_LIVERY_CUR_BG:-} && -n $live && -n ${_LIVERY_DEFAULT_BG:-} && $live != "$_LIVERY_DEFAULT_BG" ]]; then
        printf 'warning  : cached default #%s but terminal reports #%s.\n' "$_LIVERY_DEFAULT_BG" "$live"
        printf '           run "livery forget", or pin "set default_bg #%s" in the config.\n' "$live"
      fi
      printf 'project  : %s\n' "${_LIVERY_LABEL:-<none>}"
      ;;
    test)
      local d="${2:-$PWD}"; d=$(_livery_expand_tilde "$d")
      if _livery_resolve "$d"; then
        printf '%s\n' "$d"
        _livery_report_theme
        printf '  %-8s %sms\n' 'fade' "$_LIVERY_R_fade_ms"
      else
        printf '%s -> no scheme (would reset to defaults)\n' "$d"
      fi
      ;;
    themes)
      if compgen -G "$LIVERY_THEMES/*.conf" >/dev/null 2>&1; then
        local f
        for f in "$LIVERY_THEMES"/*.conf; do
          printf '%-24s %s\n' "$(basename "$f" .conf)" "$f"
        done
      else
        printf 'no themes in %s\n' "$LIVERY_THEMES"
      fi
      ;;
    doctor)
      printf 'Probing terminal capabilities (TERM=%s VTE=%s)\n\n' "$TERM" "${VTE_VERSION:-none}"
      local before after name code idx
      _livery_probe() {   # name code [index]
        local nm="$1" cd="$2" ix="${3:-}" b a ok
        b=$(_livery_query_color "$cd" "$ix")
        if [[ -z $b ]]; then printf '  %-22s no reply to query\n' "$nm"; return; fi
        if [[ -n $ix ]]; then _livery_emit "$(_livery_osc "$cd;$ix;#123456")"
        else                  _livery_emit "$(_livery_osc "$cd;#123456")"; fi
        _livery_msleep 120
        a=$(_livery_query_color "$cd" "$ix")
        if [[ -n $ix ]]; then _livery_emit "$(_livery_osc "$cd;$ix;#$b")"
        else                  _livery_emit "$(_livery_osc "$cd;#$b")"; fi
        [[ $a == 123456 ]] && ok=yes || ok="NO (read back #$a)"
        printf '  %-22s was #%s  settable: %s\n' "$nm" "$b" "$ok"
      }
      _livery_probe 'background (OSC 11)' 11
      _livery_probe 'foreground (OSC 10)' 10
      _livery_probe 'cursor (OSC 12)'     12
      _livery_probe 'ansi 1 (OSC 4;1)'    4 1
      _livery_probe 'ansi 4 (OSC 4;4)'    4 4
      _livery_probe 'ansi 12 (OSC 4;12)'  4 12
      unset -f _livery_probe

      # Setting a colour proves nothing about restoring it. Capture the live
      # values, reset, and check they actually moved back.
      # Proving a reset works needs a value the reset must visibly clear. A
      # before/after comparison cannot: for a theme that never set the palette,
      # the slots are already at their defaults, so "unchanged" is a success
      # and looks identical to failure. Plant a sentinel, then reset.
      printf '\n  reset check (OSC 104/110/111/112)\n'
      local sent='123456' nm code idx pre post
      for nm in 'background:11:' 'ansi 1:4:1' 'ansi 4:4:4'; do
        code=$(printf '%s' "$nm" | cut -d: -f2); idx=$(printf '%s' "$nm" | cut -d: -f3)
        pre=$(_livery_query_color "$code" "$idx")
        if [[ -z $pre ]]; then printf '  %-22s no reply; cannot test\n' "${nm%%:*}"; continue; fi
        if [[ -n $idx ]]; then _livery_emit "$(_livery_osc "$code;$idx;#$sent")"
        else                   _livery_emit "$(_livery_osc "$code;#$sent")"; fi
        _livery_msleep 120
        if [[ $(_livery_query_color "$code" "$idx") != "$sent" ]]; then
          printf '  %-22s could not set the sentinel; skipped\n' "${nm%%:*}"
          if [[ -n $idx ]]; then _livery_emit "$(_livery_osc "$code;$idx;#$pre")"
          else                   _livery_emit "$(_livery_osc "$code;#$pre")"; fi
          continue
        fi
        _LIVERY_CUR_BG= ; _livery_reset
        _livery_msleep 120
        post=$(_livery_query_color "$code" "$idx")
        if [[ -z $post ]];          then printf '  %-22s no reply after reset\n' "${nm%%:*}"
        elif [[ $post == "$sent" ]]; then printf '  %-22s sentinel survived -- reset does NOT work\n' "${nm%%:*}"
        else                              printf '  %-22s sentinel cleared -> #%s  restored\n' "${nm%%:*}" "$post"
        fi
      done
      printf '\n  if the colours below look like your normal profile, resets work:\n'
      printf '    \033[0;31mred\033[0m \033[0;32mgreen\033[0m \033[0;34mblue\033[0m \033[1;32mbold green\033[0m \033[1;34mbold blue\033[0m\n'
      # doctor is a diagnostic, not a state change: put the project's scheme
      # back. Without clearing _LIVERY_LAST_PWD the hook would return early on
      # the next prompt and leave the terminal on profile defaults.
      _LIVERY_LAST_PWD=; _livery_hook
      ;;
    audit)
      # Check every project at once: contrast of each colour against its own
      # background, and how far apart the backgrounds are perceptually.
      # Run this after adding a client, rather than trusting that it looks fine.
      #
      # Auto projects are included. Leaving them out is how a 1.17:1 prompt
      # colour survived: a rule's colours are written down and get measured,
      # while an auto project's come from the terminal profile and used to be
      # measured nowhere at all.
      local i p k v ratio bgs=() names=() kinds=()
      local rworst=99999 rwhat= rlow=0 rmeas=0
      local aworst=99999 awhat= alow=0 ameas=0
      # The background role is tracked separately from the text role. They pull
      # opposite ways, so one worst-case figure covering both would report a
      # palette as fine when half of it is unreadable.
      local oworst=99999 owhat= olow=0 omeas=0
      local -a autodirs=()

      _livery_audit_slots() {   # accumulate stats for the resolved project
        local kind="$1" nm="$2" bg="$3" thr="$4" kk vv rr oo
        for kk in fg bold cursor ansi1 ansi2 ansi3 ansi4 ansi5 ansi6 ansi7 \
                  ansi9 ansi10 ansi11 ansi12 ansi13 ansi14 ansi15; do
          vv="${_LIVERY_T[$kk]:-}"
          # An auto project's unrepaired slots are the profile's own. They are
          # what actually renders, so they are what has to be measured.
          [[ -z $vv && $kind == auto ]] && vv="${_LIVERY_P[$kk]:-}"
          [[ -z $vv ]] && continue
          # A two-sided slot is measured in the role that governs it -- the
          # light text that lands on it -- and kept out of the text tallies.
          # Counting it in both would report every project as failing a floor
          # it cannot reach, burying the ones that are genuinely broken.
          if _livery_is_on_color_slot "$kk"; then
            if oo=$(_livery_contrast "$vv" "$(_livery_on_color_fg)"); then
              omeas=$((omeas+1))
              (( oo < oworst )) && { oworst=$oo; owhat="$kk on $nm"; }
              (( oo < _LIVERY_O_on_color_contrast )) && olow=$((olow+1))
            fi
            continue
          fi
          rr=$(_livery_contrast "$vv" "$bg") || continue
          if [[ $kind == auto ]]; then
            ameas=$((ameas+1))
            (( rr < aworst )) && { aworst=$rr; awhat="$kk on $nm"; }
            (( rr < thr )) && alow=$((alow+1))
          else
            rmeas=$((rmeas+1))
            (( rr < rworst )) && { rworst=$rr; rwhat="$kk on $nm"; }
            (( rr < thr )) && rlow=$((rlow+1))
          fi
        done
      }

      printf '  configured rules\n'
      for i in "${!_LIVERY_PATHS[@]}"; do
        p="${_LIVERY_PATHS[i]}"
        _livery_resolve "$p" || continue
        local bg="${_LIVERY_T[bg]:-}"
        [[ -z $bg ]] && continue
        local nm="${_LIVERY_R_label:-$p}"
        names+=("$nm"); bgs+=("$bg"); kinds+=(rule)
        _livery_audit_slots rule "$nm" "$bg" "$_LIVERY_O_min_contrast"
        printf '    %-22s bg #%s\n' "$nm" "$bg"
      done

      if [[ $_LIVERY_O_auto == on && -n $_LIVERY_O_auto_root ]]; then
        printf '\n  auto projects under %s\n' "$_LIVERY_O_auto_root"
        if [[ $_LIVERY_O_auto_contrast == on ]] && ! _livery_load_profile_cache; then
          printf '    the profile palette is unknown, so the colours these actually\n'
          printf '    render with cannot be measured. Run "livery forget" in a\n'
          printf '    terminal that answers OSC 4, then audit again.\n'
        fi
        while IFS= read -r p; do autodirs+=("$p"); done < <(
          shopt -s nullglob
          for p in "$_LIVERY_O_auto_root"/*/; do printf '%s\n' "${p%/}"; done | sort
        )
        if (( ${#autodirs[@]} == 0 )); then
          printf '    none found\n'
        fi
        # There are typically far more auto projects than rules, and they have
        # no hand-written colours to inspect -- so only the ones with something
        # to report are listed. A clean auto project is a count, not a line.
        local aclean=0 arepaired=0
        for p in "${autodirs[@]}"; do
          _livery_resolve "$p" || continue
          # A directory under auto_root that has its own rule is a configured
          # project and was listed above; resolve reports which it got.
          [[ -n ${_LIVERY_R_auto:-} ]] || continue
          local bg="${_LIVERY_T[bg]:-}"
          [[ -z $bg ]] && continue
          local nm="${_LIVERY_R_label:-$p}"
          names+=("$nm"); bgs+=("$bg"); kinds+=(auto)
          local lowbefore=$alow nrep=0
          _livery_audit_slots auto "$nm" "$bg" "$_LIVERY_O_auto_min_contrast"
          for k in $_LIVERY_R_repaired; do nrep=$((nrep+1)); done
          arepaired=$((arepaired+nrep))
          if (( alow > lowbefore )); then
            printf '    %-22s bg #%s   %s repaired, %s STILL BELOW THE FLOOR\n' \
              "$nm" "$bg" "$nrep" "$(( alow - lowbefore ))"
          else
            aclean=$((aclean+1))
          fi
        done
        printf '    %s clear the floor with %s slots repaired between them\n' \
          "$aclean" "$arepaired"
      fi
      unset -f _livery_audit_slots

      printf '\n  %s projects with a background\n' "${#bgs[@]}"
      if (( rmeas == 0 )); then
        printf '  rules, lowest text  : n/a (no text colours in any rule)\n'
      else
        printf '  rules, lowest text  : %s:1  (%s)   target %s:1\n' \
          "$(_livery_ratio_fmt "$rworst")" "$rwhat" "$(_livery_ratio_fmt "$_LIVERY_O_min_contrast")"
      fi
      printf '  rules below target  : %s\n' "$rlow"
      if (( ameas > 0 )); then
        printf '  auto,  lowest text  : %s:1  (%s)   floor  %s:1\n' \
          "$(_livery_ratio_fmt "$aworst")" "$awhat" "$(_livery_ratio_fmt "$_LIVERY_O_auto_min_contrast")"
        printf '  auto below floor    : %s\n' "$alow"
      fi
      # The other role: ansi1/ansi4/ansi5 painted as a background, measured
      # against the light text a program puts on them -- `\e[37;41m`, which is
      # what composer and drush print an error block with.
      if (( omeas > 0 )); then
        printf '  lowest text ON a slot: %s:1  (%s)   floor  %s:1\n' \
          "$(_livery_ratio_fmt "$oworst")" "$owhat" \
          "$(_livery_ratio_fmt "$_LIVERY_O_on_color_contrast")"
        printf '  slots below that     : %s of %s\n' "$olow" "$omeas"
      fi
      # Two separations matter, and they are not the same question. Between
      # rules: whether two projects you named look alike. Between an auto
      # project and a rule: whether "lighter" still means "not one I named".
      #
      # Auto projects are not compared with each other. The hue ring has 18
      # entries at one lightness, so with more auto projects than that,
      # collisions are arithmetic rather than a defect -- reporting dE 0.0 as
      # the headline figure would bury both numbers that do mean something.
      local rdec= adec= rnm=() anm=() abgs=() r g b
      for i in "${!bgs[@]}"; do
        read -r r g b <<<"$(_livery_rgb "${bgs[i]}")"
        if [[ ${kinds[i]} == auto ]]; then
          adec+="$r $g $b "; anm+=("${names[i]}"); abgs+=("${bgs[i]}")
        else
          rdec+="$r $g $b "; rnm+=("${names[i]}")
        fi
      done
      if (( ${#rnm[@]} > 1 || (${#rnm[@]} > 0 && ${#anm[@]} > 0) )); then
        # Perceptual distance in CIELAB. Channels are converted to decimals here
        # so the awk stays portable: strtonum() is GNU-only and mawk lacks it.
        awk -v rd="$rdec" -v ad="$adec" -v rn="${rnm[*]}" -v an="${anm[*]}" '
          function f(v){ v=v/255; return (v<=0.04045)? v/12.92 : ((v+0.055)/1.055)^2.4 }
          function cb(t){ return (t>0.008856)? t^(1/3) : 7.787*t+16/116 }
          function lab(d,L,A,B,   n,c,i,k,r,g,b,X,Y,Z,fy){
            n=split(d,c," "); k=0
            for(i=1;i<=n;i+=3){
              k++
              r=f(c[i]); g=f(c[i+1]); b=f(c[i+2])
              X=(0.4124*r+0.3576*g+0.1805*b)/0.95047
              Y=(0.2126*r+0.7152*g+0.0722*b)
              Z=(0.0193*r+0.1192*g+0.9505*b)/1.08883
              fy=cb(Y); L[k]=116*fy-16; A[k]=500*(cb(X)-fy); B[k]=200*(fy-cb(Z))
            }
            return k }
          function de(i,j,L1,A1,B1,L2,A2,B2){
            return sqrt((L1[i]-L2[j])^2+(A1[i]-A2[j])^2+(B1[i]-B2[j])^2) }
          BEGIN{
            nr=lab(rd,RL,RA,RB); na=lab(ad,AL,AA,AB)
            split(rn,rq," "); split(an,aq," ")
            best=1e9
            for(i=1;i<=nr;i++) for(j=i+1;j<=nr;j++){
              e=de(i,j,RL,RA,RB,RL,RA,RB); if(e<best){best=e; bi=rq[i]; bj=rq[j]} }
            if(nr>1) printf "  closest two rules   : dE %.1f  (%s vs %s)\n", best, bi, bj
            best=1e9
            for(i=1;i<=na;i++) for(j=1;j<=nr;j++){
              e=de(i,j,AL,AA,AB,RL,RA,RB); if(e<best){best=e; bi=aq[i]; bj=rq[j]} }
            if(na>0 && nr>0) printf "  closest auto to rule: dE %.1f  (%s vs %s)\n", best, bi, bj
          }'
      fi
      if (( ${#anm[@]} > 0 )); then
        local ndistinct
        ndistinct=$(printf '%s\n' "${abgs[@]}" | sort -u | wc -l)
        printf '  auto colours in use : %s distinct across %s projects (%s on the ring)\n' \
          "$ndistinct" "${#anm[@]}" "${#_LIVERY_AUTO_HUES[@]}"
      fi
      ;;
    suggest)
      # Automates the allocation done by hand for every project so far: rotate a
      # brand hue clear of what is already configured, pick a lightness that is
      # perceptually distinct, and solve the two prompt slots for contrast.
      local target="${2:-}" brand="${3:-}"
      if [[ -z $target ]]; then
        printf 'usage: livery suggest <dir> [#brandcolour]\n'; return 1
      fi
      target=$(_livery_expand_tilde "$target"); target=${target%/}
      local i p bg exbg=() exnm=()
      for i in "${!_LIVERY_PATHS[@]}"; do
        p="${_LIVERY_PATHS[i]}"
        [[ $p == "$target" ]] && printf 'note: %s already has a rule\n\n' "$target"
        _livery_resolve "$p" || continue
        [[ -n ${_LIVERY_T[bg]:-} ]] && { exbg+=("${_LIVERY_T[bg]}"); exnm+=("${_LIVERY_R_label:-$p}"); }
      done

      local bhue=-1
      if [[ -n $brand ]]; then
        local bh; bh=$(_livery_hex "$brand") || { printf 'livery: bad colour "%s"\n' "$brand" >&2; return 1; }
        read -r bhue _ _ <<<"$(_livery_rgb_to_hsl "$bh")"
      fi

      printf 'searching hues and lightnesses against %s configured backgrounds...\n' "${#exbg[@]}"
      local hue L acc cand cands=() meta=()
      for (( hue=0; hue<360; hue+=20 )); do
        acc=$(_livery_hsl_to_hex "$hue" 70 50)
        for (( L=6; L<=12; L++ )); do
          cand=$(_livery_at_lightness "$acc" "$L" 70) || continue
          cands+=("$cand"); meta+=("$hue $L $acc")
        done
      done

      # one awk pass: score every candidate by its distance to the nearest
      # configured background, with a penalty for straying from the brand hue
      local best
      best=$(awk -v c="${cands[*]}" -v e="${exbg[*]}" -v m="${meta[*]}" -v bh="$bhue" '
        function h2d(x,   i,n,d){ n=0; for(i=1;i<=length(x);i++){ d=index("0123456789abcdef",tolower(substr(x,i,1)))-1; n=n*16+d } return n }
        function f(v){ v=v/255; return (v<=0.04045)? v/12.92 : ((v+0.055)/1.055)^2.4 }
        function cb(t){ return (t>0.008856)? t^(1/3) : 7.787*t+16/116 }
        function L_(h){ return 116*cb(0.2126*f(h2d(substr(h,1,2)))+0.7152*f(h2d(substr(h,3,2)))+0.0722*f(h2d(substr(h,5,2))))-16 }
        function A_(h,  r,g,b,X,Y){ r=f(h2d(substr(h,1,2))); g=f(h2d(substr(h,3,2))); b=f(h2d(substr(h,5,2)))
          X=(0.4124*r+0.3576*g+0.1805*b)/0.95047; Y=0.2126*r+0.7152*g+0.0722*b; return 500*(cb(X)-cb(Y)) }
        function B_(h,  r,g,b,Y,Z){ r=f(h2d(substr(h,1,2))); g=f(h2d(substr(h,3,2))); b=f(h2d(substr(h,5,2)))
          Y=0.2126*r+0.7152*g+0.0722*b; Z=(0.0193*r+0.1192*g+0.9505*b)/1.08883; return 200*(cb(Y)-cb(Z)) }
        BEGIN{
          nc=split(c,C," "); ne=split(e,E," "); split(m,M," ")
          for(j=1;j<=ne;j++){ eL[j]=L_(E[j]); eA[j]=A_(E[j]); eB[j]=B_(E[j]) }
          # Distinctness is a constraint, not something to trade away against
          # brand fidelity. Find the best separation available, aim for a floor
          # just under it, and among everything that clears the floor take the
          # smallest rotation from the brand hue. Scoring the two against each
          # other produces colours that are neither distinct nor on-brand.
          for(i=1;i<=nc;i++){
            cl=L_(C[i]); ca=A_(C[i]); cbb=B_(C[i]); mind=1e9; near=1
            for(j=1;j<=ne;j++){
              d=sqrt((cl-eL[j])^2+(ca-eA[j])^2+(cbb-eB[j])^2)
              if(d<mind){mind=d; near=j}
            }
            MD[i]=mind; NR_[i]=near
            if(mind>maxmd) maxmd=mind
          }
          floor=(maxmd<10)? maxmd*0.9 : 10
          bestrot=1e9; bi=0
          for(i=1;i<=nc;i++){
            if(MD[i]<floor) continue
            hue=M[(i-1)*3+1]+0
            rot=0
            if(bh>=0){ rot=(hue>bh)?hue-bh:bh-hue; if(rot>180) rot=360-rot }
            # tie-break on the larger separation
            if(rot<bestrot || (rot==bestrot && MD[i]>bd)){ bestrot=rot; bi=i; bd=MD[i]; bn=NR_[i] }
          }
          printf "%s %s %s %s %.1f %s", C[bi], M[(bi-1)*3+1], M[(bi-1)*3+2], M[(bi-1)*3+3], bd, bn
        }')
      local newbg nhue nL naccent nde nearidx
      read -r newbg nhue nL naccent nde nearidx <<<"$best"

      # prompt slots: the path takes the project hue, user@host a contrasting one
      local slot4 slot2 slot4n h2 try r
      _livery_solve_slot() {      # hue -> lightest-needed colour clearing 7.5:1
        local hh="$1" x c
        for (( x=35; x<100; x++ )); do
          c=$(_livery_hsl_to_hex "$hh" 70 "$x")
          r=$(_livery_contrast "$c" "$newbg")
          (( r >= 750 )) && { printf '%s' "$c"; return 0; }
        done
        _livery_hsl_to_hex "$hh" 70 90
      }
      # ansi4 is in the normal bank, so a program can paint it as a background.
      # Giving it the bright prompt colour is what leaves `\e[37;44m` unreadable,
      # so it takes the darkest-but-most-contrasting value at the same hue that
      # still holds the light text landing on it. The path keeps its punch from
      # ansi12, which PS1 reaches through `01;34` when bold-is-bright is on.
      _livery_solve_on_color_slot() {   # hue -> mid-tone holding light text
        local hh="$1" x c o rr bestc= bestr=-1 onfg
        onfg=$(_livery_on_color_fg)
        for (( x=20; x<100; x++ )); do
          c=$(_livery_hsl_to_hex "$hh" 70 "$x")
          o=$(_livery_contrast "$c" "$onfg")
          (( ${o:-0} < _LIVERY_O_on_color_contrast )) && continue
          rr=$(_livery_contrast "$c" "$newbg")
          (( ${rr:-0} > bestr )) && { bestr=$rr; bestc=$c; }
        done
        if [[ -n $bestc ]]; then printf '%s' "$bestc"
        else _livery_hsl_to_hex "$hh" 70 35; fi
      }
      # The suggestion names high-contrast-dark, so the light text those slots
      # must hold is that theme's ansi7 -- not whichever project _livery_resolve
      # happened to leave in _LIVERY_T while scoring the candidates above.
      _livery_load_theme high-contrast-dark 2>/dev/null || true
      slot4=$(_livery_solve_slot "$nhue")
      slot4n=$(_livery_solve_on_color_slot "$nhue")
      # A fixed offset is unreliable: a red opposite a blue lightens to pale
      # pink and ends up close to the path colour. Try several and measure.
      local -a c2s=() offs=(100 130 160 190 220)
      for h2 in "${offs[@]}"; do c2s+=("$(_livery_solve_slot $(( (nhue + h2) % 360 )) )"); done
      slot2=$(awk -v a="$slot4" -v c="${c2s[*]}" '
        function h2d(x,   i,n,d){ n=0; for(i=1;i<=length(x);i++){ d=index("0123456789abcdef",tolower(substr(x,i,1)))-1; n=n*16+d } return n }
        function f(v){ v=v/255; return (v<=0.04045)? v/12.92 : ((v+0.055)/1.055)^2.4 }
        function cb(t){ return (t>0.008856)? t^(1/3) : 7.787*t+16/116 }
        function LL(h){ return 116*cb(0.2126*f(h2d(substr(h,1,2)))+0.7152*f(h2d(substr(h,3,2)))+0.0722*f(h2d(substr(h,5,2))))-16 }
        function AA(h,  r,g,b,X,Y){ r=f(h2d(substr(h,1,2))); g=f(h2d(substr(h,3,2))); b=f(h2d(substr(h,5,2)))
          X=(0.4124*r+0.3576*g+0.1805*b)/0.95047; Y=0.2126*r+0.7152*g+0.0722*b; return 500*(cb(X)-cb(Y)) }
        function BB(h,  r,g,b,Y,Z){ r=f(h2d(substr(h,1,2))); g=f(h2d(substr(h,3,2))); b=f(h2d(substr(h,5,2)))
          Y=0.2126*r+0.7152*g+0.0722*b; Z=(0.0193*r+0.1192*g+0.9505*b)/1.08883; return 200*(cb(Y)-cb(Z)) }
        BEGIN{ n=split(c,C," "); al=LL(a); aa=AA(a); ab=BB(a); best=-1
          for(i=1;i<=n;i++){ d=sqrt((al-LL(C[i]))^2+(aa-AA(C[i]))^2+(ab-BB(C[i]))^2)
            if(d>best){best=d; b=C[i]} }
          printf "%s", b }')

      printf '\n  rule ~%s  theme=high-contrast-dark accent=#%s lightness=%s ansi4=#%s ansi12=#%s ansi2=#%s ansi10=#%s\n\n' \
        "${target#$HOME}" "$naccent" "$nL" "$slot4n" "$slot4" "$slot2" "$slot2"
      printf '  background  #%s   dE %s from the nearest (%s)\n' "$newbg" "$nde" "${exnm[$((nearidx-1))]:-none}"
      local c4 c2 c4n o4n
      c4=$(_livery_contrast "$slot4" "$newbg"); c2=$(_livery_contrast "$slot2" "$newbg")
      c4n=$(_livery_contrast "$slot4n" "$newbg")
      o4n=$(_livery_contrast "$slot4n" "$(_livery_on_color_fg)")
      printf '  path        #%s   %s.%02d:1   (ansi12, the bright bank)\n' "$slot4" "$((c4/100))" "$((c4%100))"
      printf '  plain blue  #%s   %s.%02d:1   (ansi4, holds light text at %s.%02d:1)\n' \
        "$slot4n" "$((c4n/100))" "$((c4n%100))" "$((o4n/100))" "$((o4n%100))"
      printf '  user@host   #%s   %s.%02d:1\n' "$slot2" "$((c2/100))" "$((c2%100))"
      if [[ -n $brand ]]; then
        local rot=$(( nhue > bhue ? nhue - bhue : bhue - nhue ))
        (( rot > 180 )) && rot=$(( 360 - rot ))
        printf '  brand hue %s rotated %s degrees to clear the configured set\n' "$bhue" "$rot"
      fi
      printf '\n  paste into %s, then run `livery audit`.\n' "$LIVERY_CONF"
      unset -f _livery_solve_slot _livery_solve_on_color_slot
      ;;
    preview)
      # Swatches use SGR (in-band text colour), not OSC, so this only prints
      # coloured text -- it never changes the terminal's actual colours.
      local i p lbl bg fg a2 a4 r g b fr fg2 fb
      case "${COLORTERM:-}" in
        truecolor|24bit) ;;
        *) printf 'note: COLORTERM=%s -- swatches need a truecolor terminal\n\n' "${COLORTERM:-unset}" ;;
      esac
      for i in "${!_LIVERY_PATHS[@]}"; do
        p="${_LIVERY_PATHS[i]}"
        _livery_resolve "$p" || continue
        bg="${_LIVERY_T[bg]:-}"; [[ -z $bg ]] && continue
        lbl="${_LIVERY_R_label:-$p}"
        fg="${_LIVERY_T[fg]:-ffffff}"
        # PS1 paints these bold (01;32, 01;34), so with bold-is-bright on they
        # render from the bright bank. Preview what the prompt actually shows,
        # not the normal-bank slots -- those now hold a darker value, because a
        # program can paint them as a background. Fall back to the normal slot
        # for a rule that sets only that one, or a profile with the setting off.
        a2="${_LIVERY_T[ansi10]:-${_LIVERY_T[ansi2]:-$fg}}"
        a4="${_LIVERY_T[ansi12]:-${_LIVERY_T[ansi4]:-$fg}}"
        read -r r g b <<<"$(_livery_rgb "$bg")"
        printf '\033[48;2;%s;%s;%sm ' "$r" "$g" "$b"
        read -r fr fg2 fb <<<"$(_livery_rgb "$a2")"
        printf '\033[38;2;%s;%s;%sm%s' "$fr" "$fg2" "$fb" "user@host"
        read -r fr fg2 fb <<<"$(_livery_rgb "$fg")"
        printf '\033[38;2;%s;%s;%sm:' "$fr" "$fg2" "$fb"
        read -r fr fg2 fb <<<"$(_livery_rgb "$a4")"
        printf '\033[38;2;%s;%s;%sm~/%s' "$fr" "$fg2" "$fb" "$lbl"
        read -r fr fg2 fb <<<"$(_livery_rgb "$fg")"
        printf '\033[38;2;%s;%s;%sm$ \033[0m' "$fr" "$fg2" "$fb"
        printf '  %-22s #%s\n' "$lbl" "$bg"
      done
      printf '\n  %s rules. `livery audit` measures what these only show.\n' "${#_LIVERY_PATHS[@]}"
      ;;
    reload)
      _livery_load_conf
      _LIVERY_DEFAULT_BG=                       # the config may have changed default_bg
      if [[ $_LIVERY_O_enable == on ]]; then
        if [[ $_LIVERY_O_auto == on && $_LIVERY_O_auto_contrast == on ]]; then
          _livery_load_profile_cache || true    # cache only: a query here would
        fi                                      # read the live project's palette
        [[ $_LIVERY_O_title == on ]] && _livery_install_title || _livery_remove_title
        _livery_init_default_bg || true
        _LIVERY_LAST_PWD=; _livery_hook
      else
        _livery_remove_title; _livery_reset     # disabling must undo, not just stop
      fi
      printf 'livery: reloaded %s\n' "$LIVERY_CONF" ;;
    on)     _LIVERY_O_enable=on;  _LIVERY_LAST_PWD=; _livery_hook ;;
    off)    _LIVERY_O_enable=off; _livery_remove_title; _livery_reset ;;
    title)
      case "${2:-}" in
        on)  _LIVERY_O_title=on;  _livery_install_title; _LIVERY_LAST_PWD=; _livery_hook
             printf 'livery: tab title on\n' ;;
        off) _LIVERY_O_title=off; _livery_remove_title; _LIVERY_TITLE=
             printf 'livery: tab title off (reopen the tab to clear it)\n' ;;
        *)   printf 'tab title: %s   (livery title on|off)\n' "$_LIVERY_O_title" ;;
      esac ;;
    reset)  _livery_reset ;;
    forget)
      # Both caches describe the terminal profile, so a profile change
      # invalidates both. Reset the palette before re-reading it, or the
      # snapshot records the current project instead of the profile.
      rm -f "$LIVERY_CACHE/default_bg" "$(_livery_profile_cache)"
      _LIVERY_DEFAULT_BG=; _LIVERY_P=()
      _LIVERY_CUR_BG=; _livery_reset
      _livery_init_default_bg || true
      printf 'livery: default-bg cache cleared, re-read as %s\n' \
        "$(_livery_fmt "${_LIVERY_DEFAULT_BG:-}" '<query failed>')"
      if [[ $_LIVERY_O_auto == on && $_LIVERY_O_auto_contrast == on ]]; then
        _livery_init_profile_palette || true
        printf 'livery: profile palette re-read, %s of %s slots\n' \
          "${#_LIVERY_P[@]}" "${#_LIVERY_PROFILE_SLOTS[@]}"
      fi
      _LIVERY_LAST_PWD=; _livery_hook ;;
    demo)
      local a c prev
      printf 'Fading through the palette at lightness=%s. Watch the background.\n' "$_LIVERY_O_lightness"
      prev="${_LIVERY_CUR_BG:-${_LIVERY_DEFAULT_BG:-}}"
      for a in "${_LIVERY_PALETTE[@]:0:6}"; do
        c=$(_livery_at_lightness "$a" "$_LIVERY_O_lightness" "$_LIVERY_O_saturation")
        printf '  hue of #%s -> bg #%s\n' "$a" "$c"
        _livery_fade_bg "$prev" "$c" "$_LIVERY_O_fade_ms"; prev="$c"
        _livery_msleep 450
      done
      _LIVERY_CUR_BG="$prev"; _livery_reset
      printf 'Done, restored to profile defaults.\n'
      ;;
    *) printf 'usage: livery [status|test [dir]|preview|themes|audit|suggest <dir> [#brand]|doctor|title on|off|reload|on|off|reset|forget|demo]\n' ;;
  esac
}

# ------------------------------------------------------------------- install --
_livery_load_conf
_livery_init_sleepfd                 # must happen here, not in PROMPT_COMMAND
if [[ $_LIVERY_O_enable == on ]]; then
  [[ $_LIVERY_O_title == on ]] && _livery_install_title
  _livery_init_default_bg || true    # learn the profile default before any color is set
  # Same reason and same timing: the profile's own text colours can only be read
  # while they are still on screen, before any project's palette is applied.
  # Cached on disk, so only the first shell on a machine pays for the queries.
  if [[ $_LIVERY_O_auto == on && $_LIVERY_O_auto_contrast == on ]]; then
    _livery_init_profile_palette || true
  fi
fi                                   # disabled: touch nothing, not even a query
case "${PROMPT_COMMAND:-}" in
  *_livery_hook*) ;;                                    # already installed
  *) PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND; }_livery_hook" ;;
esac
