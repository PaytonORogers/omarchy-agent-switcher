# Nautilus extension: right-click files/folders -> "Send to agent" -> <Agent>.
# Installed by `install.sh --with-nautilus` into ~/.local/share/nautilus-python/extensions/.
import os
import subprocess
from urllib.parse import unquote, urlparse

from gi.repository import GObject, Nautilus

BIN = os.path.expanduser("~/.local/bin/omarchy-agents")


def agents():
    try:
        out = subprocess.run([BIN, "list"], capture_output=True, text=True, timeout=3).stdout
        return [a for a in out.splitlines() if a.strip()]
    except Exception:
        return []


class AgentSwitcherSendTo(GObject.GObject, Nautilus.MenuProvider):
    def _send(self, _item, agent, files):
        paths = [unquote(urlparse(f.get_uri()).path) for f in files if f.get_uri_scheme() == "file"]
        if paths:
            subprocess.Popen([BIN, "send-files", agent, *paths], start_new_session=True)

    def get_file_items(self, *args):
        files = args[-1]  # Nautilus 4: (files); Nautilus 3: (window, files)
        if not files or not os.access(BIN, os.X_OK):
            return []
        names = agents()
        if not names:
            return []
        top = Nautilus.MenuItem(name="AgentSwitcher::SendTo", label="Send to agent")
        sub = Nautilus.Menu()
        top.set_submenu(sub)
        for i, name in enumerate(names):
            item = Nautilus.MenuItem(name=f"AgentSwitcher::SendTo{i}", label=f"Send to {name}")
            item.connect("activate", self._send, name, files)
            sub.append_item(item)
        return [top]
