#!/usr/bin/env bash
# Unit tests for bin/omarchy-agents against a fake hyprctl/omarchy-shell (tests/stubs).
# Usage: tests/run.sh        (needs bash, jq, flock; luac optional for Lua syntax checks)
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd)
PASS=0; FAILN=0
ok() { PASS=$((PASS+1)); echo "  ok   $1"; }
bad() { FAILN=$((FAILN+1)); echo "  FAIL $1"; [[ -n ${2:-} ]] && echo "       $2"; }
check() { if eval "$2"; then ok "$1"; else bad "$1" "$2"; fi; }

# Fresh fake world: HOME, config, fake agent binaries, fake hyprland state.
setup_world() {
  T=$(mktemp -d); export HOME=$T/home FAKE=$T/fake XDG_CONFIG_HOME=$T/home/.config XDG_STATE_HOME=$T/home/.local/state XDG_DATA_HOME=$T/home/.local/share
  unset OMARCHY_AGENTS_CONF
  mkdir -p "$HOME/.local/bin" "$FAKE" "$XDG_CONFIG_HOME/omarchy-agent-switcher" "$XDG_CONFIG_HOME/hypr" "$T/agents"
  export PATH="$ROOT/tests/stubs:$T/agents:/usr/bin:/bin"
  for a in agent-a agent-b agent-c; do printf '#!/bin/sh\nexit 0\n' > "$T/agents/$a"; chmod +x "$T/agents/$a"; done
  ln -sf "$ROOT/bin/omarchy-agents" "$HOME/.local/bin/omarchy-agents"
  OA=$HOME/.local/bin/omarchy-agents; R=$XDG_CONFIG_HOME/hypr/agent-switcher.lua; mkdir -p "$XDG_STATE_HOME/omarchy-agent-switcher"
  cat > "$XDG_CONFIG_HOME/omarchy-agent-switcher/agents.conf" <<CONF
toggle_key = SUPER + A
width = 0.62
height = 0.82
top = 0.06
A | class.a | agent-a | SUPER + SHIFT + A |
B | class.b | agent-b | |
C | class.c | agent-c | |
Missing | class.m | not-installed-agent | SUPER + ALT + M |
CONF
  monitors 0
  echo '[]' > "$FAKE/clients.json"; : > "$FAKE/calls"; : > "$FAKE/shell"
}
monitors() { # monitors <special-visible 0|1> [second monitor]
  local sp=""; [[ $1 == 1 ]] && sp="special:agents"
  local m2=""; [[ ${2:-} == 2 ]] && m2=',{"name":"HDMI-A-1","x":1280,"y":0,"width":1920,"height":1080,"scale":1,"transform":0,"focused":false,"specialWorkspace":{"name":""}}'
  echo "[{\"name\":\"eDP-1\",\"x\":0,\"y\":0,\"width\":1920,\"height\":1080,\"scale\":1.5,\"transform\":0,\"focused\":true,\"specialWorkspace\":{\"name\":\"$sp\"}}$m2]" > "$FAKE/monitors.json"
}
clients() { # clients "class:addr:x" ...
  local out="[" c; for c in "$@"; do IFS=: read -r cl ad x <<<"$c"
    out+="{\"class\":\"$cl\",\"address\":\"$ad\",\"workspace\":{\"name\":\"special:agents\"},\"size\":[793,590],\"at\":[$x,43]},"; done
  echo "${out%,}]" > "$FAKE/clients.json"
}
evals() { grep '^eval' "$FAKE/calls"; }

echo "== config + rules"
setup_world
$OA rules >/dev/null 2>"$T/err"
R=$XDG_CONFIG_HOME/hypr/agent-switcher.lua
check "rules written" "[[ -f $R ]]"
check "rule matches only installed agents" "grep -q '\^(class\\\\\\\\.a|class\\\\\\\\.b|class\\\\\\\\.c)\\\$' $R"
check "missing agent has no bind" "! grep -q 'SUPER + ALT + M' $R"
check "toggle bind points at installed copy" "grep -q \"\\\"$HOME/.local/bin/omarchy-agents toggle\\\"\" $R"
if command -v luac >/dev/null || command -v luac5.4 >/dev/null; then L=$(command -v luac || command -v luac5.4); check "generated Lua parses" "$L -p $R"; fi
check "list shows 3 available agents" "[[ \$($OA list | wc -l) == 3 ]]"

