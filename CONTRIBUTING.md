# Contributing

## Running the tests

```bash
./test/run-tests.sh                  # headless: opens no windows, steals no focus
./test/run-tests.sh --real-terminal  # also drives a real gnome-terminal
```

The headless suites need bash 4+ and Python 3. They open no windows and are safe
to run while you work.

`--real-terminal` opens a terminal window that **takes keyboard focus while it
runs**, so anything you type lands in it. Run it only when you are away from the
keyboard.

## The rule that matters

**Anything touching `PROMPT_COMMAND` or `PS1` must be tested against a real
interactive shell, compared against a control run without livery loaded.**

This is not a style preference. An earlier version of this tool passed 43
assertions — every one of which read colours back off the terminal rather than
trusting the escape sequence — while making an interactive shell unusable: no
prompt, no echo of typed input. The colour tests could not see it, because they
only ever asked "was the colour set correctly?"

`test/prompt.py` exists for that class of bug. It drives a real bash on a pty
and compares prompt count, input echo, command output and titles against a
control. If you change the hook, that suite is the one that matters.

## Testing terminal escape sequences

`test/mockterm.py` is a small terminal emulator on a pty. It speaks the `OSC`
subset livery uses, answers queries, and records every colour it is told to use
plus any byte that falls **outside** a well-formed sequence. That last part
catches malformed output that would otherwise print to the screen as garbage.

Prefer it over spawning real terminals: it is deterministic, fast, and does not
steal focus. Its limit is that it is not a real emulator, so it cannot reproduce
emulator-specific behaviour — that is what `--real-terminal` and `livery doctor`
are for.

## Verifying colour work

Do not eyeball contrast. `livery test <dir>` prints the resolved theme with a
measured WCAG ratio per colour, and `livery audit` checks every configured rule
plus how far apart the backgrounds are perceptually (CIELAB ΔE). Both are
cheaper than an opinion and they disagree with intuition often enough to matter.

## Checking terminal support

`tools/terminal-probe.sh` is deliberately POSIX `sh` with no arrays, no
`[[ ]]` and no `read -t`/`-d`, so it runs under sh, zsh and bash 3.2. It exists
so the *terminal* question can be answered separately from the *shell* question
— useful when someone on a shell livery does not support wants to know whether
porting is even worthwhile.

Keep it dependency-free and keep it restoring what it changes.

## Shell support

bash 4+ only. The hook uses associative arrays, `printf -v`, `PROMPT_COMMAND`
and bash prompt-escape markers. A zsh port should not duplicate this logic —
split the engine into a command that is executed rather than sourced, leaving a
thin per-shell hook. zsh's `chpwd` is a better fit than `PROMPT_COMMAND`.

Note that macOS ships bash 3.2, which lacks associative arrays, so livery needs
a newer bash there even before the zsh question.
