# Changelog

Notable changes, newest first. Dates are ISO 8601.

## Unreleased

Initial public release.

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