echo "== validation / injection"
setup_world
printf 'Evil"Name | class.x"); os.execute("touch /tmp/pwn | agent-a | |\nQuote"d | class.q | agent-a | SUPER + Q |\nweird = 1\nwidth = 0.5   height = 0.9\n' >> "$XDG_CONFIG_HOME/omarchy-agent-switcher/agents.conf"
$OA rules >/dev/null 2>"$T/err"
check "invalid class rejected with warning" "grep -q 'invalid window class' $T/err"
check "unknown setting warned" "grep -q \"unknown setting 'weird'\" $T/err"
check "multiple settings on one line warned" "grep -q 'several settings on one line' $T/err"
check "quote in name escaped in Lua" "grep -qF 'Quote\\\"d (agent switcher)' \$R"
[[ -n ${L:-} ]] && check "Lua still parses with hostile names" "$L -p $R"

echo "== slide_ms"
setup_world; echo "slide_ms = 0" >> "$XDG_CONFIG_HOME/omarchy-agent-switcher/agents.conf"; $OA rules >/dev/null 2>&1
check "slide_ms=0 disables animation (no speed 0)" "grep -q 'enabled = false' $R && ! grep -q 'speed = 0.00' $R"
setup_world; echo "slide_ms = 5" >> "$XDG_CONFIG_HOME/omarchy-agent-switcher/agents.conf"; $OA rules >/dev/null 2>&1
check "tiny slide_ms clamped to 0.1" "grep -q 'speed = 0.10' $R"

echo "== cycle-key restore"
setup_world; echo '[{"modmask":72,"key":"LEFT","submap":"","description":"Move window to group on left"},{"modmask":72,"key":"RIGHT","submap":"","description":"My custom thing"}]' > "$FAKE/binds.json"
$OA rules >/dev/null 2>"$T/err"
check "Omarchy default restored for LEFT" "grep 'SUPER + ALT + LEFT' $R | grep -q 'restore = {'"
check "custom bind on RIGHT not 'restored' to Omarchy default" "grep 'SUPER + ALT + RIGHT' $R | grep -q 'restore = nil'"
check "custom bind warned" "grep -q 'My custom thing' $T/err"

echo "== runtime: open, switch directions, cursor"
setup_world; clients "class.a:0xa1:243" "class.b:0xb1:2000" "class.c:0xc1:2000"; echo "A" > "$XDG_STATE_HOME/omarchy-agent-switcher/last"
$OA toggle
check "open toggles special workspace" "evals | grep -q \"toggle_special('agents')\""
check "open restores cursor" "evals | grep -q 'cursor.move({ x = 100, y = 200 })'"
check "open: each dispatch pcall-wrapped" "! evals | grep -o 'hl.dispatch' | sed -n 1p | grep -q . || evals | grep -q 'pcall(function() hl.dispatch'"
check "strip summoned with seq" "grep -q '\"seq\":' $FAKE/shell"
monitors 1; : > "$FAKE/calls"
$OA show B
# monitor logical width 1920/1.5=1280 -> slot x 243; right park = 1280+40
check "switch right: B moves into slot" "evals | grep -q \"address:0xb1', x = 243\""
check "switch right: A exits left" "evals | grep -q \"address:0xa1', x = -833\""
check "last = B" "[[ \$(cat $XDG_STATE_HOME/omarchy-agent-switcher/last) == B ]]"
clients "class.a:0xa1:-833" "class.b:0xb1:243" "class.c:0xc1:1320"; : > "$FAKE/calls"
$OA show A
check "switch left: A enters slot" "evals | grep -q \"address:0xa1', x = 243\""
check "switch left: B exits right" "evals | grep -q \"address:0xb1', x = 1320\""
check "no teleport for pre-parked incoming" "! evals | grep -q \"address:0xa1', prop = 'no_anim'\""

