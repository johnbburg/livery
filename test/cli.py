#!/usr/bin/env python3
"""CLI-level tests against the mock terminal.

These cover the paths the colour suites do not: the standalone probe, `livery
doctor`, `livery audit` and `livery reload`. All of them need a terminal that
answers OSC queries, which the mock provides — so none of this needs a window
and none of it steals focus.
"""
import json, os, shutil, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
LIVERY_SH = os.path.abspath(os.environ.get('LIVERY_SH', os.path.join(HERE, '..', 'livery.sh')))
PROBE = os.path.join(HERE, '..', 'tools', 'terminal-probe.sh')
P = F = 0

def chk(desc, want, got):
    global P, F
    if want == got:
        P += 1; print(f'  ok   {desc}  ({got})')
    else:
        F += 1; print(f'  FAIL {desc}  got={got!r} want={want!r}')

def run(script, env=None, timeout=180):
    e = dict(os.environ, LIVERY_FORCE='1', LIVERY_SH=LIVERY_SH, **(env or {}))
    out = subprocess.run([sys.executable, os.path.join(HERE, 'mockterm.py'), script],
                         capture_output=True, text=True, env=e, timeout=timeout)
    if out.returncode != 0:
        return None, out.stderr[-800:]
    return json.loads(out.stdout), ''

def write(path, text):
    with open(path, 'w') as fh:
        fh.write(text)
    os.chmod(path, 0o755)

def main():
    root = tempfile.mkdtemp(prefix='livery-cli-')
    try:
        print('== standalone probe against a terminal that supports everything ==')
        rep, err = run(os.path.abspath(PROBE))
        if rep is None:
            print('  harness failed:', err); return 1
        stray = rep.get('stray', '')
        chk('reports all six slots settable', 6, stray.count('YES'))
        chk('reaches the "all supported" verdict', True, 'All supported' in stray)
        defaults = {f'ansi{i}': '%02x%02x%02x' % (i * 16, i * 16, i * 16) for i in range(16)}
        chk('leaves the whole palette untouched', [],
            [k for k, v in defaults.items() if rep['final'][k] != v])
        chk('restores bg/fg/cursor exactly', ['300a24', 'ffffff', 'ffffff'],
            [rep['final']['bg'], rep['final']['fg'], rep['final']['cursor']])
        chk('sends no global palette reset', 1, len(rep['frames']['ansi0']))

        print('== livery doctor ==')
        os.makedirs(os.path.join(root, 'proj'), exist_ok=True)
        conf = os.path.join(root, 'conf')
        write(conf, f'set default_bg #300a24\nset auto off\n'
                    f'rule {root}/proj accent=#61afef\n')
        drv = os.path.join(root, 'doctor.sh')
        write(drv, f'source "$LIVERY_SH"\ncd {root}/proj && _livery_hook\nlivery doctor\n')
        rep, err = run(drv, {'LIVERY_CONF': conf})
        if rep is None:
            print('  harness failed:', err); return 1
        s = rep.get('stray', '')
        chk('probes every colour slot as settable', 6, s.count('settable: yes'))
        chk('proves resets work via the sentinel', True, 'sentinel cleared' in s)
        chk('never claims a reset failed', False, 'does NOT work' in s)
        chk('reapplies the project scheme afterwards', '071a2b', rep['final']['bg'])

        print('== livery audit with backgrounds but no text colours ==')
        conf2 = os.path.join(root, 'conf2')
        write(conf2, f'set default_bg #300a24\nset auto off\nrule {root}/proj bg=#123456\n')
        drv2 = os.path.join(root, 'audit.sh')
        write(drv2, 'source "$LIVERY_SH"\nlivery audit\n')
        rep, err = run(drv2, {'LIVERY_CONF': conf2})
        s = rep.get('stray', '') if rep else ''
        chk('reports n/a rather than a fictional ratio', True,
            'n/a (no text colours' in s)
        chk('does not print an invented 999 ratio', False, '999' in s)

        print('== livery reload ==')
        conf3 = os.path.join(root, 'conf3')
        write(conf3, f'set default_bg #300a24\nset auto off\nrule {root}/proj accent=#61afef\n')
        drv3 = os.path.join(root, 'reload.sh')
        write(drv3,
              'mark(){ printf "\\033]777;mark;%s\\033\\\\" "$1" >/dev/tty; }\n'
              'source "$LIVERY_SH"\n'
              f'cd {root}/proj && _livery_hook; mark applied\n'
              f'printf "set default_bg #300a24\\nset auto off\\nset enable off\\nrule {root}/proj accent=#61afef\\n" > {conf3}\n'
              'livery reload >/dev/null 2>&1; mark disabled\n')
        rep, err = run(drv3, {'LIVERY_CONF': conf3})
        if rep is None:
            print('  harness failed:', err); return 1
        m = {k['name']: k for k in rep['marks'] if k.get('name') != '__title__'}
        chk('the scheme applied first', '071a2b', m['applied']['bg'])
        chk('reload with enable=off resets the terminal', '300a24', m['disabled']['bg'])

        print()
        print(f'pass={P} fail={F}')
        return 1 if F else 0
    finally:
        shutil.rmtree(root, ignore_errors=True)

sys.exit(main())
