#!/usr/bin/env bash
# Remove omarchy-agent-switcher. Keeps your agents.conf unless --purge.
set -euo pipefail
SRC=$(cd "$(dirname "$0")" && pwd)
CFG_HOME=${XDG_CONFIG_HOME:-$HOME/.config}
ID=$(jq -r .id "$SRC/plugin/manifest.json")
HYPR=$CFG_HOME/hypr/hyprland.lua
MARK="-- omarchy-agent-switcher"
# Close the drop-down first so agent windows aren't stranded off-screen.
omarchy-agents hide >/dev/null 2>&1 || true
if grep -qF -- "$MARK" "$HYPR"; then
  cp "$HYPR" "$HYPR.bak-agent-switcher-uninstall"
  sed -i "/^$MARK/,/^require(\"hypr.agent-switcher\")/d" "$HYPR"
  sed -i -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$HYPR"   # trim trailing blank lines
fi
rm -f "$CFG_HOME/hypr/agent-switcher.lua"
hyprctl reload >/dev/null 2>&1 || true
omarchy plugin disable "$ID" >/dev/null 2>&1 || true
rm -rf "$CFG_HOME/omarchy/plugins/$ID" "${XDG_DATA_HOME:-$HOME/.local/share}/omarchy-agent-switcher" \
       "${XDG_STATE_HOME:-$HOME/.local/state}/omarchy-agent-switcher" "$HOME/.local/bin/omarchy-agents"
[[ ${1:-} == --purge ]] && rm -rf "$CFG_HOME/omarchy-agent-switcher"
omarchy-restart-shell >/dev/null 2>&1 || true
echo "omarchy-agent-switcher removed$([[ ${1:-} == --purge ]] && echo ' (config purged)' || echo "; config kept in $CFG_HOME/omarchy-agent-switcher")."
echo "Agent windows stay open in special:agents; reopen them with their own launchers or close them."
