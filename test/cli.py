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


def _lin(c):
    c = c / 255.0
    return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4

def lum(hexstr):
    r, g, b = (int(hexstr[i:i + 2], 16) for i in (0, 2, 4))
    return 0.2126 * _lin(r) + 0.7152 * _lin(g) + 0.0722 * _lin(b)

def contrast(a, b):
    """WCAG 2.1 contrast ratio, x100 and rounded -- what livery reports."""
    la, lb = lum(a), lum(b)
    if la < lb:
        la, lb = lb, la
    return int(((la + 0.05) / (lb + 0.05)) * 100 + 0.5)

def MockDefault(key):
    """The palette test/mockterm.py starts with, mirrored here on purpose: a
    test that asked the mock what it had set would prove nothing."""
    if key.startswith('ansi'):
        v = int(key[4:]) * 16
        return '%02x%02x%02x' % (v, v, v)
    return {'fg': 'ffffff', 'bg': '300a24', 'cursor': 'ffffff'}[key]

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

        print('== livery preview ==')
        prevconf = os.path.join(root, 'conf-prev')
        os.makedirs(os.path.join(root, 'p2'), exist_ok=True)
        write(prevconf, f'set default_bg #300a24\nset auto off\n'
                        f'rule {root}/proj accent=#61afef\n'
                        f'rule {root}/p2   accent=#e06c75\n')
        drvp = os.path.join(root, 'prev.sh')
        write(drvp, 'source "$LIVERY_SH"\nlivery preview\n')
        rep, err = run(drvp, {'LIVERY_CONF': prevconf})
        if rep is None:
            print('  harness failed:', err); return 1
        s2 = rep.get('stray', '')
        chk('draws a swatch per rule', 2, s2.count('user@host'))
        chk('uses truecolor background SGR', True, '48;2;' in s2)
        chk('resets colour after each swatch', True, '[0m' in s2)
        # the important one: preview must not touch the terminal's real colours
        chk('emits no OSC at all', 1, len(rep['frames']['bg']))
        chk('terminal left on its defaults', '300a24', rep['final']['bg'])

        print('== livery suggest ==')
        drvs = os.path.join(root, 'sug.sh')
        write(drvs, 'source "$LIVERY_SH"\nlivery suggest /tmp/does-not-matter "#0058A4"\n')
        rep, err = run(drvs, {'LIVERY_CONF': prevconf}, timeout=300)
        if rep is None:
            print('  harness failed:', err); return 1
        s3 = rep.get('stray', '')
        import re as _re
        rule = _re.search(r'rule \S+\s+(theme=\S+ accent=#([0-9a-f]{6}) lightness=(\d+).*)', s3)
        chk('prints a pasteable rule', True, rule is not None)
        pred = _re.search(r'background\s+#([0-9a-f]{6})\s+dE ([0-9.]+)', s3)
        chk('reports the background and its separation', True, pred is not None)
        # ansi4 and ansi12 must not be the same value. Handing the bright prompt
        # colour to both is what made every generated rule illegible under
        # \e[37;44m, the same defect the shipped theme had.
        a4 = _re.search(r'ansi4=#([0-9a-f]{6})', s3)
        a12 = _re.search(r'ansi12=#([0-9a-f]{6})', s3)
        chk('suggests both prompt slots', True, a4 is not None and a12 is not None)
        if a4 and a12:
            chk('ansi4 is not the bright ansi12 value', True,
                a4.group(1) != a12.group(1))
            # and the mid-tone one is the darker of the two
            chk('ansi4 is the darker of the pair', True,
                contrast(a4.group(1), 'ffffff') > contrast(a12.group(1), 'ffffff'))
        chk('reports what ansi4 holds as a background', True,
            'holds light text at' in s3)
        if rule and pred:
            chk('separation clears dE 8', True, float(pred.group(2)) >= 8.0)
            # round trip: applying the suggestion must produce what it predicted
            rt = os.path.join(root, 'rt'); os.makedirs(rt, exist_ok=True)
            rtconf = os.path.join(root, 'conf-rt')
            write(rtconf, f'set default_bg #300a24\nset auto off\nrule {rt} {rule.group(1).strip()}\n')
            drvr = os.path.join(root, 'rt.sh')
            write(drvr, 'mark(){ printf "\\033]777;mark;%s\\033\\\\" "$1" >/dev/tty; }\n'
                        'source "$LIVERY_SH"\n'
                        f'cd {rt} && _livery_hook; mark applied\n')
            rep2, _ = run(drvr, {'LIVERY_CONF': rtconf})
            got = {k['name']: k for k in rep2['marks'] if k.get('name') != '__title__'}['applied']['bg']
            chk('applying the suggestion reproduces the predicted colour',
                pred.group(1), got)
        for slot in ('path', 'user@host'):
            mm = _re.search(slot.replace('@', '@') + r'\s+#[0-9a-f]{6}\s+([0-9.]+):1', s3)
            chk(f'{slot} contrast reported and >= 7.5', True,
                mm is not None and float(mm.group(1)) >= 7.5)

        # An auto project takes a derived background and keeps the terminal
        # profile's palette. Nothing used to check that the palette was readable
        # on that background: the stock Ubuntu blue measures 1.17:1 on one, and
        # `livery test` printed no contrast rows for auto projects at all. This
        # asserts the colours the terminal is actually left holding.
        print('== auto projects: every text slot the terminal is left with ==')
        aroot = os.path.join(root, 'autoroot')
        os.makedirs(os.path.join(aroot, 'someproj'), exist_ok=True)
        acache = os.path.join(root, 'acache')
        aconf = os.path.join(root, 'conf-auto')
        write(aconf, f'set default_bg #300a24\nset auto on\nset auto_root {aroot}\n'
                     f'set auto_lightness 18\nset auto_min_contrast 450\n')
        drva = os.path.join(root, 'auto.sh')
        write(drva, 'source "$LIVERY_SH"\n'
                    f'cd {aroot}/someproj && _livery_hook\n')
        rep, err = run(drva, {'LIVERY_CONF': aconf, 'LIVERY_CACHE': acache})
        if rep is None:
            print('  harness failed:', err); return 1
        fin = rep['final']
        bg = fin['bg']
        chk('the auto background was applied', True, bg != '300a24')

        FLOOR = 450
        ONFLOOR = 300
        # ansi1/ansi4/ansi5 are two-sided: programs paint them as a background
        # as well as as text, so they are held to the on-colour floor instead
        # and cannot be judged by the text floor alone.
        TWOSIDED = ['ansi1', 'ansi4', 'ansi5']
        TEXT = ['fg'] + [f'ansi{i}' for i in list(range(1, 8)) + list(range(9, 16))
                         if f'ansi{i}' not in TWOSIDED]
        bad = {k: contrast(fin[k], bg) for k in TEXT if contrast(fin[k], bg) < FLOOR}
        chk('no text slot is left below the 4.50:1 floor', {}, bad)

        # the sharp one: the mock's profile blue is #404040, unreadable on any
        # dark background, and it is the slot a stock PS1 paints the path with
        chk('ansi4 no longer holds the unreadable profile value', True,
            fin['ansi4'] != '404040')
        # and the reported bug: the same slots have to hold the light text a
        # program puts on them. \e[37;41m is ansi7 on ansi1.
        onbad = {k: contrast(fin[k], fin['ansi7']) for k in TWOSIDED
                 if contrast(fin[k], fin['ansi7']) < ONFLOOR}
        chk('every two-sided slot holds ansi7 text', {}, onbad)

        # structural slots are exempt by documented design, so they must be left
        # exactly as the profile had them
        chk('ansi0 left at the profile value', '000000', fin['ansi0'])
        chk('ansi8 left at the profile value', '808080', fin['ansi8'])

        # a slot that was already readable must not be rewritten, or an auto
        # project stops being distinguishable from a configured one
        chk('an already-readable slot is untouched', 'f0f0f0', fin['ansi15'])
        chk('some slots were left to the profile', True,
            sum(1 for k in TEXT if fin[k] == MockDefault(k)) > 0)

        # the snapshot is cached, so only the first shell pays for the queries
        pf = os.path.join(acache, 'palette')
        chk('the profile palette was cached', True, os.path.exists(pf))
        if os.path.exists(pf):
            with open(pf) as fh:
                lines = [l for l in fh.read().splitlines() if l.strip()]
            chk('cache holds every non-structural slot', 15, len(lines))
            chk('cache records the profile value, not the repaired one', True,
                'ansi4 404040' in lines)

        print('== auto_contrast off keeps the profile palette untouched ==')
        aconf2 = os.path.join(root, 'conf-auto-off')
        write(aconf2, f'set default_bg #300a24\nset auto on\nset auto_root {aroot}\n'
                      f'set auto_lightness 18\nset auto_contrast off\n')
        rep2, err = run(drva, {'LIVERY_CONF': aconf2,
                               'LIVERY_CACHE': os.path.join(root, 'acache2')})
        if rep2 is None:
            print('  harness failed:', err); return 1
        chk('the background still changes', True, rep2['final']['bg'] != '300a24')
        chk('ansi4 is left at the profile value', '404040', rep2['final']['ansi4'])

        print('== livery test reports contrast for an auto project ==')
        drvt = os.path.join(root, 'autotest.sh')
        write(drvt, 'source "$LIVERY_SH"\n'
                    f'livery test {aroot}/someproj\n')
        rep3, err = run(drvt, {'LIVERY_CONF': aconf, 'LIVERY_CACHE': acache})
        if rep3 is None:
            print('  harness failed:', err); return 1
        s4 = rep3.get('stray', '')
        chk('names the floor it measured against', True, 'contrast floor 4.50:1' in s4)
        chk('measures every text slot, not just the background', 15,
            s4.count('contrast vs bg'))
        chk('says which slots it repaired', True, '(repaired from #404040)' in s4)
        chk('says which slots are the profile\'s own', True, '(profile)' in s4)
        # Both roles are reported, because measuring only the text role is how
        # an illegible `\e[37;41m` error block measured clean.
        chk('reports the background role too', 3, s4.count('text on it'))
        chk('reports it only for the two-sided slots', True,
            all(f'ansi{n}' in l for n, l in
                zip((1, 4, 5), [l for l in s4.splitlines() if 'text on it' in l])))
        # The mock profile is a grey ramp, so a two-sided slot has the same hue
        # as the text it must carry and cannot clear both floors -- it is
        # reported LOW rather than silently left broken. The text-only slots
        # have one floor and must all clear it.
        onesided = [l for l in s4.splitlines()
                    if 'contrast vs bg' in l and 'text on it' not in l]
        chk('every text-only slot clears its floor', [],
            [l.split()[0] for l in onesided if 'LOW' in l])
        # A two-sided slot is labelled, not flagged against the text floor --
        # the same treatment ansi0/ansi8 get as structural.
        chk('two-sided slots are labelled as such', 3, s4.count('(two-sided)'))

        print('== livery audit covers auto projects ==')
        drvau = os.path.join(root, 'autoaudit.sh')
        write(drvau, 'source "$LIVERY_SH"\nlivery audit\n')
        rep4, err = run(drvau, {'LIVERY_CONF': aconf, 'LIVERY_CACHE': acache})
        if rep4 is None:
            print('  harness failed:', err); return 1
        s5 = rep4.get('stray', '')
        chk('has an auto section', True, 'auto projects under' in s5)
        # Two-sided slots are judged by the on-colour floor, not the text one,
        # so they stay out of this tally -- and on the mock's grey ramp, where
        # hue cannot separate a slot from the text it must carry, they are what
        # the on-colour tally reports.
        chk('reports the auto floor', True, 'auto below floor    : 0' in s5)
        chk('reports the background role', True, 'lowest text ON a slot' in s5)
        chk('counts the two-sided slots separately', True,
            'slots below that     : 0 of 3' in s5)
        chk('measured auto text colours', True, 'auto,  lowest text' in s5)

        print()
        print(f'pass={P} fail={F}')
        return 1 if F else 0
    finally:
        shutil.rmtree(root, ignore_errors=True)

sys.exit(main())
