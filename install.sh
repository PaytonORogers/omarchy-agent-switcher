#!/usr/bin/env bash
# Install omarchy-agent-switcher for the current user. Safe to re-run.
#   ./install.sh            interactive agent selection on first install
#   ./install.sh --yes      non-interactive: enable every detected agent
#   ./install.sh --setup    re-run agent detection even if a config exists
#   ./install.sh --from-shell
#       Invoked by the panel when Omarchy enables a checkout from `omarchy plugin add`.
#       That command never runs an install hook, so the plugin finishes setup itself.
#       Returns immediately when setup is already current, and does not restart the shell.
set -euo pipefail
SRC=$(cd "$(dirname "$0")" && pwd)
CFG_HOME=${XDG_CONFIG_HOME:-$HOME/.config}
DATA=${XDG_DATA_HOME:-$HOME/.local/share}/omarchy-agent-switcher
BIN=$HOME/.local/bin
ID=$(jq -r .id "$SRC/manifest.json")
PLUG=$CFG_HOME/omarchy/plugins/$ID
HYPR=$CFG_HOME/hypr/hyprland.lua
CONF=$CFG_HOME/omarchy-agent-switcher/agents.conf
MARK="-- omarchy-agent-switcher"
YES=""; SETUP=0; FROM_SHELL=0
for a in "$@"; do
  case $a in
    --yes|-y|--detect) YES=--yes ;;
    --setup) SETUP=1 ;;
    --from-shell) FROM_SHELL=1 ;;
  esac
done

stale() { [[ ! -e $2 || $1 -nt $2 ]]; }

if (( FROM_SHELL )) && [[ -x $BIN/omarchy-agents && -f $DATA/registry.conf && -f $CONF && -f $CFG_HOME/hypr/agent-switcher.lua ]] \
  && grep -qF -- "$MARK" "$HYPR" \
  && ! stale "$SRC/bin/omarchy-agents" "$BIN/omarchy-agents" \
  && ! stale "$SRC/share/registry.conf" "$DATA/registry.conf"; then
  exit 0
fi

for c in hyprctl jq omarchy-shell; do command -v $c >/dev/null || { echo "missing dependency: $c (is this Omarchy?)" >&2; exit 1; }; done

echo ":: installing files"
mkdir -p "$BIN" "$DATA/icons" "$PLUG/plugin"
install -m755 "$SRC/bin/omarchy-agents" "$BIN/omarchy-agents"
install -m644 "$SRC/share/registry.conf" "$SRC/share/agents.conf.default" "$DATA/"
install -m644 "$SRC"/share/icons/*.svg "$DATA/icons/"
# `omarchy plugin add` clones this repo into $PLUG, so the manifest and QML are
# already where entryPoints says. Copying them again would overwrite that checkout.
if [[ $SRC != "$PLUG" ]]; then
  install -m644 "$SRC/manifest.json" "$PLUG/manifest.json"
  install -m644 "$SRC/plugin/Switcher.qml" "$PLUG/plugin/Switcher.qml"
fi

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

if (( FROM_SHELL )); then
  echo "done. Press $(grep -m1 '^toggle_key' "$CONF" | cut -d= -f2 | xargs || echo 'SUPER + A') to open. Config: $CONF"
  exit 0
fi

echo ":: enabling shell plugin $ID"
omarchy-shell -q shell rescanPlugins; sleep 1   # make the shell see the freshly copied plugin
omarchy plugin enable "$ID" >/dev/null 2>&1 || omarchy-shell -q shell enablePlugin "$ID" '{}'
# A full restart (not hot reload) loads the panel reliably.
omarchy-restart-shell >/dev/null 2>&1 || true
omarchy plugin list 2>/dev/null | grep -q "^$ID[[:space:]]*enabled" || echo "warning: plugin $ID is not enabled; run: omarchy plugin enable $ID" >&2
echo "done. Press $(grep -m1 '^toggle_key' "$CONF" | cut -d= -f2 | xargs || echo 'SUPER + A') to open. Config: $CONF"
