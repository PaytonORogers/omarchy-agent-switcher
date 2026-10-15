#!/usr/bin/env bash
# Shared installer/CLI guard. Optional arguments reuse runtime snapshots.
desktop_ready() {
  local monitors=${1:-} clients=${2:-} tmp="" result locked idle lock_status
  # solitaryBlockedBy stops at its first blocker, so a missing LOCK is not
  # proof of an unlocked session. Also check the shell's requested lock state
  # and the screensaver launch grace period, before a terminal has mapped.
  lock_status=$(timeout 2 omarchy-shell lock status 2>/dev/null || true)
  if jq -e 'all(.requested, .pending, .sessionLocked, .secure; type=="boolean")' <<<"$lock_status" >/dev/null 2>&1; then
    # The aggregate locked property can remain latched after an unlock. These
    # fields describe the request and actual ext-session-lock state directly.
    if jq -e '.requested or .pending or .sessionLocked or .secure' <<<"$lock_status" >/dev/null 2>&1; then return 1; fi
  else
    locked=$(timeout 2 omarchy-shell lock isLocked 2>/dev/null || true)
    [[ $locked == true ]] && return 1
  fi
  idle=$(timeout 2 omarchy-shell idle status 2>/dev/null || true)
  if jq -e '(.screensaverStarted == true) or ((.screensaverWindows // 0)>0) or (.processes.screensaver == true) or (.processes.lock == true)' <<<"$idle" >/dev/null 2>&1; then return 1; fi
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
