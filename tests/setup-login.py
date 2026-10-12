#!/usr/bin/env python3
"""Interactive sign-in setup regressions with a real tty and fake desktop."""
import os
from pathlib import Path
import pty
import select
import signal
import subprocess
import tempfile
import time
import unittest

ROOT = Path(__file__).resolve().parents[1]


class SetupLogin(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.base = Path(self.tmp.name)
        self.home = self.base / 'home'
        self.fake = self.base / 'fake'
        self.bin = self.base / 'bin'
        for folder in (self.home, self.fake, self.bin):
            folder.mkdir()
        self.cfg = self.home / '.config'
        self.data = self.home / '.local/share/omarchy-agent-switcher'
        self.state = self.home / '.local/state/omarchy-agent-switcher'
        for folder in (self.cfg / 'hypr', self.cfg / 'omarchy-agent-switcher', self.data, self.state):
            folder.mkdir(parents=True)
        self.conf = self.cfg / 'omarchy-agent-switcher/agents.conf'
        self.original = 'toggle_key = SUPER + A\nOld | old.agent | agent-a | |\n'
        self.conf.write_text(self.original)
        self.rules = self.cfg / 'hypr/agent-switcher.lua'
        self.rules.write_text('-- original rules\n')
        (self.data / 'agents.conf.default').write_text('toggle_key = SUPER + A\n')
        self.registry = self.data / 'registry.conf'
        self.registry.write_text('a | A | gui | bin:agent-a | class.a | agent-a |\n')
        (self.fake / 'monitors.json').write_text('[{"name":"M","focused":true,"x":0,"y":0,"width":1280,"height":720,"scale":1,"transform":0,"reserved":[0,0,0,0],"activeWorkspace":{"id":2},"specialWorkspace":{"name":""}}]')
        (self.fake / 'clients.json').write_text('[]')
        (self.fake / 'cursor').write_text('100, 200')
        self.program('agent-a', 'echo launched >> "$FAKE/launch"\n')
        self.env = dict(os.environ, HOME=str(self.home), FAKE=str(self.fake),
                        XDG_CONFIG_HOME=str(self.cfg), XDG_DATA_HOME=str(self.home / '.local/share'),
                        XDG_STATE_HOME=str(self.home / '.local/state'), XDG_RUNTIME_DIR=str(self.base),
                        OMARCHY_AGENTS_NO_GUM='1', PATH=f'{self.bin}:{ROOT}/tests/stubs:/usr/bin:/bin')
        self.env.pop('OMARCHY_AGENTS_CONF', None)

    def program(self, name, body):
        path = self.bin / name
        path.write_text('#!/bin/sh\n' + body)
        path.chmod(0o755)

    def start(self, inputs):
        master, slave = pty.openpty()
        proc = subprocess.Popen([str(ROOT / 'bin/omarchy-agents'), 'setup'], env=self.env,
                                stdin=slave, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                start_new_session=True)
        os.close(slave)
        os.write(master, inputs.encode())
        return proc, master

    def run_setup(self, inputs):
        proc, master = self.start(inputs)
        try:
            output = proc.communicate(timeout=20)[0].decode()
            return proc.returncode, output
        finally:
            if proc.poll() is None:
                proc.kill()
                proc.wait()
            os.close(master)

    def assert_restored(self):
        self.assertEqual(self.rules.read_text(), '-- original rules\n')
        self.assertFalse((self.state / 'setup-login').exists())
        self.assertFalse(list(self.state.glob('setup-rules.*')))

    def test_confirmation_enables_agent(self):
        code, output = self.run_setup('y\nl\n\ny\n\n')
        self.assertEqual(code, 0, output)
        self.assertIn('A ', self.conf.read_text())
        calls = (self.fake / 'calls').read_text()
        self.assertIn("hl.dsp.focus({ workspace = '2' })", calls)
        self.assertFalse((self.state / 'setup-login').exists())

    def test_already_ready_manual_agent_never_opens(self):
        code, output = self.run_setup('y\ny\n\n')
        self.assertEqual(code, 0, output)
        self.assertFalse((self.fake / 'launch').exists())
        self.assertIn('A ', self.conf.read_text())

    def test_close_option_closes_login_window_before_confirmation(self):
        (self.fake / 'clients.json').write_text('[{"class":"class.a","address":"0xa1","floating":false,"workspace":{"name":"1"},"size":[800,600],"at":[0,0]}]')
        code, output = self.run_setup('y\nl\nc\ny\n\n')
        self.assertEqual(code, 0, output)
        self.assertIn("window.close({ window = 'address:0xa1' })", (self.fake / 'calls').read_text())

    def test_skip_preserves_config_and_rules(self):
        code, output = self.run_setup('y\ns\n')
        self.assertNotEqual(code, 0, output)
        self.assertEqual(self.conf.read_text(), self.original)
        self.assert_restored()

    def test_cancel_preserves_config_and_rules(self):
        code, output = self.run_setup('y\nq\n')
        self.assertNotEqual(code, 0, output)
        self.assertEqual(self.conf.read_text(), self.original)
        self.assert_restored()

    def test_native_success_avoids_launch_and_secret_output(self):
        self.registry.write_text('codex | Codex | gui | bin:codex | class.codex | codex |\n')
        self.program('codex', 'echo SECRET-TOKEN\nexit 0\n')
        code, output = self.run_setup('y\n\n')
        self.assertEqual(code, 0, output)
        self.assertNotIn('SECRET-TOKEN', output)
        self.assertFalse((self.fake / 'launch').exists())

    def test_failed_native_check_does_not_enable(self):
        self.registry.write_text('claude | Claude Code | gui | bin:claude | class.claude | claude |\n')
        self.program('claude', 'exit 1\n')
        code, output = self.run_setup('y\n\n\ns\n')
        self.assertNotEqual(code, 0, output)
        self.assertIn('still reports signed out', output)
        self.assertEqual(self.conf.read_text(), self.original)
        self.assert_restored()

    def test_unsupported_native_command_uses_confirmation(self):
        self.registry.write_text('codex | Codex | gui | bin:codex | class.codex | codex |\n')
        self.program('codex', 'exit 2\n')
        code, output = self.run_setup('y\nl\n\ny\n\n')
        self.assertEqual(code, 0, output)
        self.assertIn('No reliable login check', output)

    def test_unattended_does_not_check_or_launch(self):
        result = subprocess.run([str(ROOT / 'bin/omarchy-agents'), 'setup', '--yes'],
                                env=self.env, stdin=subprocess.DEVNULL, capture_output=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse((self.fake / 'launch').exists())

    def test_skipping_one_agent_keeps_confirmed_agent(self):
        self.program('agent-b', 'exit 0\n')
        self.registry.write_text('a | A | gui | bin:agent-a | class.a | agent-a |\nb | B | gui | bin:agent-b | class.b | agent-b |\n')
        code, output = self.run_setup('y\ny\n\nl\n\ny\ns\n\n')
        self.assertEqual(code, 0, output)
        self.assertIn('A ', self.conf.read_text())
        self.assertNotIn('B ', self.conf.read_text())

    def test_manual_decline_does_not_enable(self):
        code, output = self.run_setup('y\nl\n\nn\ns\n')
        self.assertNotEqual(code, 0, output)
        self.assertEqual(self.conf.read_text(), self.original)
        self.assert_restored()

    def test_login_becomes_verified_after_window_launch(self):
        self.registry.write_text('codex | Codex | gui | bin:codex | class.codex | codex |\n')
        self.program('codex', 'if [ "$1" = login ]; then test -e "$FAKE/signed-in"; else touch "$FAKE/signed-in"; fi\n')
        proc, master = self.start('y\n\n')
        try:
            deadline = time.monotonic() + 10
            while not (self.fake / 'signed-in').exists() and time.monotonic() < deadline:
                time.sleep(0.05)
            self.assertTrue((self.fake / 'signed-in').exists())
            os.write(master, b'\n\n')
            output = proc.communicate(timeout=10)[0].decode()
            self.assertEqual(proc.returncode, 0, output)
            self.assertIn('Codex', self.conf.read_text())
        finally:
            if proc.poll() is None:
                proc.kill()
                proc.wait()
            os.close(master)

    def test_existing_agent_excluded_during_login_and_theme_refresh(self):
        self.conf.write_text('A | class.a | agent-a | |\n')
        proc, master = self.start('y\nl\n')
        try:
            deadline = time.monotonic() + 10
            while not (self.state / 'setup-login').exists() and time.monotonic() < deadline:
                time.sleep(0.05)
            self.assertTrue((self.state / 'setup-login').exists())
            refreshed = subprocess.run([str(ROOT / 'bin/omarchy-agents'), 'rules'], env=self.env,
                                       capture_output=True, timeout=10)
            self.assertEqual(refreshed.returncode, 0, refreshed.stderr)
            self.assertNotIn('o.window(', self.rules.read_text())
            os.write(master, b'q\n')
            try:
                proc.communicate(timeout=10)
            except subprocess.TimeoutExpired:
                raise AssertionError(f"termination timeout: parent status={proc.poll()}")
            self.assert_restored()
        finally:
            if proc.poll() is None:
                proc.kill()
                proc.wait()
            os.close(master)

    def test_reordered_rows_survive_signin_and_config_save(self):
        self.registry.write_text('codex | A | gui | bin:codex | class.a | codex |\nclaude | B | gui | bin:claude | class.b | claude |\n')
        self.program('codex', 'exit 0\n')
        self.program('claude', 'exit 0\n')
        code, output = self.run_setup('y\ny\n\x1b[1;3B\n\n')
        self.assertEqual(code, 0, output)
        listed = subprocess.run([str(ROOT / 'bin/omarchy-agents'), 'list'], env=self.env,
                                capture_output=True, text=True, check=True).stdout.splitlines()
        self.assertEqual(listed, ['B', 'A'])

    def test_signal_restores_rules(self):
        proc, master = self.start('y\nl\n')
        try:
            output = b''
            deadline = time.monotonic() + 15
            while b'Enter to check/confirm' not in output and time.monotonic() < deadline:
                if select.select([proc.stdout], [], [], 0.2)[0]:
                    output += os.read(proc.stdout.fileno(), 4096)
            self.assertIn(b'Enter to check/confirm', output)
            proc.send_signal(signal.SIGTERM)
            try:
                proc.communicate(timeout=10)
            except subprocess.TimeoutExpired:
                raise AssertionError(f"termination timeout: parent status={proc.poll()}")
            self.assert_restored()
            self.assertEqual(self.conf.read_text(), self.original)
        finally:
            if proc.poll() is None:
                proc.kill()
                proc.wait()
            os.close(master)


if __name__ == '__main__':
    unittest.main()
