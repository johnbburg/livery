# Changelog

Notable changes, newest first. Dates are ISO 8601.

## Unreleased

Initial public release.

### Added

- `auto_contrast` (default on) keeps an auto project's text readable on the
  background livery derives for it. Auto projects take a derived background but
  keep the terminal profile's palette, and a background the profile was never
  chosen for can make that palette unreadable. On stock Ubuntu 22.04 it does:
  `PS1` paints the path with `01;34`, and the profile's `ansi4 #12488b` /
  `ansi12 #2a7bde` measure 1.17:1 and 2.51:1 against an auto background at
  `auto_lightness 18` — against the profile's own `#300a24` they are 1.95:1 and
  4.17:1, so that blue was never readable on a dark background. Configured rules
  override both slots by hand for this reason; an auto project has nobody to do
  it. Each slot below `auto_min_contrast` (default 450, WCAG AA) is now replaced
  by the profile's own colour at the same hue and saturation, moved the shortest
  distance in lightness that clears the floor: `ansi12 #2a7bde` becomes
  `#7eafeb` at 4.64:1. Slots already clearing the floor are left alone — nine of
  fifteen change on the stock palette — so the palette stays recognisably the
  profile's rather than being re-themed. `ansi0`/`ansi8` are exempt, as they
  already are from `livery test`'s threshold, and `ansi1`/`ansi4`/`ansi5` are
  solved against two floors rather than one (below).

  The floor is deliberately not `min_contrast`: 7:1 is the target for palettes
  written by hand, and repairing to it would rewrite eleven of fifteen stock
  slots. `auto_contrast off` restores the previous behaviour.

  The profile's own values can only come from the terminal, so they are read
  once with an `OSC 4` query per slot and cached in `~/.cache/livery/palette` —
  at source time, before any project colour is applied, since a later snapshot
  would record whichever project was on screen. Repair itself is one awk fork
  solving the lightness ramp for the whole set, ~14 ms on the directory change
  that triggers it. `livery forget` clears both caches; `livery status` reports
  how many slots are known.
- `on_color_contrast` (default 300, WCAG AA for large text) governs the slots a
  program paints *as* a background. An ANSI slot is addressed in two roles —
  `\e[31m` as text, `\e[41m` as a background — and contrast against the project
  background covers only the first. The two pull opposite ways: lightening a
  slot until it reads as text is exactly what makes it illegible under the text
  a program puts on it. Symfony Console prints its error block as `\e[37;41m`,
  `ansi7` on `ansi1`, so `composer` and `drush` are where this shows up.

  `ansi1`, `ansi4` and `ansi5` are the slots convention pairs with light text
  (`fg=white;bg=red`, `bg=blue;fg=white`), so they carry a ceiling as well as a
  floor. Green, yellow and cyan are omitted: convention pairs them with black
  text (`fg=black;bg=green`), which their lightness already suits. The bright
  bank is omitted because `\e[101m`-style backgrounds are rare enough that
  constraining it would cost text contrast for nothing.

  One value cannot clear AA in both roles at once, so `high-contrast-dark` now
  splits the banks by role: `ansi1..ansi7` mid-tone and safe in both,
  `ansi9..ansi15` light and tuned for text. `ansi1` moves from `#ff9a9a` to
  `#eb0000`, taking the error block from 1.32:1 to 3.00:1 while dropping red
  text from 9.46:1 to 4.15:1; `ansi4` and `ansi5` move the same way. The split
  assumes `bold-is-bright` is on in the terminal profile, which is what sends
  `\e[1;31m` — bold red text, what `grep`, `pytest` and `npm` emit — to the
  bright bank at 9.51:1. livery does not change your profile; the README gives
  the `gsettings` line.

  Repair solves these slots for the on-colour floor first and takes the most
  background contrast available under it, rather than the least movement from
  the profile. It resolves `ansi7` ahead of them in the same awk pass, since
  `ansi7` is the text they must hold and can itself be repaired — solving
  against the profile value it is about to stop being would leave the figure
  `livery test` reports different from the one repair aimed at.

  `livery test` prints both figures and marks these slots `(two-sided)`,
  exempting them from `min_contrast` the way `ansi0`/`ansi8` are exempt as
  structural. `livery audit` reports the worst of each role separately; one
  combined figure would call a palette clean while half of it was unreadable.
- `livery preview` draws the path and `user@host` swatches from `ansi12` and
  `ansi10`, falling back to the normal slot when only that one is set. `PS1`
  paints both bold, so with `bold-is-bright` on they render from the bright
  bank; drawing them from the normal bank showed the darker two-sided value
  rather than the prompt it is previewing.
- `livery suggest` solves `ansi4` and `ansi12` separately rather than handing
  the same bright value to both: `ansi12` takes the prompt path, `ansi4` takes
  the darkest-but-most-contrasting value at that hue which still holds light
  text, since a program can paint it as a background. It reports both figures.
  Giving both slots one bright value made every generated rule illegible under
  `\e[37;44m`.
- `livery suggest <dir> [#brand]` proposes a non-colliding rule: it searches
  hues and lightnesses, scores candidates by perceptual distance to every
  configured background, and reports the contrast figures. Distinctness is a
  constraint and brand fidelity the thing minimised against it, so it also tells
  you how far a crowded brand hue had to rotate. What it predicts is what livery
  produces — the suite round-trips a suggestion through resolution.
