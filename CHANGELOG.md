# Changelog

Notable changes, newest first. Dates are ISO 8601.

## Unreleased

Initial public release.

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
