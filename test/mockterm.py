#!/usr/bin/env python3
"""A minimal terminal emulator on a pty, just enough to test livery.sh.

Speaks the parts of the OSC protocol livery.sh depends on: set/query/reset of
background (11/111), foreground (10/110) and cursor (12/112). It records every
colour it is told to use, so a test can assert on the whole fade sequence
rather than only the final colour. Runs headless, so it never steals focus.

Marks: the script under test emits OSC 777;mark;NAME to snapshot state.
Output: a JSON report on stdout.
"""
import json, os, pty, re, select, sys

OSC = re.compile(rb'\x1b\]([^\x07\x1b]*)(?:\x07|\x1b\\)')


class MockTerm:
    def __init__(self, defaults):
        for i in range(16):
            defaults.setdefault(f'ansi{i}', '%02x%02x%02x' % (i * 16, i * 16, i * 16))
        defaults.setdefault('bold', 'ffffff')
        self.defaults = dict(defaults)
        self.cur = dict(defaults)
        self.frames = {k: [v] for k, v in defaults.items()}   # every value ever set
        self.marks = []
        self.buf = b''
        self.stray = b''      # bytes outside any well-formed OSC sequence

    @staticmethod
    def _parse_color(spec):
        spec = spec.strip()
        if spec.startswith('#') and len(spec) == 7:
            return spec[1:].lower()
        m = re.fullmatch(r'rgb:([0-9a-fA-F]+)/([0-9a-fA-F]+)/([0-9a-fA-F]+)', spec)
        if m:
            return ''.join(g[:2].lower() for g in m.groups())
        return None

    def _reply_indexed(self, fd, idx, key):
        v = self.cur[key]
        payload = 'rgb:{}{}/{}{}/{}{}'.format(v[0:2], v[0:2], v[2:4], v[2:4], v[4:6], v[4:6])
        os.write(fd, f'\x1b]4;{idx};{payload}\x1b\\'.encode())

    def _reply(self, fd, code, key):
        v = self.cur[key]
        payload = 'rgb:{}{}/{}{}/{}{}'.format(v[0:2], v[0:2], v[2:4], v[2:4], v[4:6], v[4:6])
        os.write(fd, f'\x1b]{code};{payload}\x1b\\'.encode())

    def feed(self, data, fd):
        self.buf += data
        while True:
            m = OSC.search(self.buf)
            if not m:
                # keep the tail in case a sequence is split across reads
                if len(self.buf) > 64:
                    self.stray += self.buf[:-64]
                    self.buf = self.buf[-64:]
                return
            body = m.group(1).decode('utf-8', 'replace')
            self.stray += self.buf[:m.start()]
            self.buf = self.buf[m.end():]
            self._dispatch(body, fd)

    def _dispatch(self, body, fd):
        parts = body.split(';')
        code = parts[0]
        arg = ';'.join(parts[1:])
        keymap = {'10': 'fg', '11': 'bg', '12': 'cursor'}
        resetmap = {'110': 'fg', '111': 'bg', '112': 'cursor'}
        if code == '4':                     # OSC 4 ; index ; spec|?
            bits = arg.split(';')
            if len(bits) >= 2 and bits[0].isdigit():
                key = 'ansi' + bits[0]
                if key in self.cur:
                    if bits[1].strip() == '?':
                        self._reply_indexed(fd, bits[0], key)
                    else:
                        c = self._parse_color(bits[1])
                        if c:
                            self.cur[key] = c
                            self.frames.setdefault(key, []).append(c)
            return
        if code == '5':                     # OSC 5 ; 0 ; spec  (bold colour)
            bits = arg.split(';')
            if len(bits) >= 2:
                c = self._parse_color(bits[1])
                if c:
                    self.cur['bold'] = c
                    self.frames.setdefault('bold', []).append(c)
            return
        if code == '104':                   # reset whole palette
            for i in range(16):
                k = f'ansi{i}'
                self.cur[k] = self.defaults[k]
                self.frames.setdefault(k, []).append(self.defaults[k])
            return
        if code == '105':
            self.cur['bold'] = self.defaults['bold']
            return
        if code in keymap:
            key = keymap[code]
            if arg.strip() == '?':
                self._reply(fd, code, key)
            else:
                c = self._parse_color(arg)
                if c:
                    self.cur[key] = c
                    self.frames[key].append(c)
        elif code in resetmap:
            key = resetmap[code]
            self.cur[key] = self.defaults[key]
            self.frames[key].append(self.defaults[key])
        elif code == '777' and arg.startswith('mark;'):
            snap = dict(self.cur)
            snap['name'] = arg[len('mark;'):]
            snap['bg_frames'] = len(self.frames['bg'])
            self.marks.append(snap)
        elif code in ('0', '2'):
            self.marks.append({'name': '__title__', 'title': arg})


def main():
    script = sys.argv[1]
    args = sys.argv[2:]
    defaults = {'bg': '300a24', 'fg': 'ffffff', 'cursor': 'ffffff'}
    term = MockTerm(defaults)

    pid, fd = pty.fork()
    if pid == 0:
        os.environ['TERM'] = 'xterm-256color'
        os.environ['LIVERY_FORCE'] = '1'
        os.execvp('bash', ['bash', script] + args)

    while True:
        try:
            r, _, _ = select.select([fd], [], [], 20)
        except OSError:
            break
        if not r:
            break
        try:
            data = os.read(fd, 65536)
        except OSError:
            break
        if not data:
            break
        term.feed(data, fd)
    os.close(fd)
    try:
        os.waitpid(pid, 0)
    except ChildProcessError:
        pass
    # feed() holds back the last 64 bytes in case a sequence is split across
    # reads. Flush that remainder, or the tail of every run is silently lost --
    # which quietly breaks any assertion about trailing output.
    term.stray += term.buf
    term.buf = b''

    print(json.dumps({'marks': term.marks, 'frames': term.frames, 'final': term.cur,
                      'stray': term.stray.decode('utf-8', 'replace')}, indent=1))


if __name__ == '__main__':
    main()
