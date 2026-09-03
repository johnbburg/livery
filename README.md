# livery

A bash hook that recolors the terminal background when you `cd` into a project,
so a screenful of windows running different projects is distinguishable at a
glance. The transition is a fade, not a snap.

A livery is the distinctive color scheme that identifies whose something is.
Each project gets one, and its windows wear it.

No daemon and no background process — it costs nothing while idle. It needs
bash 4+, coreutils, and `awk` for the contrast maths in `livery test`/`audit`
(any POSIX awk; no GNU extensions). It makes no changes to your terminal
profile, and works by writing OSC escape sequences to the tty.

## Requirements and scope

- **bash only.** The hook installs itself into `PROMPT_COMMAND` and `PS1`.
  There is no zsh or fish port.
- **A terminal that implements `OSC 4`, `10`, `11`, `12` and the matching
  `104`/`110`/`111`/`112` resets.** Check before installing anything:

  ```sh
  sh tools/terminal-probe.sh
  ```

  That script is plain POSIX `sh` — it runs under sh, zsh, and macOS's bash 3.2,
  needs livery neither installed nor sourced, and restores every colour it
  touches. Use it to answer the terminal question independently of the shell
  question. `livery doctor` does the same thing once livery is running.
- **Developed and verified on gnome-terminal 3.44 / VTE 0.68 (Ubuntu 22.04).**
  The escape sequences are standard and it should work on other terminals that
  implement them, but no others have been tested. Run `livery doctor` first.
  The `--real-terminal` test suite invokes `gnome-terminal` specifically; the
  other suites are portable.
- Python 3 is needed to run the test suite, not to use the tool.


## Install

Clone or copy it anywhere; nothing depends on the location.

```bash
LIVERY=~/.local/share/livery        # or wherever you keep it

# themes live in the config directory, not next to the script
mkdir -p ~/.config/livery/themes
cp "$LIVERY"/themes/*.conf ~/.config/livery/themes/
cp "$LIVERY"/livery.conf.example ~/.config/livery/livery.conf

# try it in one shell
source "$LIVERY"/livery.sh

# keep it: add to the END of ~/.bashrc, after PS1 and PROMPT_COMMAND are set
source "$LIVERY"/livery.sh
```

It must be sourced *after* `PS1` and `PROMPT_COMMAND` are set: livery appends
its hook to one and its title escape to the other.

The hook appends itself to `PROMPT_COMMAND` and is safe to source twice.
Config lives at `~/.config/livery/livery.conf`; see `livery.conf.example`.

## Config

```
set mode        dark        # dark = accent hue pinned dark | tint = blend
set lightness   10          # how dark derived backgrounds are (HSL L%)
set saturation  70          # cap on their saturation
set fade_ms     260         # fade duration
set fade_steps  16          # frames (1 = instant snap)
set auto        on          # auto-color unlisted projects under auto_root
set auto_root   ~/projects
set auto_lightness 18       # auto colors sit above the configured band
set auto_contrast on        # keep the profile palette readable on those colors
set auto_min_contrast 450   # the floor it repairs to (4.50:1)
set on_color_contrast 300   # floor for text sitting *on* a colour (3.00:1)
set title       on          # project name as the tab label
set min_contrast 700        # `livery test` flags anything under 7.00:1

rule ~/projects/foo   theme=high-contrast-dark
rule ~/projects/bar   theme=high-contrast-dark accent=#e06c75
rule ~/projects/baz   accent=#61afef lightness=8
rule ~/work/prod      bg=#2a0708 fg=#ffd7d7 ansi4=#ff5b66 cursor=#ff7575
```

Longest matching path prefix wins, so a rule on a subdirectory overrides its
parent.

`mode=dark` treats an accent as a **hue source only** and discards its
brightness: the background is that hue at `lightness`. Blending a near-black
background toward a bright accent — what `mode=tint` does — always raises
luminance, so every project ends up lighter than the profile default. Pinning
lightness instead keeps projects equally dark and still tells them apart.

## Auto mode

With `auto on`, any directory directly under `auto_root` gets a background
derived from its name — POSIX `cksum` over the name, modulo a hue ring. No
randomness, no hostname, no path, so a directory keeps the same color on any
machine, and renaming it changes the color.