echo "== multi-monitor parking"
setup_world; monitors 1 2; clients "class.a:0xa1:243" "class.b:0xb1:3240" "class.c:0xc1:3240"; echo A > "$XDG_STATE_HOME/omarchy-agent-switcher/last"
$OA show B
check "outgoing parks left of the whole desktop" "evals | grep -q \"address:0xa1', x = -833\""
check "incoming came from right of the whole desktop (3240)" "! evals | grep -q \"address:0xb1', prop = 'no_anim'\""

echo "== unknown / missing agents"
setup_world; clients "class.a:0xa1:243"; : > "$FAKE/calls"
$OA show Nope 2>"$T/err"; rc=$?; : "$rc"
check "show unknown -> error, nonzero" "(( rc != 0 )) && grep -q \"no available agent named 'Nope'\" $T/err"
check "show unknown -> no dispatch" "! grep -q . $FAKE/calls"
$OA direct class.m 2>/dev/null; check "direct for missing agent does nothing" "! grep -q . $FAKE/calls"
$OA direct class.m,class.b --start-hidden
check "start_hidden skips missing agent, launches only B" "grep -q 'launch B' $XDG_STATE_HOME/omarchy-agent-switcher/log && ! grep -q 'launch A' $XDG_STATE_HOME/omarchy-agent-switcher/log"

echo "== hide restores opacity; autohide"
setup_world; monitors 1; clients "class.a:0xa1:243" "class.b:0xb1:1320"
$OA hide
check "hide restores opacity on all agents" "evals | grep -q \"address:0xb1', prop = 'opacity', value = '0.82'\""
: > "$FAKE/calls"; echo '{"address":"0xfff","workspace":{"name":"1"}}' > "$FAKE/activewindow.json"; rm -f "$XDG_STATE_HOME/omarchy-agent-switcher/acted"
$OA autohide; check "autohide closes when focus is on a regular window" "evals | grep -q toggle_special"
: > "$FAKE/calls"; echo '{}' > "$FAKE/activewindow.json"
$OA autohide; check "autohide closes when nothing is focused" "evals | grep -q toggle_special"
: > "$FAKE/calls"; echo '{"address":"0xa1","workspace":{"name":"special:agents"}}' > "$FAKE/activewindow.json"
$OA autohide; check "autohide keeps panel when an agent is focused" "! evals | grep -q toggle_special"
date +%s%3N > "$XDG_STATE_HOME/omarchy-agent-switcher/acted"; echo '{}' > "$FAKE/activewindow.json"; : > "$FAKE/calls"
$OA autohide; check "autohide ignores events right after our own action" "! grep -q . $FAKE/calls"

echo "== resolve_cmd keeps arguments verbatim"
setup_world
echo "Q | class.q | env FOO=1 agent-a --flag 'two  spaces' |" >> "$XDG_CONFIG_HOME/omarchy-agent-switcher/agents.conf"
clients "class.a:0xa1:243"; $OA show Q >/dev/null 2>&1
check "program resolved, args intact" "grep -q \"launch Q: env FOO=1 $T/agents/agent-a --flag 'two  spaces'\" $XDG_STATE_HOME/omarchy-agent-switcher/log"

echo "== hint subcommand without config"
setup_world; rm "$XDG_CONFIG_HOME/omarchy-agent-switcher/agents.conf"; mkdir -p "$XDG_DATA_HOME/omarchy-agent-switcher"; cp "$ROOT/share/agents.conf.default" "$XDG_DATA_HOME/omarchy-agent-switcher/"
$OA hint off >/dev/null 2>&1; check "hint off creates config with show_hint = false" "grep -q '^show_hint *= false' $XDG_CONFIG_HOME/omarchy-agent-switcher/agents.conf"

echo "== uninstall never eats hyprland.lua"
setup_world
H=$XDG_CONFIG_HOME/hypr/hyprland.lua; printf 'line1\n-- omarchy-agent-switcher (remove with uninstall.sh)\nline-after-marker\nlast-line\n' > "$H"
mkdir -p "$T/repo"; cp -r "$ROOT/plugin" "$ROOT/uninstall.sh" "$T/repo/"; bash "$T/repo/uninstall.sh" >/dev/null 2>&1
check "only the marker line removed when require line is missing" "[[ \$(cat $H) == \$'line1\nline-after-marker\nlast-line' ]]"

echo
echo "passed: $PASS  failed: $FAILN"
(( FAILN == 0 ))
