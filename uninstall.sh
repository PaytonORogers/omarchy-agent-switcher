#!/usr/bin/env bash
# Remove omarchy-agent-switcher. Keeps your agents.conf unless --purge.
set -euo pipefail
SRC=$(cd "$(dirname "$0")" && pwd)
CFG_HOME=${XDG_CONFIG_HOME:-$HOME/.config}
ID=$(jq -r .id "$SRC/manifest.json")
HYPR=$CFG_HOME/hypr/hyprland.lua
HOOK=$CFG_HOME/omarchy/hooks/theme-set
MARK="-- omarchy-agent-switcher"
REQ='require("hypr.agent-switcher")'
# Close the drop-down first so agent windows aren't stranded off-screen or invisible.
"$HOME/.local/bin/omarchy-agents" hide >/dev/null 2>&1 || true
# Remove exactly the status hooks and bar icon we added (backups are kept next to each file).
"$HOME/.local/bin/omarchy-agents" hooks uninstall || true
"$HOME/.local/bin/omarchy-agents" bar-entry remove || true
if [[ -f $HYPR ]] && grep -qE "^($MARK|require\(\"hypr\.agent-switcher\"\))" "$HYPR"; then
  cp "$HYPR" "$HYPR.bak-agent-switcher-uninstall"
  # Delete exactly our two lines; never a range (a missing end marker must not eat the file).
  grep -vxF -- "$REQ" "$HYPR" | grep -v "^$MARK" > "$HYPR.tmp" || true
  mv "$HYPR.tmp" "$HYPR"
fi
[[ -f $HOOK ]] && { grep -vF "# omarchy-agent-switcher" "$HOOK" > "$HOOK.tmp" || true; mv "$HOOK.tmp" "$HOOK"; chmod +x "$HOOK"; }
rm -f "$CFG_HOME/hypr/agent-switcher.lua" \
      "${XDG_DATA_HOME:-$HOME/.local/share}/applications/omarchy-agents-send.desktop" \
      "${XDG_DATA_HOME:-$HOME/.local/share}/nautilus-python/extensions/omarchy-agent-switcher.py"
hyprctl reload >/dev/null 2>&1 || true
omarchy plugin disable "$ID" >/dev/null 2>&1 || true
rm -rf "$CFG_HOME/omarchy/plugins/$ID" "${XDG_DATA_HOME:-$HOME/.local/share}/omarchy-agent-switcher" \
       "${XDG_STATE_HOME:-$HOME/.local/state}/omarchy-agent-switcher" "$HOME/.local/bin/omarchy-agents"
[[ ${1:-} == --purge ]] && rm -rf "$CFG_HOME/omarchy-agent-switcher"
omarchy-restart-shell >/dev/null 2>&1 || true
echo "omarchy-agent-switcher removed$([[ ${1:-} == --purge ]] && echo ' (config purged)' || echo "; config kept in $CFG_HOME/omarchy-agent-switcher")."
echo "Agent windows stay open in special:agents; close them or reopen with their own launchers."
