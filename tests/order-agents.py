#!/usr/bin/env python3
"""Exercise ordering keys through a tty, with captured output separate from UI."""
import os
from pathlib import Path
import pty
import subprocess
import unittest

HELPER = Path(__file__).resolve().parents[1] / 'share/order-agents'


class Ordering(unittest.TestCase):
    def run_menu(self, keys, names=('Grok Bot', 'Claude Code', 'Codex')):
        master, slave = pty.openpty()
        proc = subprocess.Popen([str(HELPER), *names], stdin=slave,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                start_new_session=True)
        os.close(slave)
        try:
            os.write(master, keys)
            output, error = proc.communicate(timeout=10)
            return proc.returncode, output.decode().splitlines(), error.decode()
        finally:
            if proc.poll() is None:
                proc.kill()
                proc.wait()
            os.close(master)

    def test_enter_preserves_order(self):
        self.assertEqual(self.run_menu(b'\r')[:2], (0, ['Grok Bot', 'Claude Code', 'Codex']))

    def test_alt_down_moves_highlighted_row(self):
        self.assertEqual(self.run_menu(b'\x1b[1;3B\r')[1], ['Claude Code', 'Grok Bot', 'Codex'])

    def test_navigation_and_alt_up(self):
        self.assertEqual(self.run_menu(b'\x1b[B\x1b[B\x1b[1;3A\r')[1], ['Grok Bot', 'Codex', 'Claude Code'])

    def test_boundaries(self):
        self.assertEqual(self.run_menu(b'\x1b[1;3A\x1b[B\x1b[B\x1b[1;3B\r')[1], ['Grok Bot', 'Claude Code', 'Codex'])

    def test_escape_cancels_without_output(self):
        code, output, _ = self.run_menu(b'\x1b')
        self.assertNotEqual(code, 0)
        self.assertEqual(output, [])

    def test_keyboard_fallback(self):
        self.assertEqual(self.run_menu(b'JK\r')[1], ['Grok Bot', 'Claude Code', 'Codex'])


if __name__ == '__main__':
    unittest.main()
