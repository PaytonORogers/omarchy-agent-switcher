#!/usr/bin/env python3
"""Configuration persistence and GUI sign-in against the fake desktop."""
import importlib.util
import json
import os
from pathlib import Path
import select
import signal
import subprocess
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('login_tests', ROOT / 'tests/setup-login.py')
fixtures = importlib.util.module_from_spec(spec)
spec.loader.exec_module(fixtures)


class StripConfig(unittest.TestCase):
    program = fixtures.SetupLogin.program

    def setUp(self):
        fixtures.SetupLogin.setUp(self)
        self.program('agent-b', 'exit 0\n')
        self.conf.write_text('open_on = first\n# user note\nopacity = 1.0 1.0\nA | class.a | agent-a | |\nB | class.b | agent-b | |\nonly = B, A\n')

    def command(self, *args, check=True):
        return subprocess.run([str(ROOT / 'bin/omarchy-agents'), *args], env=self.env, capture_output=True, text=True, check=check, timeout=15)

    def service(self, name='A'):
        proc = subprocess.Popen([str(ROOT / 'share/configure-signin'), str(ROOT / 'bin/omarchy-agents'), name], env=self.env, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.addCleanup(self.stop, proc)
        proc.buffered = b''
        return proc

    def stop(self, proc):
        if proc.poll() is None:
            proc.terminate()
            proc.communicate(timeout=10)

    def state_is(self, proc, desired):
        deadline = time.monotonic() + 12
        while time.monotonic() < deadline:
            while b'\n' in proc.buffered:
                line, proc.buffered = proc.buffered.split(b'\n', 1)
                value = json.loads(line)
                if value['state'] == desired:
                    return value
            if select.select([proc.stdout], [], [], 0.2)[0]:
                data = os.read(proc.stdout.fileno(), 4096)
                if not data:
                    self.fail(f'Session exited before {desired}: {proc.stderr.read().decode()}')
                proc.buffered += data
        self.fail(f'Timed out waiting for {desired}')

    def send(self, proc, action):
        proc.stdin.write((action + '\n').encode())
        proc.stdin.flush()

    def test_catalog_includes_custom_and_disabled_agents(self):
        self.command('disable', 'A')
        data = json.loads(self.command('agents', '--json').stdout)
        self.assertEqual(data['enabled'], ['B'])
        self.assertEqual({a['name'] for a in data['agents']}, {'A', 'B'})
        self.assertFalse(next(a for a in data['agents'] if a['name'] == 'A')['enabled'])

    def test_moves_persist_keep_config_and_stop_at_edges(self):
        self.command('move', 'class.a', 'left')
        self.assertEqual(self.command('list').stdout.splitlines(), ['A', 'B'])
        self.command('move', 'A', 'left')
        self.assertEqual(self.command('list').stdout.splitlines(), ['A', 'B'])
        self.assertIn('# user note', self.conf.read_text())
        self.assertIn('open_on = first', self.conf.read_text())

    def test_concurrent_moves_serialize(self):
        procs = [subprocess.Popen([str(ROOT / 'bin/omarchy-agents'), 'move', 'A', 'left'], env=self.env, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE) for _ in range(5)]
        for proc in procs:
            self.assertEqual(proc.communicate(timeout=20)[1], b'')
            self.assertEqual(proc.returncode, 0)
        self.assertEqual(self.command('list').stdout.splitlines(), ['A', 'B'])
        self.assertEqual(self.conf.read_text().count('only ='), 1)

    def test_settings_validate_and_preserve_other_lines(self):
        self.command('setting', 'usage_display', 'percent')
        self.command('setting', 'show_hint', 'false')
        self.command('setting', 'open_on', 'A')
        self.command('setting', 'opacity', '0.85 0.85')
        saved = self.conf.read_text()
        for key, value in [('opacity','1.8'),('unknown','x'),('open_on','Missing'),('show_hint','perhaps')]:
            self.assertNotEqual(self.command('setting', key, value, check=False).returncode, 0)
            self.assertEqual(self.conf.read_text(), saved)
        self.assertIn('# user note', saved)
        self.assertEqual(self.command('list').stdout.splitlines(), ['B', 'A'])

    def test_empty_strip_still_opens_picker(self):
        self.command('disable', 'A', 'B')
        self.command('toggle')
        self.assertIn('"picker":true', (self.fake / 'shell').read_text())
        self.assertEqual(self.command('list').stdout.strip(), '')

    def test_empty_strip_can_close_and_refocus_does_not_reopen_picker(self):
        self.command('disable', 'A', 'B')
        self.program('omarchy-shell', 'if [ "$1" = agentswitcher ] && [ "$2" = state ]; then echo "open:"; fi\n')
        (self.fake / 'calls').write_text('')
        self.command('toggle')
        self.assertIn('agent_switcher.off()', (self.fake / 'calls').read_text())
        (self.fake / 'shell').write_text('')
        self.command('refocus')
        self.assertEqual((self.fake / 'shell').read_text(), '')

    def test_submap_defined_without_overriding_desktop_swap(self):
        self.command('rules')
        rules = self.rules.read_text()
        self.assertIn('hl.define_submap("agent-switcher-arrange"', rules)
        self.assertNotIn('hl.unbind, "SUPER + SHIFT + LEFT"', rules)
        self.assertIn('agent_switcher.arranging=false', rules)

    def test_cancel_without_opening_preserves_config(self):
        old = self.conf.read_text()
        proc = self.service()
        self.state_is(proc, 'confirmation_needed')
        self.send(proc, 'cancel')
        proc.communicate(timeout=10)
        self.assertEqual(self.conf.read_text(), old)
        self.assertFalse((self.fake / 'launch').exists())

    def test_manual_confirmation_appends_without_launch(self):
        self.command('disable', 'A')
        proc = self.service()
        self.state_is(proc, 'confirmation_needed')
        self.send(proc, 'confirm')
        self.state_is(proc, 'added')
        proc.communicate(timeout=10)
        self.assertEqual(self.command('list').stdout.splitlines(), ['B', 'A'])
        self.assertFalse((self.fake / 'launch').exists())

    def test_native_success_adds_without_opening_or_secret_output(self):
        self.registry.write_text('codex | Codex | gui | bin:codex | class.codex | codex |\n')
        self.program('codex', 'echo SECRET\nexit 0\n')
        proc = self.service('Codex')
        value = self.state_is(proc, 'added')
        self.assertNotIn('SECRET', json.dumps(value))
        proc.communicate(timeout=10)
        self.assertIn('Codex', self.command('list').stdout)
        self.assertFalse((self.fake / 'launch').exists())

    def test_native_negative_cannot_be_manually_overridden(self):
        self.registry.write_text('codex | Codex | gui | bin:codex | class.codex | codex |\n')
        self.program('codex', 'echo "Not logged in"\nexit 1\n')
        old = self.conf.read_text()
        proc = self.service('Codex')
        self.state_is(proc, 'signed_out')
        self.send(proc, 'confirm')
        self.state_is(proc, 'signed_out')
        self.send(proc, 'cancel'); proc.communicate(timeout=10)
        self.assertEqual(self.conf.read_text(), old)

    def test_launch_failure_and_cancel_restore_rules(self):
        self.env['OMARCHY_AGENTS_LOGIN_TIMEOUT'] = '1'
        self.bin.joinpath('agent-a').write_text('#!/bin/sh\nexit 0\n')
        old = self.conf.read_text()
        proc = self.service()
        self.state_is(proc, 'confirmation_needed')
        self.send(proc, 'open')
        self.state_is(proc, 'failed')
        self.send(proc, 'cancel'); proc.communicate(timeout=10)
        self.assertFalse((self.state / 'setup-login').exists())
        self.assertIn('class\\\\.a', self.rules.read_text())
        self.assertEqual(self.conf.read_text(), old)

    def test_mapped_window_can_close_without_enabling(self):
        self.fake.joinpath('clients.json').write_text('[{"class":"class.a","address":"0xa1","floating":false,"workspace":{"name":"2"}}]')
        proc = self.service(); self.state_is(proc, 'confirmation_needed')
        old = self.conf.read_text()
        self.send(proc, 'open'); self.state_is(proc, 'awaiting_login')
        self.fake.joinpath('clients.json').write_text('[]')
        self.send(proc, 'check'); self.state_is(proc, 'confirmation_needed')
        self.send(proc, 'cancel'); proc.communicate(timeout=10)
        self.assertEqual(self.conf.read_text(), old)

    def test_signal_cleans_marker_and_theme_refresh_excludes_only_target(self):
        self.fake.joinpath('clients.json').write_text('[{"class":"class.a","address":"0xa1","floating":false,"workspace":{"name":"2"}}]')
        proc = self.service(); self.state_is(proc, 'confirmation_needed')
        self.send(proc, 'open'); self.state_is(proc, 'awaiting_login')
        self.command('rules')
        self.assertNotIn('class\\\\.a', self.rules.read_text())
        self.assertIn('class\\\\.b', self.rules.read_text())
        proc.send_signal(signal.SIGTERM); proc.communicate(timeout=10)
        self.assertFalse((self.state / 'setup-login').exists())
        self.assertIn('class\\\\.a', self.rules.read_text())

    def test_cancel_during_launch_is_prompt_and_restores_rules(self):
        self.bin.joinpath('agent-a').write_text('#!/bin/sh\nexit 0\n')
        proc = self.service(); self.state_is(proc, 'confirmation_needed')
        self.send(proc, 'open'); self.state_is(proc, 'opening')
        started = time.monotonic()
        proc.terminate(); proc.communicate(timeout=5)
        self.assertLess(time.monotonic() - started, 4)
        self.assertFalse((self.state / 'setup-login').exists())

    def test_auth_timeout_requires_confirmation(self):
        self.registry.write_text('codex | Codex | gui | bin:codex | class.codex | codex |\n')
        self.program('codex', 'sleep 5\n')
        self.env['OMARCHY_AGENTS_AUTH_TIMEOUT'] = '1'
        data = json.loads(self.command('auth', 'Codex').stdout)
        self.assertEqual(data['state'], 'confirmation_needed')

    def test_fresh_gui_setup_has_no_enabled_tabs(self):
        self.conf.unlink()
        self.command('setup', '--empty')
        self.assertEqual(self.command('list').stdout.strip(), '')
        self.assertIn('only = ', self.conf.read_text())
        self.assertIn('# A', self.conf.read_text())

    def test_unexpected_native_error_uses_confirmation(self):
        self.registry.write_text('codex | Codex | gui | bin:codex | class.codex | codex |\n')
        self.program('codex', 'echo "wrapper unavailable" >&2\nexit 1\n')
        data = json.loads(self.command('auth', 'Codex').stdout)
        self.assertEqual(data['state'], 'confirmation_needed')

    def test_stale_session_recovers_when_rules_regenerate(self):
        (self.state / 'setup-login').write_text('999999999 class.a\n')
        self.command('rules')
        self.assertFalse((self.state / 'setup-login').exists())
        self.assertIn('class\\\\.a', self.rules.read_text())


if __name__ == '__main__':
    unittest.main()
