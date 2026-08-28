#!/bin/bash
# Runs inside the mock terminal (test/mockterm.py). Emits marks so the harness
# can snapshot colour state at known points.
E="$1"; CONF="$2"
LIVERY_SH="${LIVERY_SH:?}"
mark(){ printf '\033]777;mark;%s\033\\' "$1" >/dev/tty; }
export LIVERY_CONF="$CONF" LIVERY_CACHE=$(mktemp -d)
source "$LIVERY_SH"
go(){ cd "$1" && _livery_hook; }

mark start
go "$E/proj-a";             mark proj_a
go "$E/proj-a/sub";         mark proj_a_sub
go "$E/proj-b";             mark proj_b
go "$E/proj-loud";          mark proj_loud
go "$E/proj-theme";         mark proj_theme
go "$E/proj-override";      mark proj_override
go "$E/proj-dark";          mark proj_dark
go "$E/proj-theme-accent";  mark proj_theme_accent
go "$E/proj-theme-bg";      mark proj_theme_bg
go "$E/proj-theme";         mark before_partial
go "$E/proj-hueonly";       mark after_partial
go "$E/proj-a";             mark before_fgonly
go "$E/proj-fgonly";        mark fgonly
go "$E/proj-a";             mark before_badbg
go "$E/proj-badbg";         mark badbg
go "$HOME";                 mark home
go "$E/auto/alpha-proj";    mark auto_alpha
go "$E/auto/beta-proj";     mark auto_beta
go "$HOME";                 mark home2
go "$E/auto/alpha-proj";    mark auto_alpha_again
_livery_hook;                  mark repeat_hook
livery off  >/dev/null 2>&1;   mark livery_off
livery on   >/dev/null 2>&1;   mark livery_on
livery reset >/dev/null 2>&1;  mark livery_reset
rm -rf "$LIVERY_CACHE"