Auto colors are placed in **their own lightness band** (`auto_lightness`, above
the one configured rules use) rather than competing for hues. That is not a
stylistic choice. At a shared lightness the perceptual difference between two
dark colors is dominated by lightness, so an auto color twenty degrees of hue
away from a configured project still reads as the same color: measured here,
eleven of fourteen auto colors once sat within ΔE 8 of a client and the worst
was ΔE 1.6 — indistinguishable. Separating by lightness puts every auto color
clear of every configured one, and gives "lighter" a meaning: not a project you
named.

Auto projects get a background only; their text colors stay the terminal
profile's, which is the second signal — an unlisted directory keeps your normal
prompt colors, where a project you named gets a theme.

### Keeping the profile palette readable

A background the profile was never chosen for can make that palette unreadable,
and on Ubuntu it does. `PS1` paints the path with `01;34`, which resolves to
`ansi4` or `ansi12` depending on `bold-is-bright`; the stock values are `#12488b`
and `#2a7bde`, measuring **1.17:1** and **2.51:1** against an auto background at
`auto_lightness 18`. Against the profile's own `#300a24` they are 1.95:1 and
4.17:1, so that blue was never readable on a dark background — configured rules
override those two slots by hand for exactly this reason, and an auto project
has nobody to do it.

With `auto_contrast on` (the default), each slot that falls under
`auto_min_contrast` against the derived background is replaced by **the
profile's own color at the same hue and saturation**, moved the shortest
distance in lightness that clears the floor. `#2a7bde` becomes `#7eafeb` at
4.64:1. Slots already clearing the floor are left alone and reset to the
profile, so on the stock Ubuntu palette nine of fifteen change and six do not —
the palette stays recognisably yours, brighter, not re-themed. `ansi0` and
`ansi8` are never repaired: they are dim text and box drawing, and `livery test`
exempts them from the threshold.

