#!/usr/bin/env bash
# Shared installer/CLI guard. Optional arguments reuse runtime snapshots.
desktop_ready() {
  local monitors=${1:-} clients=${2:-} tmp="" result
  if [[ -z $monitors || -z $clients ]]; then
    tmp=$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/agent-switcher-desktop.XXXXXX") || return 1
    monitors=$tmp/monitors; clients=$tmp/clients
    hyprctl -j monitors > "$monitors" 2>/dev/null &
    hyprctl -j clients > "$clients" 2>/dev/null &
    wait
  fi
  jq -en --slurpfile m "$monitors" --slurpfile c "$clients" '
    ($m[0] | type=="array" and length>0)
    and ($c[0] | type=="array")
    and all($m[0][]; ((.solitaryBlockedBy // []) | index("LOCK"))==null)
    and all($c[0][]; [(.class // "" | ascii_downcase), (.initialClass // "" | ascii_downcase)] | index("org.omarchy.screensaver")==null)
  ' >/dev/null 2>&1
  result=$?
  [[ -z $tmp ]] || rm -rf "$tmp"
  return "$result"
}
