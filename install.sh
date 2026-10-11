#!/usr/bin/env bash
# Install omarchy-agent-switcher for the current user. Safe to re-run (also how you update).
#   ./install.sh               interactive agent selection on first install
#   ./install.sh --yes         non-interactive: enable every detected agent
#   ./install.sh --setup       re-run agent detection even if a config exists
#   ./install.sh --no-restart  don't restart the Omarchy shell (plugin loads on next restart)
#   ./install.sh --from-shell  run by the panel on first load after `omarchy plugin add` (which has no install hook);
#                              no-op once this version is set up (marker file), never restarts the shell
#   ./install.sh --with-nautilus   add "Send to agent" to the Nautilus right-click menu
set -euo pipefail
SRC=$(cd "$(dirname "$0")" && pwd)
CFG_HOME=${XDG_CONFIG_HOME:-$HOME/.config}
DATA=${XDG_DATA_HOME:-$HOME/.local/share}/omarchy-agent-switcher
BIN=$HOME/.local/bin
ID=$(jq -r .id "$SRC/manifest.json")
VER=$(jq -r .version "$SRC/manifest.json")
STATE=${XDG_STATE_HOME:-$HOME/.local/state}/omarchy-agent-switcher
MARKER=$STATE/installed
PLUG=$CFG_HOME/omarchy/plugins/$ID
HYPR=$CFG_HOME/hypr/hyprland.lua
CONF=$CFG_HOME/omarchy-agent-switcher/agents.conf
HOOK=$CFG_HOME/omarchy/hooks/theme-set
MARK="-- omarchy-agent-switcher"
REQ='require("hypr.agent-switcher")'
YES=""; SETUP=0; RESTART=1; FROM_SHELL=0; NAUT=0
for a in "$@"; do case $a in --yes|-y|--detect) YES=--yes ;; --setup) SETUP=1 ;; --no-restart) RESTART=0 ;; --with-nautilus) NAUT=1 ;; --from-shell) FROM_SHELL=1; RESTART=0; YES=--yes ;; -h|--help) sed -n '2,9p' "$0"; exit 0 ;; esac; done

# First-load install from the panel: only once per version (the marker records version + source).
if (( FROM_SHELL )); then
  [[ $(cat "$MARKER" 2>/dev/null) == "$VER $SRC" && -x $BIN/omarchy-agents && -f $CFG_HOME/hypr/agent-switcher.lua && -f $CONF ]] && exit 0
  exec 8>"${XDG_RUNTIME_DIR:-/tmp}/omarchy-agent-switcher-install.lock"; flock -n 8 || exit 0   # one at a time (shell reloads)
fi

# ---- preflight: fail before touching anything ----
fail() { echo "install: $*" >&2; exit 1; }
for c in hyprctl jq flock omarchy-shell; do command -v "$c" >/dev/null || fail "missing dependency: $c (is this Omarchy?)"; done
[[ -f $HYPR ]] || fail "$HYPR not found: this needs Omarchy's Hyprland Lua config"
hyprctl version >/dev/null 2>&1 || fail "Hyprland isn't running (hyprctl failed)"
bash -n "$SRC/bin/omarchy-agents" || fail "bin/omarchy-agents has a syntax error"

stage() { # stage <src-dir> <dest-dir>: copy into a temp dir, then swap in (no stale files, no half copies)
  local tmp="$2.new.$$"; rm -rf "$tmp"; mkdir -p "$tmp"; cp -r "$1"/. "$tmp"/
  rm -rf "$2.old.$$"; [[ -d $2 ]] && mv "$2" "$2.old.$$"; mv "$tmp" "$2"; rm -rf "$2.old.$$"
}
echo ":: installing files"
mkdir -p "$BIN" "$(dirname "$PLUG")" "$(dirname "$DATA")"
install -m755 "$SRC/bin/omarchy-agents" "$BIN/omarchy-agents.new" && mv "$BIN/omarchy-agents.new" "$BIN/omarchy-agents"
stage "$SRC/share" "$DATA"
# `omarchy plugin add` clones this repo straight into $PLUG: it already is the plugin, never stage over it.
if [[ $(readlink -f "$SRC") != $(readlink -f "$PLUG" 2>/dev/null || echo "$PLUG") ]]; then
  tmpplug=$(mktemp -d); mkdir -p "$tmpplug/plugin"
  cp "$SRC/manifest.json" "$tmpplug/"; cp -r "$SRC/plugin"/. "$tmpplug/plugin/"
  stage "$tmpplug" "$PLUG"; rm -rf "$tmpplug"
