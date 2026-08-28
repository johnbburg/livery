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
  _LIVERY_O_title=off    _LIVERY_O_default_bg=
  _LIVERY_O_min_contrast=700                       # warn below 7.00:1
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
          enable|mode|alpha|lightness|saturation|fade_ms|fade_steps|auto|auto_root|auto_lightness|title|default_bg|min_contrast)
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
    accent=$(_livery_auto_accent "$label"); is_auto=1
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
_livery_report_theme() {        # print the resolved theme with contrast figures
  local k v bg fg ratio
  bg="${_LIVERY_T[bg]:-}"; fg="${_LIVERY_T[fg]:-}"
  printf '  %-8s %s\n' 'label' "${_LIVERY_R_label:-<none>}"
  [[ -n ${_LIVERY_R_theme:-} ]] && printf '  %-8s %s\n' 'theme' "$_LIVERY_R_theme"
  for k in bg fg cursor bold ansi0 ansi1 ansi2 ansi3 ansi4 ansi5 ansi6 ansi7 \
           ansi8 ansi9 ansi10 ansi11 ansi12 ansi13 ansi14 ansi15; do
    v="${_LIVERY_T[$k]:-}"
    [[ -z $v ]] && continue
    if [[ -n $bg && $k != bg ]]; then
      ratio=$(_livery_contrast "$v" "$bg" 2>/dev/null)
      # ansi0/ansi8 are structural -- dim text and box drawing, not body text --
      # so the readability threshold does not apply to them.
      local flag=
      case "$k" in
        ansi0|ansi8) flag='  (structural)' ;;
        *) (( ${ratio:-0} < _LIVERY_O_min_contrast )) && flag='  LOW' ;;
      esac
      printf '  %-8s #%s   contrast vs bg %s.%02s:1%s\n' "$k" "$v" \
        "$(( ${ratio:-0} / 100 ))" "$(printf '%02d' $(( ${ratio:-0} % 100 )))" "$flag"
    else
      printf '  %-8s #%s\n' "$k" "$v"
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
      printf 'auto_root: %s\n' "$_LIVERY_O_auto_root"
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
      # Check every configured rule at once: contrast of each colour against its
      # own background, and how far apart the backgrounds are perceptually.
      # Run this after adding a client, rather than trusting that it looks fine.
      local i p bgs=() names=() worst=99999 worstwhat= lowcount=0 ratio k v measured=0
      for i in "${!_LIVERY_PATHS[@]}"; do
        p="${_LIVERY_PATHS[i]}"
        _livery_resolve "$p" || continue
        local bg="${_LIVERY_T[bg]:-}"
        [[ -z $bg ]] && continue
        names+=("${_LIVERY_R_label:-$p}"); bgs+=("$bg")
        for k in fg bold cursor ansi1 ansi2 ansi3 ansi4 ansi5 ansi6 ansi7 \
                 ansi9 ansi10 ansi11 ansi12 ansi13 ansi14 ansi15; do
          v="${_LIVERY_T[$k]:-}"; [[ -z $v ]] && continue
          ratio=$(_livery_contrast "$v" "$bg") || continue
          measured=$((measured+1))
          if (( ratio < worst )); then worst=$ratio; worstwhat="$k on ${_LIVERY_R_label:-$p}"; fi
          (( ratio < _LIVERY_O_min_contrast )) && lowcount=$((lowcount+1))
        done
        printf '  %-22s bg #%s\n' "${_LIVERY_R_label:-$p}" "$bg"
      done
      printf '\n  %s rules with a background\n' "${#bgs[@]}"
      if (( measured == 0 )); then
        printf '  lowest text contrast : n/a (no text colours in any rule)\n'
      else
        printf '  lowest text contrast : %s.%02s:1  (%s)\n' \
          "$(( worst / 100 ))" "$(printf '%02d' $(( worst % 100 )))" "$worstwhat"
      fi
      printf '  below min_contrast   : %s\n' "$lowcount"
      if (( ${#bgs[@]} > 1 )); then
        # Perceptual distance in CIELAB. Channels are converted to decimals here
        # so the awk stays portable: strtonum() is GNU-only and mawk lacks it.
        local dec= r g b
        for p in "${bgs[@]}"; do
          read -r r g b <<<"$(_livery_rgb "$p")"
          dec+="$r $g $b "
        done
        printf '  closest backgrounds  : %s\n' \
          "$(awk -v d="$dec" -v nm="${names[*]}" '
            function f(v){ v=v/255; return (v<=0.04045)? v/12.92 : ((v+0.055)/1.055)^2.4 }
            function cb(t){ return (t>0.008856)? t^(1/3) : 7.787*t+16/116 }
            BEGIN{
              n=split(d,c," "); split(nm,q," "); k=0
              for(i=1;i<=n;i+=3){
                k++
                r=f(c[i]); g=f(c[i+1]); b=f(c[i+2])
                X=(0.4124*r+0.3576*g+0.1805*b)/0.95047
                Y=(0.2126*r+0.7152*g+0.0722*b)
                Z=(0.0193*r+0.1192*g+0.9505*b)/1.08883
                fy=cb(Y); L[k]=116*fy-16; A[k]=500*(cb(X)-fy); B[k]=200*(fy-cb(Z))
              }
              best=1e9
              for(i=1;i<=k;i++) for(j=i+1;j<=k;j++){
                e=sqrt((L[i]-L[j])^2+(A[i]-A[j])^2+(B[i]-B[j])^2)
                if(e<best){best=e; bi=q[i]; bj=q[j]}
              }
              printf "dE %.1f  (%s vs %s)", best, bi, bj }')"
      fi
      ;;
    reload)
      _livery_load_conf
      _LIVERY_DEFAULT_BG=                       # the config may have changed default_bg
      if [[ $_LIVERY_O_enable == on ]]; then
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
    forget) rm -f "$LIVERY_CACHE/default_bg"; _LIVERY_DEFAULT_BG=; _livery_init_default_bg || true
            printf 'livery: default-bg cache cleared, re-read as %s\n' "$(_livery_fmt "${_LIVERY_DEFAULT_BG:-}" '<query failed>')" ;;
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
    *) printf 'usage: livery [status|test [dir]|themes|audit|doctor|title on|off|reload|on|off|reset|forget|demo]\n' ;;
  esac
}

# ------------------------------------------------------------------- install --
_livery_load_conf
_livery_init_sleepfd                 # must happen here, not in PROMPT_COMMAND
if [[ $_LIVERY_O_enable == on ]]; then
  [[ $_LIVERY_O_title == on ]] && _livery_install_title
  _livery_init_default_bg || true    # learn the profile default before any color is set
fi                                   # disabled: touch nothing, not even a query
case "${PROMPT_COMMAND:-}" in
  *_livery_hook*) ;;                                    # already installed
  *) PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND; }_livery_hook" ;;
esac