- `livery preview` draws every configured project as a swatch showing its real
  prompt appearance, so the whole set can be reviewed at once. It uses SGR text
  colour only and emits no OSC, so it cannot change the terminal's own colours.

### Changed

- `livery test` and `livery audit` now measure auto projects. They previously
  covered configured rules only: `livery test` on an auto directory printed a
  label, a background and a fade time with no contrast rows at all, and `audit`
  iterated the rule list. That is how a 1.17:1 prompt colour survived — the 7:1
  minimum the config claimed applied to twelve projects, while 119 auto ones ran
  unmeasured on whatever the profile gave. `livery test` now prints a row per
  text slot, marking each as repaired or as the profile's own; `audit` has an
  auto section, reports the lowest auto text contrast against its own floor
  separately from the rules against theirs, and names any project still below
  it.
- `livery audit` now reports background separation as two figures rather than
  one: the closest pair among rules, and the closest auto-to-rule pair. The
  single ΔE it used to print became meaningless once auto projects were
  included — the hue ring holds 18 colours at one lightness, so with more auto
  projects than that, identical backgrounds are arithmetic rather than a defect,
  and ΔE 0.0 would bury both numbers that do mean something. The distinct-colour
  count is reported alongside.
- Auto-assigned colors now occupy their own lightness band (`auto_lightness`,
  default 18) instead of sharing the configured one. Competing for hues did not
  work: at a shared lightness, perceptual difference between dark colors is
  dominated by lightness, so eleven of the fourteen auto colors sat within ΔE 8
  of a configured project and the closest was ΔE 1.6 — an unlisted directory
  looked exactly like a client. Now none are within ΔE 8, the worst is 9.7, and
  there are 18 colors rather than 14.

### Fixed before release

Found in review, all reproduced before fixing:

- A theme that omits a slot no longer inherits the previous project's value.
  Application emitted only the keys a theme defined, so moving from a full theme
  to a hue-only one silently kept the old foreground, cursor and all 16 palette
  entries. Omitted slots are now reset to the profile's own values.
- `tools/terminal-probe.sh` no longer sends a global `OSC 104`/`110`/`111`/`112`
  on exit, which reset all sixteen palette entries including ones it never
  probed. It also now disables echo *before* the first query, so replies no
  longer leak onto the screen as garbage, and its interrupt trap restores the
  in-flight colour rather than only tty settings.
- `livery doctor` reapplies the project scheme when it finishes. It reset the
  terminal without clearing `_LIVERY_LAST_PWD`, so the next prompt returned
  early and left the terminal on profile defaults.
- `livery reload` now applies what it reloaded: it invalidates the memoised
  default background so a changed `default_bg` takes effect, and resets the
  terminal when `enable` has been turned off. Sourcing livery with `enable off`
  no longer installs title handling or queries the terminal.
- `alpha` is accepted as a per-rule key. It was rejected as an unknown key while
  tint mode silently used the global value.
- A scheme naming no background returns to the profile background instead of
  keeping the previous project's. Only non-background slots were being reset, so
  a foreground-only rule — or one whose background was dropped as unparseable —
  inherited the last colour.
- `livery doctor` proves resets by planting a sentinel first. Comparing before
  and after could not distinguish success from failure when a slot was already
  at its default, so it reported working resets as broken.
- `tools/terminal-probe.sh` compares whole normalised colours instead of
  matching a substring of the reply, and checks that a reply is for the code and
  index it asked about. It previously called a terminal supported when only the
  red channel changed, or when the existing colour happened to start with the
  same digits.
- `alpha`, `lightness` and `saturation` are bounded to 0–100. `alpha=200`
  produced a wider-than-six-digit "colour" that normalisation then dropped.
- `livery audit` reports `n/a` when no text colours were measured, rather than a
  fictional `999.99:1`.
- `test/mockterm.py` flushes its trailing buffer, so the last 64 bytes of a run
  are no longer silently lost — that had been hiding output from assertions.
- The contrast and ΔE maths no longer use `strtonum()`, a GNU awk extension
  absent from mawk. Fixing this also corrected the ΔE figures: the previous
  implementation omitted the piecewise branch of the CIELAB transfer function,
  which matters precisely because these backgrounds are very dark.

- Recolour the terminal background per project directory, with a fade.
- Full theme control: background, foreground, bold, cursor and all 16 ANSI
  palette entries (`OSC 4`), so prompt colours can carry project identity.
- `mode=dark` derives backgrounds by pinning an accent's hue to a low lightness,
  rather than blending toward the accent. Blending a dark background toward a
  bright accent raises luminance, which makes every project *lighter* than the
  profile default.
- Theme files in `~/.config/livery/themes`, overridable per rule.
- Tab labels from the project name, appended to `PS1` so they survive a program
  setting its own title.
- `livery audit` reports contrast per colour and perceptual distance between
  backgrounds across every configured rule.
- `livery doctor` probes which colours the terminal actually honours, and
  verifies that resets restore rather than only that setting works.
- Test suites: colour maths, behaviour against a mock terminal on a pty,
  interactive-shell prompt integrity, and an opt-in real-terminal suite.