fi

if [[ ! -f $CONF || $SETUP == 1 ]]; then
  echo ":: choosing agents"
  if ! "$BIN/omarchy-agents" setup $YES; then
    mkdir -p "$(dirname "$CONF")"; [[ -f $CONF ]] || cp "$DATA/agents.conf.default" "$CONF"
  fi
fi
"$BIN/omarchy-agents" rules

if ! grep -qxF -- "$REQ" "$HYPR"; then
  echo ":: adding include to $HYPR"
  cp "$HYPR" "$HYPR.bak-agent-switcher"
  printf '\n%s (remove with uninstall.sh)\n%s\n' "$MARK" "$REQ" >> "$HYPR"
fi

# Regenerate border colours when the Omarchy theme changes.
mkdir -p "$(dirname "$HOOK")"
[[ -f $HOOK ]] || printf '#!/bin/bash\n' > "$HOOK"
grep -qF "# omarchy-agent-switcher" "$HOOK" || echo "\"\$HOME/.local/bin/omarchy-agents\" rules --reload >/dev/null 2>&1 &  # omarchy-agent-switcher" >> "$HOOK"
chmod +x "$HOOK"

# "Send to agent" for any file manager's Open With (hidden from the app launcher).
APPS=${XDG_DATA_HOME:-$HOME/.local/share}/applications; mkdir -p "$APPS"
install -m644 "$SRC/share/applications/omarchy-agents-send.desktop" "$APPS/"
command -v update-desktop-database >/dev/null && update-desktop-database "$APPS" >/dev/null 2>&1 || true

if (( NAUT )); then
  echo ":: Nautilus integration"
  NX=${XDG_DATA_HOME:-$HOME/.local/share}/nautilus-python/extensions; mkdir -p "$NX"
  install -m644 "$SRC/integrations/nautilus/omarchy-agent-switcher.py" "$NX/"
  [[ -d /usr/share/nautilus-python || -d /usr/lib/nautilus/extension-4 ]] || echo "   note: install python-nautilus for the menu to appear" >&2
  pgrep -x nautilus >/dev/null && { nautilus -q >/dev/null 2>&1 || true; }
fi

hyprctl reload >/dev/null
errs=$(hyprctl configerrors); [[ -z ${errs//[[:space:]]/} ]] || { echo "Hyprland config errors:"; echo "$errs"; }

mkdir -p "$STATE"; echo "$VER $SRC" > "$MARKER"
if (( FROM_SHELL )); then   # the shell already loaded us; enabling/restarting from inside it would loop
  notify-send -a "Agent switcher" "Agent switcher installed" "Press $(grep -m1 '^toggle_key' "$CONF" | cut -d= -f2 | xargs || echo 'SUPER + A') to open. Run omarchy-agents setup to pick agents." 2>/dev/null || true
  exit 0
fi

echo ":: enabling shell plugin $ID"
omarchy-shell -q shell rescanPlugins; sleep 1   # make the shell see the freshly copied plugin
omarchy plugin enable "$ID" >/dev/null 2>&1 || omarchy-shell -q shell enablePlugin "$ID" '{}'
if (( RESTART )); then omarchy-restart-shell >/dev/null 2>&1 || true   # a full restart loads the panel reliably
else echo "   (--no-restart: run omarchy-restart-shell to load the strip)"; fi
omarchy plugin list 2>/dev/null | grep -q "^${ID}[[:space:]]*enabled" || echo "warning: plugin $ID is not enabled; run: omarchy plugin enable $ID" >&2
echo "done ($("$BIN/omarchy-agents" version)). Press $(grep -m1 '^toggle_key' "$CONF" | cut -d= -f2 | xargs || echo 'SUPER + A') to open. Config: $CONF"
