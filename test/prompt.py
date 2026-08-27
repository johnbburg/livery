#!/usr/bin/env python3
"""Interactive-shell tests: the prompt must still be drawn and typed input
must still echo while livery is loaded.

This is the case the colour tests could not see. They asserted that colours
were set correctly and passed while the shell was, in fact, refusing to draw a
prompt or echo keystrokes. Anything touching PROMPT_COMMAND must be checked
against a real interactive bash on a pty, comparing against a control run.
"""
import os, pty, re, select, shutil, subprocess, sys, tempfile, time

HERE = os.path.dirname(os.path.abspath(__file__))
LIVERY_SH = os.environ.get('LIVERY_SH', os.path.join(HERE, '..', 'livery.sh'))
PROMPT = 'LVTESTPROMPT$ '
P = F = 0

def chk(desc, want, got):
    global P, F
    if want == got:
        P += 1; print(f'  ok   {desc}  ({got})')
    else:
        F += 1; print(f'  FAIL {desc}  got={got!r} want={want!r}')

def session(rc_extra, root):
    """Run an interactive bash on a pty; return its full output."""
    rc = os.path.join(root, 'rc')
    with open(rc, 'w') as fh:
        fh.write(f'PS1="{PROMPT}"\n{rc_extra}\n')
    cmds = ['echo ONE', f'cd {root}/proj-a', 'echo TWO', f'cd {root}', 'echo THREE', 'exit']
    pid, fd = pty.fork()
    if pid == 0:
        os.environ['TERM'] = 'xterm-256color'
        os.execvp('bash', ['bash', '--rcfile', rc, '-i'])
    out = b''
    def drain(sec):
        nonlocal out
        end = time.time() + sec
        while time.time() < end:
            r, _, _ = select.select([fd], [], [], 0.1)
            if r:
                try: d = os.read(fd, 65536)
                except OSError: return False
                if not d: return False
                out += d
        return True
    drain(1.5)
    for c in cmds:
        os.write(fd, (c + '\n').encode())
        if not drain(1.5):
            break
    try:
        os.close(fd); os.waitpid(pid, 0)
    except OSError:
        pass
    return out

def main():
    root = tempfile.mkdtemp(prefix='livery-prompt-')
    try:
        os.makedirs(os.path.join(root, 'proj-a'), exist_ok=True)
        conf = os.path.join(root, 'conf')
        with open(conf, 'w') as fh:
            fh.write('set default_bg  #300a24\nset alpha 20\nset auto off\n'
                     f'rule {root}/proj-a  accent=#61afef\n')
        sh = os.path.abspath(LIVERY_SH)
        load = f'export LIVERY_CONF={conf}; source {sh}'

        base = session('', root)
        want_prompts = base.count(PROMPT.encode())
        want_echo = base.count(b'echo ONE')
        print(f'== control: {want_prompts} prompts, typed command echoed {want_echo}x ==')
        chk('control draws prompts at all', True, want_prompts >= 4)
        chk('control echoes typed input', True, want_echo >= 1)

        cases = [
            ('livery loaded, default fade', load),
            ('fade_steps=32',               load + '; _LIVERY_O_fade_steps=32'),
            ('sleep(1) fallback',           load + '; _LIVERY_SLEEPFD=none'),
            ('fade_steps=1 (instant)',      load + '; _LIVERY_O_fade_steps=1'),
            ('title on',                    load + '; _LIVERY_O_title=on; _livery_install_title'),
        ]
        for name, rc in cases:
            out = session(rc, root)
            print(f'== {name} ==')
            chk('prompt count matches control', want_prompts, out.count(PROMPT.encode()))
            chk('typed input echoes as in control', want_echo, out.count(b'echo ONE'))
            chk('command output still appears', True, b'THREE' in out)
            chk('the recolor still happened', True, out.count(b'\x1b]11;') > 0)

        print('== tab title: must beat a PS1 that sets its own title ==')
        # mimic the stock Ubuntu ~/.bashrc, which puts a title escape in PS1
        rc = ('PS1="\\[\\e]0;user@host: \\w\\a\\]' + PROMPT + '"\n'
              + load + '; _LIVERY_O_title=on; _livery_install_title')
        out = session(rc, root)
        titles = [t.decode() for t in re.findall(rb'\x1b\]0;([^\x07]*)\x07', out)]
        chk('some titles were emitted', True, len(titles) > 0)
        chk('the PS1 title is present too', True,
            any(t.startswith('user@host') for t in titles))
        chk('livery wins: project name is the LAST title before the cd back', True,
            'proj-a' in titles)
        # One prompt render emits: [PS1 title][prompt text][livery title]. So the
        # invariant is that every PS1 title is immediately followed by a livery
        # one -- livery gets the last word each time, which is what makes the
        # tab label stick. Comparing across renders instead would false-fail,
        # since the next render's PS1 title follows the previous livery title.
        ps1_idx = [i for i, t in enumerate(titles) if t.startswith('user@host')]
        unanswered = [i for i in ps1_idx
                      if i + 1 >= len(titles) or titles[i + 1].startswith('user@host')]
        chk('every PS1 title is overridden by a livery title', [], unanswered)
        chk('prompt count still matches control', want_prompts, out.count(PROMPT.encode()))

        print()
        print(f'pass={P} fail={F}')
        return 1 if F else 0
    finally:
        shutil.rmtree(root, ignore_errors=True)

sys.exit(main())
