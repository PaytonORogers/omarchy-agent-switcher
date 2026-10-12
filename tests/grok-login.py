#!/usr/bin/env python3
import importlib.machinery
import importlib.util
from pathlib import Path
import unittest
from unittest.mock import patch

path = Path(__file__).resolve().parents[1] / 'share/collectors/collect-grok-bot'
loader = importlib.machinery.SourceFileLoader('grok_login', str(path))
spec = importlib.util.spec_from_loader(loader.name, loader)
module = importlib.util.module_from_spec(spec)
loader.exec_module(module)


class LoginCheck(unittest.TestCase):
    def check(self, token, expired, status):
        with patch.object(module, 'grok_bot_tokens', return_value=(token, 'unused')), \
             patch.object(module, 'jwt_expired', return_value=expired), \
             patch.object(module, 'cursor_rpc', return_value=(status, {})) as rpc, \
             patch.object(module, 'cursor_auth_file_tokens') as fallback, \
             patch.object(module, 'cursor_refresh') as refresh:
            result = module.check_app_login()
            fallback.assert_not_called()
            refresh.assert_not_called()
            if not token or expired:
                rpc.assert_not_called()
            return result

    def test_fresh_response(self):
        self.assertEqual(self.check('test-token', False, 200), 0)

    def test_missing_credentials_unknown(self):
        self.assertEqual(self.check(None, False, 200), 2)

    def test_expired_credentials_unknown(self):
        self.assertEqual(self.check('test-token', True, 200), 2)

    def test_auth_or_network_failure_unknown(self):
        for status in (401, 403, 500, -1):
            self.assertEqual(self.check('test-token', False, status), 2)


if __name__ == '__main__':
    unittest.main()
