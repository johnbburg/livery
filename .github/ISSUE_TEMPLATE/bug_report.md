---
name: Bug report
about: Something does not work
labels: bug
---

## What happened

<!-- What you saw, and what you expected instead. -->

## Terminal support

livery depends on escape sequences that terminals implement inconsistently.
Please paste the output of `livery doctor` — it is the single most useful thing
in a report, and it answers most questions about whether a colour can work at
all in your terminal.

```
<paste `livery doctor` output here>
```

If livery will not load at all — a shell other than bash 4+, for instance — run
the standalone probe instead, which needs no installation:

```
sh tools/terminal-probe.sh
```

## Environment

- Terminal emulator and version:
- `echo $TERM`:
- `echo $BASH_VERSION`:
- OS / distribution:
- Output of `livery status`:

## Reproducing

<!-- Minimal steps. If it involves the prompt disappearing or input not
     echoing, please say which command or directory change triggered it. -->