`ansi1`, `ansi4` and `ansi5` are solved differently, because a program can paint
them *as* a background — see [Two roles per slot](#two-roles-per-slot). On an
auto background the two roles cannot both be satisfied: `#12488b` becomes
`#1c70d9`, which holds light text at 3.09:1 and reads as text at 2.20:1, up from
the profile's 1.17:1. `livery audit` reports both figures.

The floor is 4.50:1 (WCAG AA for body text), not `min_contrast`'s 7:1.
`min_contrast` is the target for palettes written by hand, and repairing to it
would rewrite eleven of the fifteen stock slots — re-theming the terminal rather
than fixing what broke. Set `auto_contrast off` to keep the profile palette
untouched whatever it measures.

Repair needs the profile's own values, which only the terminal can report. They
are read once with an `OSC 4` query per slot and cached in
`~/.cache/livery/palette`, so only the first shell on a machine pays for it. The
read happens at source time, before any project color is applied — a later
snapshot would record whichever project was on screen instead of the profile.
`livery forget` clears both caches and re-reads them; `livery status` says how
many slots are known. If the terminal never answers, nothing is repaired and
`livery test` and `livery audit` say so rather than reporting the palette as
fine.

`auto_root` is a single path. Anything outside it needs an explicit rule.

## Two roles per slot

An ANSI slot is addressed in two roles, and a color readable in one can be
unreadable in the other:

```
\e[31m   red text          needs contrast against the project background
\e[41m   red background    needs contrast against the text a program puts on it
```

Measuring only the first is a silent trap. Symfony Console — so `composer`,
`drush`, and every PHP tool that uses it — prints its error block as
`\e[37;41m`, which is `ansi7` text on an `ansi1` background:

```php
$this->block($message, 'ERROR',   'fg=white;bg=red');     // SymfonyStyle.php
$this->block($message, 'OK',      'fg=black;bg=green');
$this->block($message, 'WARNING', 'fg=black;bg=yellow');
```

Lightening `ansi1` until it reads well as text is exactly what makes that block
illegible. A pale `#ff9a9a` measures 9.46:1 as text and **1.32:1** under `ansi7`
— worse than the stock Ubuntu red it replaced, which manages 3.92:1.

So the two banks are tuned for different roles:

| bank | role | tuned for |
|---|---|---|
| `ansi1`–`ansi7` | text *and* background | both, capped by `on_color_contrast` |
| `ansi9`–`ansi15` | text only | contrast against the background |

Within the normal bank, the target depends on which text convention pairs with
each slot. Red, blue and magenta carry light text, so they are dark enough to
hold `ansi7` at `on_color_contrast`. Green, yellow and cyan carry black text, so
they stay light. `\e[101m`-style bright backgrounds are rare enough that the
bright bank is left unconstrained.

One slot cannot clear AA in both roles at once. At the theme's red hue:

| `ansi1` | as text | `ansi7` on it |
|---|---|---|
| `#ff9a9a` | 9.46:1 | 1.32:1 |
| `#eb0000` | 4.15:1 | 3.00:1 |
| `#b30000` | 2.67:1 | 4.66:1 |

The shipped theme takes the middle row. `livery test` prints both figures for
these slots and labels them `(two-sided)`; they are held to
`on_color_contrast` rather than `min_contrast`, the same way `ansi0` and `ansi8`
are exempt as structural. `livery audit` reports the worst of each role
separately, because one combined figure would call a palette clean while half of
it was unreadable.

### bold-is-bright

The bank split assumes `bold-is-bright` is **on** in the terminal profile. That
setting is what sends `\e[1;31m` — bold red text, what `grep`, `pytest` and
`npm ERR!` emit — to the bright bank:

```sh
gsettings set "org.gnome.Terminal.Legacy.Profile:\
/org/gnome/terminal/legacy/profiles:/:$(gsettings get \
org.gnome.Terminal.ProfilesList default | tr -d \')/" bold-is-bright true
```

With it off, that text renders from `ansi1` at 4.15:1 instead of 9.51:1 —
readable, but without the punch the bright bank gives it. livery never changes
your terminal profile, so this is yours to set.

## Themes

A rule can name a theme file in `~/.config/livery/themes/`:

```
bg      #0b0f14
fg      #dfe6ee
cursor  #ffcc66
bold    #ffffff
ansi0   #20262e
ansi1   #ff8080
...
ansi15  #ffffff
```

`ansi0`–`ansi15` are the sixteen ANSI palette entries, and they are what colour
your prompt: `PS1` uses ANSI codes, not the plain foreground, so setting `fg`
alone leaves the prompt untouched. `ansi2`/`ansi10` are green, `ansi4`/`ansi12`
are blue.

A theme may instead supply only `accent`, `lightness` and `saturation`, in which
case only the background is derived. Any slot a theme does not define is **reset
to your terminal profile's own value**, not left at whatever the previous
project set — otherwise moving from a full theme to a partial one would silently
keep the old project's palette.

Inline rule keys override the theme file, so `theme=X ansi4=#79b8ff` is one
theme with one colour changed.

The background has its own precedence, highest first:

```
inline bg  >  inline accent  >  theme bg  >  theme accent  >  auto accent
```

An inline `accent` beats the theme's own `bg` on purpose. That is what lets one
shared theme carry the text palette while each project's accent sets the
background hue — the intended shape for per-client colours:

```
rule ~/projects/client-a  theme=high-contrast-dark accent=#61afef
rule ~/projects/client-b  theme=high-contrast-dark accent=#e06c75
```

Without that precedence, every project sharing a theme would render identically.

`livery test <dir>` prints the whole resolved set with a measured WCAG contrast
ratio for each colour against that theme's background, flagging anything below
`min_contrast`. For an auto project it prints the same rows, marking each slot as
repaired or as the profile's own and measuring against `auto_min_contrast`.
`ansi0` and `ansi8` are marked structural and exempt — they are dim text and box
drawing, not body text. `ansi1`, `ansi4` and `ansi5` are marked `(two-sided)`
and carry a second figure, the contrast of the light text a program puts on
them; they are held to `on_color_contrast` instead of `min_contrast`.

In the shipped `high-contrast-dark` theme the lowest unexempt text colour is
`ansi9` at 9.51:1, and the lowest two-sided slot is `ansi4` at 4.05:1 as text
and 3.07:1 under `ansi7`.

Theme files are parsed, never sourced; unknown keys are reported on stderr.

With `auto on`, any directory directly under `auto_root` gets a color derived
from its name — stable across shells and machines, so a project keeps the same
color without being listed. Explicit rules are for the ones you want to
control, including anything that should look alarming.

The config file is parsed, never sourced. Only `set` and `rule` lines are
honoured and unknown keys are reported on stderr.

## Tab labels

`set title on` replaces the stock `user@host:~/long/path` tab label with just
the project name, which is the part a narrow tab truncates away.

The label is appended to the end of `PS1`, not emitted from `PROMPT_COMMAND`.
That matters: a stock Ubuntu `~/.bashrc` puts its own
`\[\e]0;\u@\h: \w\a\]` inside `PS1`, which is emitted *after*
`PROMPT_COMMAND` and would overwrite anything set there. The last title escape
in a prompt render is the one that sticks, so livery appends and only updates a
variable from the hook. `livery title on|off` toggles it and restores the
original `PS1`.

## Prompt colors

`PS1` colors text with ANSI codes, so `fg` alone cannot reach it. To make text
carry the project identity, override the palette slots the prompt actually uses.
A stock Ubuntu `PS1` uses `01;32` (bold green) for `user@host` and `01;34`
(bold blue) for the path, so:

```
rule ~/projects/foo  theme=high-contrast-dark accent=#0058A4 \
     ansi4=#5967e2 ansi12=#949FF0 ansi2=#C0A21B ansi10=#C0A21B
```

Give `ansi4` and `ansi12` **different** values. They are one hue in two roles:
`ansi12` carries the path and takes the bright value, while `ansi4` is in the
normal bank, where a program can paint it as a background, so it takes a
mid-tone that still holds light text — see
[Two roles per slot](#two-roles-per-slot). Above, `#949FF0` reads at 7.76:1 as
the path but holds `ansi7` at only 1.60:1; `#5967e2` reads at 4.09:1 and holds
it at 3.05:1. `ansi2`+`ansi10` can share one value, because green is paired
with black text rather than light.

Set **both** slots of each pair either way, because the codes are bold and VTE
picks between the normal and bright entry depending on its `bold-is-bright`
setting. Setting one pair
would work or not depending on that setting.

Pick the values by solving rather than by eye: take the hue from a brand colour
and use the *lowest* lightness that still clears your contrast target against
that project's background. Lowest keeps the most colour; anything higher washes
out to pastel. Then check the two slots are far enough apart from each other and
from `fg` to be worth having — `livery audit` reports the contrast, and the
configured rules here hold at or above 7.3:1 with the two slots ΔE 52–113 apart.

These slots are not private to the prompt: `ls` colors directories with `ansi4`
and executables with `ansi2`, and some git output uses them. Recolouring them
recolours that too.

## Commands

| Command | Effect |
|---|---|
| `livery status` | resolved options, the scheme in effect, and the color read back off the terminal |
| `livery test [dir]` | the full resolved theme with contrast ratios, without applying it |
| `livery preview` | draw every configured project as a swatch, in one screen |
| `livery suggest <dir> [#brand]` | propose a rule that does not collide, with the figures |
| `livery themes` | list available theme files |
| `livery audit` | check every project, rules and auto alike: contrast per color, and how far apart the backgrounds are (CIELAB ΔE) |
| `livery title on\|off` | toggle the tab label, restoring the original `PS1` |
| `livery doctor` | probe which colors this terminal actually lets you set |
| `livery demo` | fade through the palette, then restore |
| `livery reload` | re-read the config |
| `livery on` / `off` / `reset` | enable, disable, restore profile defaults |
| `livery forget` | drop the cached default background and profile palette, and re-read both |

## Tests

```bash
./test/run-tests.sh                  # headless: opens no windows, steals no focus
./test/run-tests.sh --real-terminal  # also drives a real gnome-terminal
```

Five headless suites run by default: color math including the contrast repair
(`test/unit.sh`), livery's behavior against a mock terminal on a pty
(`test/logic.py` + `test/mockterm.py`), the CLI subcommands against that same
mock (`test/cli.py` — probe, doctor, test, audit, preview, suggest, reload), an
interactive-shell suite that drives a real bash on a pty and checks the prompt is
still drawn and typed input still echoes (`test/prompt.py`), and a check that
sourcing the file in a shell with no tty stays silent. The mock terminal speaks the OSC subset livery depends on and
records every color it is told to use, so the assertions cover the whole fade
sequence — frame count, monotonicity per channel, no overshoot, exact landing —
not just the final color. Expected tints are computed in Python independently
of the shell arithmetic, so the two implementations have to agree.

The auto-contrast assertions read the colors the mock terminal is left holding
and measure them with a WCAG implementation written independently in Python, so
a repair that satisfies livery's own arithmetic but not the spec still fails.
`test/run-tests.sh` also checks the repair produces byte-identical output under
both gawk and mawk, and that awk's figure matches the one bash measures.

`--real-terminal` additionally drives gnome-terminal and reads each color back
off the tty. It opens a window that takes keyboard focus while it runs, and
stray keystrokes land in that window, so run it only when you are not typing.

See [CONTRIBUTING.md](CONTRIBUTING.md) before changing the hook — the rule about
testing `PROMPT_COMMAND` against a real interactive shell was learned the hard
way.

## Verified behavior

Measured on gnome-terminal 3.44 / VTE 0.68 (Ubuntu 22.04), the environment this
was written for.

- `OSC 10/11/12` set foreground/background/cursor, and answer `?` queries.
- `OSC 4;N` sets the ANSI palette, and answers `OSC 4;N;?` queries. This is what
  reaches the prompt: `PS1` colors text with ANSI codes, so the plain foreground
  cannot touch it. Confirmed for indices 1, 4 and 12 via `livery doctor`.
- `OSC 110/111/112` restore the profile's own colors exactly, and `OSC 104`
  restores the palette. `livery doctor` checks restoration numerically rather
  than only checking that setting works.
- A 260 ms / 16-frame fade takes ~295 ms wall-clock and lands exactly on the
  target color.
- The color survives `clear`, `vim`, `top`, `less`, and `tput reset`, and
  persists through a long-running full-screen program — the point being that a
  Claude session started in a colored window stays that color.
- The tab label also survives a program setting its own title, including Claude
  Code. Because the label lives at the end of `PS1` rather than in
  `PROMPT_COMMAND`, it is reasserted on every prompt: Claude's title shows while
  it works, and the project name returns at the next prompt.
- With no controlling terminal, sourcing the file is silent and inert.
- The stock Ubuntu 22.04 palette (`use-theme-colors true`, so the palette is the
  profile's own) reports `ansi4 #12488b` and `ansi12 #2a7bde` — 1.17:1 and
  2.51:1 against an auto background at `auto_lightness 18`, and 1.95:1 and
  4.17:1 against the profile's `#300a24`. Repair costs one awk fork, adding
  ~14 ms to the directory change that triggers it, against a 260 ms fade.
- Across the 119 auto projects and 12 rules configured here, `livery audit`
  measures the lowest auto text contrast at 4.50:1 and the lowest rule text
  contrast at 7.33:1, with the closest auto-to-rule background pair at ΔE 9.7.

## Limitations

- **gnome-terminal cannot color the tab bar**, only the terminal body. So
  color identifies a *window* — in Alt-Tab and the Activities overview — and
  confirms where you are typing, but you cannot scan a row of tabs by color;
  only the foreground tab shows its own. Tabs are identified by their *label*
  instead (`set title on`). For actual per-tab color in the bar you need a
  different emulator; WezTerm derives per-tab title and color from each pane's
  working directory.
- Terminals that do not implement `OSC 11` get nothing. There is no fallback.
- If your terminal does not answer the `OSC 11` query, every new shell waits
  0.4 s for a reply that never comes. Set `default_bg` in the config to skip
  the query entirely.
- **gnome-terminal reports its default background inconsistently.** The same
  profile has been observed answering `OSC 11` with both `#300a24` and
  `#380c2a` (exactly 7/6 apart) within the first seconds of a window's life.
  The cause is not established; it tracked neither elapsed time nor focus state
  reliably. The consequence, if a bad value is captured, is that all tints are
  computed from a slightly wrong base and the fade back to default ends one
  small step off before `OSC 111` snaps it into place — visible as a faint
  final jump, not as a wrong color. Two mitigations are in place: the capture
  takes the most common of three samples, and `livery status` warns when the
  cached default disagrees with the terminal. Pinning `default_bg` in the
  config avoids the query and the whole problem, and is the recommended
  setting.
- Hue derivation works in HSL, which is not perceptually uniform, so two
  accents can land at the same `lightness` and still look unequally bright.
  The contrast figures from `livery test` are the reliable measure.
- Only the background is faded. Foreground, cursor, bold and the palette are
  applied in a single write before the fade starts, so text is never rendered
  against a half-transitioned palette.
- Bash only. There is no zsh/fish hook.

## Adding a client

`livery suggest` does the allocation for you:

```
$ livery suggest ~/projects/newclient '#0058A4'

  rule ~/projects/newclient  theme=high-contrast-dark accent=#6126d8 lightness=12 \
       ansi4=#8354e2 ansi12=#b396ed ansi2=#21be21 ansi10=#21be21

  background  #170934   dE 11.2 from the nearest (alpha)
  path        #b396ed   7.56:1   (ansi12, the bright bank)
  plain blue  #8354e2   3.85:1   (ansi4, holds light text at 3.14:1)
  user@host   #21be21   7.51:1
  brand hue 209 rotated 51 degrees to clear the configured set
```

It searches hues and lightnesses, scores each candidate by its perceptual
distance to every configured background, and treats distinctness as a
**constraint** rather than something to trade against brand fidelity: it finds
the best separation available, then takes the smallest rotation from your brand
hue that still clears it. Scoring the two against each other produces colours
that are neither distinct nor on-brand.

It will tell you when your brand is crowded. A blue among several blue projects
rotates 51 degrees; an orange with room moves 8. That number is the honest cost
of keeping windows distinguishable, and it is better seen than discovered later.

The contrasting prompt colour is chosen by measurement, not a fixed offset — a
red opposite a blue lightens to pale pink and ends up close to the path colour,
so several offsets are solved and the most separated wins.

Paste the rule, then run `livery audit`. What it predicts is what livery
produces; the test suite round-trips a suggestion through resolution to prove it.

## Adding a client by hand

Read the brand colour out of the site's own theme rather than guessing. For a
Gesso theme that is `source/00-config/_design-tokens.artifact.scss` (look for
`primary: background:`, or a `base:` under a colour name); older Gesso keeps it
in `sass/partials/**/_variables.scss`.

Then add one rule and run `livery audit`:

```
rule ~/projects/newclient  theme=high-contrast-dark accent=#0058A4 lightness=8
livery audit
```

Two things go wrong, and `audit` reports both:

- **Text stops being readable.** A brand colour chosen for white marketing pages
  is usually too dark to sit behind light text. Only the *hue* is taken from it,
  so this is rare, but `audit` reports the lowest contrast across every rule.
- **Two projects end up the same colour.** Brands collide — agencies reuse the
  same blue. `audit` reports the closest pair as a ΔE figure; below about 5 they
  are hard to tell apart, and it caught two rules at ΔE 1.9 during setup here.

Lightness is the second axis when hues genuinely cannot move — two sites for
one client, or two checkouts of one repository, legitimately share a brand and
are separated by `lightness` alone.

## Note for anyone changing the hook

`test/prompt.py` exists because of a bug that every colour test passed while the
shell was unusable. `_livery_msleep` allocated its sleep descriptor lazily with
`exec {fd}<> <(:)`; run inside `PROMPT_COMMAND`, that stops an interactive bash
from drawing its prompt or echoing keystrokes — the shell writes nothing at all.
Colours were still set correctly, so the mock-terminal suite stayed green.
The descriptor is now allocated once at source time.

Anything that touches `PROMPT_COMMAND` has to be checked against a real
interactive shell on a pty, compared against a control run without livery
loaded. Verifying that the escape sequences were correct proves only that the
escape sequences were correct.

Escape sequences are built from real `ESC` bytes (`_livery_osc`), never from
`\033` strings fed to `printf %b`. Two `%b` sequences concatenated merge
`"\033\"` + `"\033"` into `"\033\\033"`, which `%b` reads as ESC, a literal
backslash, then the text `033` — so only the first sequence in a batched write
survives and the remainder prints to the screen as garbage. The mock terminal
now records every byte that falls outside a well-formed sequence and the tests
assert there are none.

## License

MIT — see [LICENSE](LICENSE). The copyright line reads "livery contributors";
set it to whoever actually holds the copyright before publishing.
