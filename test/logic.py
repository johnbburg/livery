#!/usr/bin/env python3
"""Logic tests for livery.sh against the mock terminal.

Expected colours are computed here independently of livery.sh's shell arithmetic,
so the two implementations have to agree.
"""
import json, os, shutil, subprocess, sys, tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
LIVERY_SH = os.environ.get('LIVERY_SH', os.path.join(HERE, '..', 'livery.sh'))
DEFAULT_BG, ALPHA, STEPS, FADE_MS = '300a24', 20, 6, 60

P = F = 0
def chk(desc, want, got):
    global P, F
    if want == got:
        P += 1; print(f'  ok   {desc}  ({got})')
    else:
        F += 1; print(f'  FAIL {desc}  got={got!r} want={want!r}')

import colorsys

def rgb(h): return tuple(int(h[i:i+2], 16) for i in (0, 2, 4))
def hsl(h):
    r, g, b = (c / 255 for c in rgb(h))
    hh, ll, ss = colorsys.rgb_to_hls(r, g, b)
    return round(hh * 360), round(ss * 100), round(ll * 100)
def lumin(h):
    def ch(v):
        v /= 255
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = (ch(c) for c in rgb(h))
    return .2126 * r + .7152 * g + .0722 * b
def hexs(t): return '%02x%02x%02x' % t
def blend(base, accent, pct):
    return hexs(tuple((b*(100-pct) + a*pct + 50)//100 for b, a in zip(rgb(base), rgb(accent))))

THEME = {
    'bg': '0b0f14', 'fg': 'dfe6ee', 'cursor': 'ffcc66', 'bold': 'ffffff',
    **{f'ansi{i}': v for i, v in enumerate([
        '20262e', 'ff8080', '8fdf82', 'ffd479', '79b8ff', 'e59bff', '6fe0e0', 'c8d1db',
        '5a6472', 'ff9aa2', 'b6f0a8', 'ffe6a8', 'a8d3ff', 'f0c2ff', 'a6f0f0', 'ffffff'])},
}

def build_fixture(root):
    for d in ('proj-a/sub', 'proj-b', 'proj-loud', 'proj-theme', 'proj-override',
              'proj-dark', 'proj-theme-accent', 'proj-theme-bg',
              'auto/alpha-proj', 'auto/beta-proj', 'themes'):
        os.makedirs(os.path.join(root, d), exist_ok=True)
    with open(os.path.join(root, 'themes', 'tst.conf'), 'w') as fh:
        fh.write('# a theme, with comments and blank lines to parse past\n\n')
        for k, v in THEME.items():
            fh.write(f'{k}   #{v}    # trailing comment\n')
    conf = os.path.join(root, 'conf')
    with open(conf, 'w') as fh:
        fh.write(f"""set default_bg  #{DEFAULT_BG}
set alpha       {ALPHA}
set fade_ms     {FADE_MS}
set fade_steps  {STEPS}
set auto        on
set auto_root   {root}/auto
rule {root}/proj-a      accent=#61afef
rule {root}/proj-a/sub  accent=#98c379 lightness=20
rule {root}/proj-b      accent=#e06c75   # trailing comment
rule {root}/proj-loud   bg=#3a0d0d fg=#ffd7d7 cursor=#ff5555
rule {root}/proj-theme     theme=tst
rule {root}/proj-override  theme=tst ansi4=#112233 fg=#eeeeee
rule {root}/proj-dark      accent=#61afef lightness=10 saturation=70
rule {root}/proj-theme-accent  theme=tst accent=#61afef
rule {root}/proj-theme-bg      theme=tst bg=#010203
""")
    return conf

def main():
    root = tempfile.mkdtemp(prefix='livery-logic-')
    try:
        conf = build_fixture(root)
        env = dict(os.environ, LIVERY_SH=os.path.abspath(LIVERY_SH), HOME=os.environ['HOME'])
        out = subprocess.run(
            [sys.executable, os.path.join(HERE, 'mockterm.py'),
             os.path.join(HERE, 'logic-driver.sh'), root, conf],
            capture_output=True, text=True,
            env=dict(env, LIVERY_THEMES=os.path.join(root, 'themes')), timeout=120)
        if out.returncode != 0:
            print('harness failed:', out.stderr[-2000:]); return 1
        rep = json.loads(out.stdout)
        m = {k['name']: k for k in rep['marks'] if k['name'] != '__title__'}
        need = ['start', 'proj_a', 'proj_b', 'home', 'auto_alpha', 'livery_reset']
        missing = [n for n in need if n not in m]
        if missing:
            print('missing marks:', missing); print(json.dumps(rep, indent=1)[:3000]); return 1

        def dark_ok(desc, got, accent, want_l):
            h, sat, l = hsl(got)
            ah = hsl(accent)[0]
            chk(f'{desc}: lightness ~{want_l}', True, abs(l - want_l) <= 2)
            chk(f'{desc}: hue of #{accent} preserved', True,
                min(abs(h - ah), 360 - abs(h - ah)) <= 4)
            # only meaningful when the rule asked to be darker than the profile;
            # a rule may legitimately request a lighter background.
            if want_l < hsl(DEFAULT_BG)[2]:
                chk(f'{desc}: darker than profile default', True,
                    lumin(got) < lumin(DEFAULT_BG))

        print('== negative control ==')
        chk('a colour we never set is absent', False, '123456' in rep['frames']['bg'])

        print('== no stray bytes: every write is a well-formed sequence ==')
        stray = rep.get('stray', '')
        chk('nothing outside an OSC sequence reached the terminal', '', stray.strip())
        chk('no mangled "033]" from %b escape collapsing', False, '033]' in stray)

        print('== mode=dark: accent supplies hue, lightness is pinned ==')
        chk('start is the profile default', DEFAULT_BG, m['start']['bg'])
        dark_ok('proj-a',     m['proj_a']['bg'],     '61afef', 10)
        dark_ok('proj-a/sub', m['proj_a_sub']['bg'], '98c379', 20)   # per-rule lightness
        dark_ok('proj-b',     m['proj_b']['bg'],     'e06c75', 10)
        chk('longest prefix wins (sub != parent)', True,
            m['proj_a']['bg'] != m['proj_a_sub']['bg'])

        print('== full override, no derivation ==')
        chk('loud bg',     '3a0d0d', m['proj_loud']['bg'])
        chk('loud fg',     'ffd7d7', m['proj_loud']['fg'])
        chk('loud cursor', 'ff5555', m['proj_loud']['cursor'])

        print('== leaving a project restores profile colours ==')
        chk('bg reset',     DEFAULT_BG, m['home']['bg'])
        chk('fg reset',     'ffffff',   m['home']['fg'])
        chk('cursor reset', 'ffffff',   m['home']['cursor'])

        print('== auto mode ==')
        aa, ab = m['auto_alpha']['bg'], m['auto_beta']['bg']
        chk('alpha-proj coloured',      True, aa != DEFAULT_BG)
        chk('beta-proj differs',        True, aa != ab)
        chk('same name -> same colour', aa,   m['auto_alpha_again']['bg'])
        chk('auto colours are dark too', True, hsl(aa)[2] <= 12 and hsl(ab)[2] <= 12)

        print('== idempotency ==')
        chk('repeat hook writes no frames',
            m['auto_alpha_again']['bg_frames'], m['repeat_hook']['bg_frames'])
        chk('repeat hook keeps colour', aa, m['repeat_hook']['bg'])

        print('== off / on ==')
        chk('off leaves project colour', True, m['livery_off']['bg'] != aa)
        chk('on restores project colour', aa, m['livery_on']['bg'])
        chk('reset ends on default', DEFAULT_BG, m['livery_reset']['bg'])

        print('== the fade itself (frames captured off the wire) ==')
        frames = rep['frames']['bg']
        target = m['proj_a']['bg']
        i0, i1 = m['start']['bg_frames'], m['proj_a']['bg_frames']
        fade = frames[i0:i1]
        chk('fade emits steps+1 frames', STEPS + 1, len(fade))
        chk('fade ends exactly on target', target, fade[-1])
        chk('no frame equals the start colour', False, DEFAULT_BG in fade)
        mono = True
        for ch_i in range(3):
            seq = [rgb(f)[ch_i] for f in [DEFAULT_BG] + fade]
            lo, hi = rgb(DEFAULT_BG)[ch_i], rgb(target)[ch_i]
            step = 1 if hi >= lo else -1
            if any((b - a) * step < 0 for a, b in zip(seq, seq[1:])):
                mono = False
        chk('every channel moves monotonically', True, mono)
        chk('no frame overshoots the target', True, all(
            min(rgb(DEFAULT_BG)[c], rgb(target)[c]) <= rgb(f)[c] <= max(rgb(DEFAULT_BG)[c], rgb(target)[c])
            for f in fade for c in range(3)))

        print('== theme files: every colour reaches the terminal ==')
        t = m['proj_theme']
        chk('theme bg',     THEME['bg'],     t['bg'])
        chk('theme fg',     THEME['fg'],     t['fg'])
        chk('theme cursor', THEME['cursor'], t['cursor'])
        chk('theme bold',   THEME['bold'],   t['bold'])
        bad = [f'ansi{i}' for i in range(16) if t.get(f'ansi{i}') != THEME[f'ansi{i}']]
        chk('all 16 ANSI palette entries applied', [], bad)
        chk('no colour arrived empty', [], [k for k, v in t.items()
                                            if k.startswith(('ansi', 'fg', 'bg')) and v == ''])

        print('== inline rule keys override the theme file ==')
        o = m['proj_override']
        chk('ansi4 overridden',        '112233', o['ansi4'])
        chk('fg overridden',           'eeeeee', o['fg'])
        chk('untouched entry survives', THEME['ansi2'], o['ansi2'])

        print('== background precedence: inline bg > inline accent > theme bg ==')
        ta, tb = m['proj_theme_accent'], m['proj_theme_bg']
        chk('inline accent beats the theme bg', True, ta['bg'] != THEME['bg'])
        dark_ok('theme+accent', ta['bg'], '61afef', 10)
        chk('theme palette still applied alongside it', THEME['ansi2'], ta['ansi2'])
        chk('inline bg beats everything', '010203', tb['bg'])
        chk('theme palette applied with inline bg too', THEME['ansi2'], tb['ansi2'])
        chk('a shared theme still distinguishes projects', True,
            len({m['proj_theme']['bg'], ta['bg'], tb['bg']}) == 3)

        print('== mode=dark derives a dark background from the accent hue ==')
        d = m['proj_dark']
        h, s_, l = hsl(d['bg'])
        ah, _as, _al = hsl('61afef')
        chk('derived bg is dark (L<=12)', True, l <= 12)
        chk('hue preserved (within 4 deg)', True, min(abs(h-ah), 360-abs(h-ah)) <= 4)
        chk('saturation capped at 70', True, s_ <= 72)
        chk('darker than the profile default', True, lumin(d['bg']) < lumin(DEFAULT_BG))

        print('== leaving a themed project restores the palette ==')
        h2 = m['home2']
        chk('palette restored to defaults', [], [f'ansi{i}' for i in range(16)
             if h2.get(f'ansi{i}') != rep['frames'][f'ansi{i}'][0]])
        chk('fg restored', 'ffffff', h2['fg'])

        print()
        print(f'pass={P} fail={F}')
        return 1 if F else 0
    finally:
        shutil.rmtree(root, ignore_errors=True)

sys.exit(main())
