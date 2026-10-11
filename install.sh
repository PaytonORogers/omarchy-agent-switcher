#!/usr/bin/env bash
# Install omarchy-agent-switcher for the current user. Safe to re-run.
#   ./install.sh            interactive agent selection on first install
#   ./install.sh --yes      non-interactive: enable every detected agent
#   ./install.sh --setup    re-run agent detection even if a config exists
set -euo pipefail
SRC=$(cd "$(dirname "$0")" && pwd)
CFG_HOME=${XDG_CONFIG_HOME:-$HOME/.config}
DATA=${XDG_DATA_HOME:-$HOME/.local/share}/omarchy-agent-switcher
BIN=$HOME/.local/bin
ID=$(jq -r .id "$SRC/plugin/manifest.json")
PLUG=$CFG_HOME/omarchy/plugins/$ID
HYPR=$CFG_HOME/hypr/hyprland.lua
CONF=$CFG_HOME/omarchy-agent-switcher/agents.conf
MARK="-- omarchy-agent-switcher"
YES=""; SETUP=0
for a in "$@"; do case $a in --yes|-y|--detect) YES=--yes ;; --setup) SETUP=1 ;; esac; done
for c in hyprctl jq omarchy-shell; do command -v $c >/dev/null || { echo "missing dependency: $c (is this Omarchy?)" >&2; exit 1; }; done

echo ":: installing files"
mkdir -p "$BIN" "$DATA/icons" "$PLUG"
install -m755 "$SRC/bin/omarchy-agents" "$BIN/omarchy-agents"
install -m644 "$SRC/share/registry.conf" "$SRC/share/agents.conf.default" "$DATA/"
install -m644 "$SRC"/share/icons/*.svg "$DATA/icons/"
install -m644 "$SRC"/plugin/* "$PLUG/"

if [[ ! -f $CONF || $SETUP == 1 ]]; then
  echo ":: choosing agents"
  if ! "$BIN/omarchy-agents" setup $YES; then
    mkdir -p "$(dirname "$CONF")"; [[ -f $CONF ]] || cp "$DATA/agents.conf.default" "$CONF"
  fi
fi
"$BIN/omarchy-agents" rules

if ! grep -qF -- "$MARK" "$HYPR"; then
  echo ":: adding include to $HYPR"
  cp "$HYPR" "$HYPR.bak-agent-switcher"
  printf '\n%s (remove with uninstall.sh)\nrequire("hypr.agent-switcher")\n' "$MARK" >> "$HYPR"
fi
hyprctl reload >/dev/null
errs=$(hyprctl configerrors); [[ -z ${errs//[[:space:]]/} ]] || { echo "Hyprland config errors:"; echo "$errs"; }

echo ":: enabling shell plugin $ID"
omarchy-shell -q shell rescanPlugins; sleep 1   # make the shell see the freshly copied plugin
omarchy plugin enable "$ID" >/dev/null 2>&1 || omarchy-shell -q shell enablePlugin "$ID" '{}'
# A full restart (not hot reload) loads the panel reliably.
omarchy-restart-shell >/dev/null 2>&1 || true
omarchy plugin list 2>/dev/null | grep -q "^$ID[[:space:]]*enabled" || echo "warning: plugin $ID is not enabled; run: omarchy plugin enable $ID" >&2
echo "done. Press $(grep -m1 '^toggle_key' "$CONF" | cut -d= -f2 | xargs || echo 'SUPER + A') to open. Config: $CONF"
