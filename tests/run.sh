#!/usr/bin/env bash
# shellcheck disable=SC2034  # variables are read inside check's eval
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
  export XDG_RUNTIME_DIR=$T/runtime
  mkdir -p "$XDG_RUNTIME_DIR"
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
  echo "[{\"name\":\"eDP-1\",\"x\":0,\"y\":0,\"width\":1920,\"height\":1080,\"scale\":1.5,\"transform\":0,\"focused\":true,\"activeWorkspace\":{\"id\":2},\"specialWorkspace\":{\"name\":\"$sp\"}}$m2]" > "$FAKE/monitors.json"
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
check "rule matches only installed agents" "grep -q '(?i)\\^(class\\\\\\\\.a|class\\\\\\\\.b|class\\\\\\\\.c)\\\$' $R"
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

echo "== cursor class case and single instance"
setup_world
sed -i 's/^A | class.a | agent-a/A | Cursor | cursor/' "$XDG_CONFIG_HOME/omarchy-agent-switcher/agents.conf"
printf '#!/bin/sh\nexit 0\n' > "$T/agents/cursor"; chmod +x "$T/agents/cursor"
clients "cursor:0xc0:243"
: > "$XDG_STATE_HOME/omarchy-agent-switcher/log"; : > "$FAKE/calls"
$OA show A >/dev/null
check "Wayland class cursor matches configured Cursor" "evals | grep -q 'address:0xc0'"
check "matching window is not launched again" "! grep -q 'launch A:' $XDG_STATE_HOME/omarchy-agent-switcher/log"
echo '[{"class":"code","initialClass":"cursor","address":"0x1c1","workspace":{"name":"special:agents"},"size":[793,590],"at":[243,43]}]' > "$FAKE/clients.json"
: > "$FAKE/calls"
$OA show A >/dev/null
check "initialClass cursor matches configured Cursor" "evals | grep -q 'address:0x1c1'"
clients; : > "$FAKE/calls"; : > "$XDG_STATE_HOME/omarchy-agent-switcher/log"
bindir=$(mktemp -d); cp "$(command -v sleep)" "$bindir/cursor"; "$bindir/cursor" 30 & hold=$!
$OA show A >/dev/null
check "running cursor is not launched again" "grep -q 'already running' $XDG_STATE_HOME/omarchy-agent-switcher/log && ! grep -q 'launch A: $T/agents/cursor' $XDG_STATE_HOME/omarchy-agent-switcher/log"
kill "$hold" 2>/dev/null || true; wait "$hold" 2>/dev/null || true; rm -rf "$bindir"

echo "== cursor icon"
setup_world
sed -i 's/^A | class.a | agent-a | SUPER + SHIFT + A |/A | class.a | cursor | SUPER + SHIFT + A | cursor/' "$XDG_CONFIG_HOME/omarchy-agent-switcher/agents.conf"
printf '#!/bin/sh\nexit 0\n' > "$T/agents/cursor"; chmod +x "$T/agents/cursor"
mkdir -p "$XDG_DATA_HOME/applications" "$XDG_DATA_HOME/icons/hicolor/48x48/apps"
printf '[Desktop Entry]\nName=Cursor\nExec=cursor\nIcon=co.anysphere.cursor\nType=Application\n' > "$XDG_DATA_HOME/applications/cursor.desktop"
: > "$XDG_DATA_HOME/icons/hicolor/48x48/apps/co.anysphere.cursor.png"
clients "class.a:0xa1:243"
: > "$FAKE/shell"; $OA show A >/dev/null 2>&1; sleep 0.5
check "icon name cursor falls back to the desktop Icon=" "grep summon \$FAKE/shell | tail -1 | grep -q 'image://icon/co.anysphere.cursor'"
: > "$XDG_DATA_HOME/icons/hicolor/48x48/apps/mybrand.png"
sed -i 's/| cursor$/| mybrand/' "$XDG_CONFIG_HOME/omarchy-agent-switcher/agents.conf"
: > "$FAKE/shell"; $OA show A >/dev/null 2>&1; sleep 0.5
check "an installed theme name is kept" "grep summon \$FAKE/shell | tail -1 | grep -q 'image://icon/mybrand' && ! grep summon \$FAKE/shell | tail -1 | grep -q co.anysphere.cursor"
mkdir -p "$XDG_DATA_HOME/omarchy-agent-switcher/icons"
cp "$ROOT/share/icons/grok.svg" "$XDG_DATA_HOME/omarchy-agent-switcher/icons/grok.svg"
sed -i 's/| mybrand$/| grok/' "$XDG_CONFIG_HOME/omarchy-agent-switcher/agents.conf"
: > "$FAKE/shell"; $OA show A >/dev/null 2>&1; sleep 0.5
check "bundled svg wins over the desktop icon" "grep summon \$FAKE/shell | tail -1 | grep -q 'file://.*/icons/grok.svg'"
printf 'x' > "$T/cursor.png"
sed -i "s#| grok\$#| $T/cursor.png#" "$XDG_CONFIG_HOME/omarchy-agent-switcher/agents.conf"
: > "$FAKE/shell"; $OA show A >/dev/null 2>&1; sleep 0.5
check "absolute icon path is a file URL" "grep summon \$FAKE/shell | tail -1 | grep -q 'file://$T/cursor.png'"
check "registry lists Cursor's real icon name" "grep -q 'uwsm-app -- cursor[[:space:]]*| co\\.anysphere\\.cursor' $ROOT/share/registry.conf"

echo "== keyboard focus stays on the agent"
setup_world; monitors 0; clients "class.a:0xa1:243"; : > "$FAKE/calls"
$OA show A >/dev/null 2>&1; sleep 0.6
check "focus re-sent to the agent after the strip maps" "evals | tail -1 | grep -q \"focus({ window = 'address:0xa1' })\""
echo '{"address":"0xb9","workspace":{"name":"3"}}' > "$FAKE/activewindow.json"; monitors 0; : > "$FAKE/calls"
$OA show A >/dev/null 2>&1; sleep 0.6
check "no refocus when another window took focus meanwhile (first link click)" "[[ \$(evals | grep -c \"focus({ window = 'address:0xa1' })\") == 1 ]]"
rm -f "$FAKE/activewindow.json"
check "post-show refocus puts the pointer back" "grep -q 'cursor.move({ x = \${cp%%,\*}' $ROOT/bin/omarchy-agents"
check "normal strip opening leaves keyboard focus in the agent" "grep -q 'keyboardFocus: root.arranging || root.controlMode' $ROOT/plugin/Switcher.qml"
echo "== evict non-agent windows from the agents workspace"
setup_world
echo '[{"name":"eDP-1","x":0,"y":0,"width":1920,"height":1080,"scale":1.5,"transform":0,"focused":true,"activeWorkspace":{"id":3,"name":"3"},"specialWorkspace":{"name":"special:agents"}}]' > "$FAKE/monitors.json"
echo '[{"class":"class.a","address":"0xa1","workspace":{"name":"special:agents"},"size":[793,590],"at":[243,43]},{"class":"chrome-x.com__-Default","initialClass":"chrome-x.com__-Default","address":"0xb2","workspace":{"name":"special:agents"},"size":[800,600],"at":[0,0]},{"class":"CLASS.A","address":"0xa9","workspace":{"name":"special:agents"},"size":[793,590],"at":[243,43]},{"class":"kitty","address":"0xc3","workspace":{"name":"2"},"size":[800,600],"at":[0,0]}]' > "$FAKE/clients.json"
: > "$FAKE/calls"; $OA evict 0xb2
check "web app on special:agents moves to the active workspace" "evals | grep -q \"workspace = '3', follow = false, window = 'address:0xb2'\""
check "evicted window is focused" "evals | grep -q \"focus({ window = 'address:0xb2' })\""
check "panel hides via the normal hide path" "evals | grep -q toggle_special && evals | grep -q 'agent_switcher.off'"
: > "$FAKE/calls"; $OA evict 0xa9
check "agent class (any case) is not evicted" "! grep -q . $FAKE/calls"
: > "$FAKE/calls"; $OA evict 0xc3
check "window on a regular workspace is left alone" "! grep -q . $FAKE/calls"
: > "$FAKE/calls"; $OA evict 0xdead; $OA evict notanaddr
check "unknown or bad address does nothing" "! grep -q . $FAKE/calls"
check "plugin evicts on openwindow even when closed, no browser list" "grep -q 'run(\\[\"evict\"' $ROOT/plugin/Switcher.qml && ! grep -qiE 'chrom|firefox|zen' $ROOT/plugin/Switcher.qml"

echo "== Esc closes the cheat sheet"
setup_world; monitors 1; clients "class.a:0xa1:243"; $OA rules >/dev/null 2>&1; R=$XDG_CONFIG_HOME/hypr/agent-switcher.lua
check "Esc bind only through sheet_keys, removed on off()" "grep -q 'sheet-close' $R && grep -q 'function agent_switcher.sheet_keys' $R && grep -q 'pcall(agent_switcher.sheet_keys, false)' $R"
check "no bare Escape bind at load time" "! grep -qE '^(o\\.bind|ab)\\(\"Escape' $R"
: > "$FAKE/calls"; $OA sheet-keys on; check "sheet-keys on adds the bind" "evals | grep -q 'sheet_keys(true)'"
: > "$FAKE/calls"; $OA sheet-keys off; check "sheet-keys off removes it" "evals | grep -q 'sheet_keys(false)'"
: > "$FAKE/shell"; $OA sheet-close; check "sheet-close asks the strip to close the sheet" "grep -qx 'agentswitcher closeSheet' $FAKE/shell"
echo '[{"modmask":0,"key":"Escape","submap":"","dispatcher":"exec","arg":"x","description":"Mine"}]' > "$FAKE/binds.json"
$OA rules >/dev/null 2>&1; check "existing Escape bind is left alone" "grep -q 'sheet_esc = nil' $R"
rm -f "$FAKE/binds.json"

echo "== strip edge"
setup_world; monitors 0; clients "class.a:0xa1:243"
G=$($OA geometry); check "no shell.json -> bottom edge" "[[ \$G == *edge=bottom* ]]"
mkdir -p "$XDG_CONFIG_HOME/omarchy"; echo '{"bar":{"position":"top"}}' > "$XDG_CONFIG_HOME/omarchy/shell.json"
G=$($OA geometry); check "bar on top -> strip on top, panel below it" "[[ \$G == *edge=top* && \$G == *strip_top=10* ]] && [[ \$G =~ panel=[0-9]+x[0-9]+\+[0-9]+\+80 ]]"
$OA rules >/dev/null 2>&1; R=$XDG_CONFIG_HOME/hypr/agent-switcher.lua
check "top edge: no workspace rule (it only applies to new workspaces)" "! grep -q 'workspace_rule' $R"
monitors 0; clients "class.a:0xa1:243"; : > "$FAKE/calls"; $OA show A >/dev/null 2>&1
check "top edge: open drops in from the top, then restores the leaves" "evals | grep -q \"specialWorkspaceIn', enabled = true, speed = 3, bezier = 'easeOutQuint', style = 'slidevert top'\" && evals | grep -q \"specialWorkspaceOut'.*slidevert bottom\" && evals | grep -q 'leaf = \"specialWorkspaceIn\".*style = \"slidevert\" })'"
monitors 1; : > "$FAKE/calls"; $OA hide >/dev/null 2>&1
check "top edge: hide leaves upward and restores the cursor" "evals | grep -q 'slidevert bottom' && evals | grep -q 'cursor.move'"
: > "$FAKE/shell"; $OA show A >/dev/null 2>&1; sleep 0.5
check "payload carries edge top" "grep summon $FAKE/shell | tail -1 | grep -q '\"edge\":\"top\"'"
echo '{"bar":{"position":"left"}}' > "$XDG_CONFIG_HOME/omarchy/shell.json"
G=$($OA geometry); check "bar on the left -> bottom" "[[ \$G == *edge=bottom* ]]"
$OA rules >/dev/null 2>&1; check "bottom edge: no slide override" "! grep -q 'slidevert top' $R"
echo "strip_edge = top" >> "$XDG_CONFIG_HOME/omarchy-agent-switcher/agents.conf"
G=$($OA geometry); check "strip_edge = top overrides the bar" "[[ \$G == *edge=top* ]]"
echo '{"bar":{"position":"top"}}' > "$XDG_CONFIG_HOME/omarchy/shell.json"; echo "strip_edge = bottom" >> "$XDG_CONFIG_HOME/omarchy-agent-switcher/agents.conf"
G=$($OA geometry); check "strip_edge = bottom overrides a top bar" "[[ \$G == *edge=bottom* ]]"
echo "== fake Cursor end to end (registry -> setup -> rules -> window match -> icon)"
setup_world; rm "$XDG_CONFIG_HOME/omarchy-agent-switcher/agents.conf"
D=$XDG_DATA_HOME/omarchy-agent-switcher; mkdir -p "$D"; cp "$ROOT/share/registry.conf" "$ROOT/share/agents.conf.default" "$D/"
for b in agent-a agent-b agent-c; do rm -f "$T/agents/$b"; done
printf '#!/bin/sh\nexit 0\n' > "$T/agents/cursor"; chmod +x "$T/agents/cursor"
mkdir -p "$XDG_DATA_HOME/applications" "$XDG_DATA_HOME/icons/hicolor/48x48/apps"
printf '[Desktop Entry]\nName=Cursor\nExec=cursor %%F\nIcon=co.anysphere.cursor\nStartupWMClass=Cursor\nType=Application\n' > "$XDG_DATA_HOME/applications/cursor.desktop"
: > "$XDG_DATA_HOME/icons/hicolor/48x48/apps/co.anysphere.cursor.png"
CF=$XDG_CONFIG_HOME/omarchy-agent-switcher/agents.conf
OMARCHY_AGENTS_NO_GUM=1 $OA setup --yes </dev/null >/dev/null 2>&1
check "setup detects the fake cursor binary from the registry" "grep -qE '^Cursor +\| Cursor +\| uwsm-app -- cursor' $CF"
check "setup writes Cursor's real icon name" "grep -E '^Cursor ' $CF | grep -q 'co.anysphere.cursor'"
$OA rules >/dev/null 2>&1
RX=$(grep -o 'o.window("(?i)^([^"]*)\$"' $R | head -1 | sed 's/^o.window("//; s/"$//; s/\\\\\\\\/\\\\/g')
check "generated window rule is case-insensitive and names Cursor" "[[ \$RX == '(?i)^('*Cursor*')\$' ]]"
check "rule regex matches Wayland app_id 'cursor' and 'Cursor', not 'cursor-agent'" "python3 -c 'import re,sys; r=re.compile(sys.argv[1]); sys.exit(0 if r.match(\"cursor\") and r.match(\"Cursor\") and not r.match(\"cursor-agent\") else 1)' \"\$RX\""
monitors 0; clients "cursor:0xc0:243"; : > "$FAKE/calls"; : > "$FAKE/shell"
$OA show Cursor >/dev/null 2>&1; sleep 0.5
check "app_id cursor window is the Cursor tab (moved + focused, not relaunched)" "evals | grep -q 'address:0xc0' && ! grep -q 'launch Cursor' $XDG_STATE_HOME/omarchy-agent-switcher/log"
check "Cursor tab icon resolves to the theme icon" "grep summon $FAKE/shell | tail -1 | grep -q 'image://icon/co.anysphere.cursor'"
echo '[]' > "$FAKE/clients.json"; : > "$FAKE/calls"; monitors 0
$OA show Cursor >/dev/null 2>&1; sleep 0.3
check "no window yet: launches via the registry command" "grep -q 'launch Cursor' $XDG_STATE_HOME/omarchy-agent-switcher/log"

echo "== agent status dots"
setup_world; monitors 0; clients "class.a:0xa1:243" "class.b:0xb1:243"
C=$XDG_CONFIG_HOME/omarchy-agent-switcher/agents.conf
sed -i 's/^A | class.a | agent-a | SUPER + SHIFT + A |$/A | class.a | agent-a | SUPER + SHIFT + A | | claude/; s/^B | class.b | agent-b | |$/B | class.b | agent-b | | | grok/; s/^C | class.c | agent-c | |$/C | class.c | agent-c | | | grok-bot/' "$C"
SD=$XDG_STATE_HOME/omarchy-agent-switcher/status
st() { $OA status --json | jq -r --arg c "$1" '.agents[] | select(.class == $c) | .state'; }
check "no status -> idle" "[[ \$(st class.a) == idle && \$($OA status --json | jq -r .top) == idle ]]"
$OA status-set A working; check "status-set by name" "[[ \$(st class.a) == working ]]"
check "status-set refreshes the strip" "grep -qx 'agentswitcher status' $FAKE/shell"
! $OA status-set A bogus 2>/dev/null; check "invalid state rejected" "[[ \$? == 0 && \$(st class.a) == working ]]"
$OA status-set class.b 'done'; check "top: done beats working" "[[ \$($OA status --json | jq -r .top) == done ]]"
$OA status-set C error; check "top: error beats done" "[[ \$($OA status --json | jq -r .top) == error ]]"
$OA status-set A approval; check "top: approval beats error" "[[ \$($OA status --json | jq -r .top) == approval ]]"
echo "working $(( $(date +%s) - 700 ))" > "$SD/class.a"; check "stale working (>10 min) shows idle" "[[ \$(st class.a) == idle ]]"
echo "done $(( $(date +%s) - 7000 ))" > "$SD/class.a"; check "done never goes stale" "[[ \$(st class.a) == done ]]"
$OA status-set C idle; check "idle removes the file" "[[ ! -f $SD/class.c ]]"
: > "$FAKE/shell"; $OA show A >/dev/null 2>&1; sleep 0.5
check "payload carries per-tab status" "grep summon $FAKE/shell | tail -1 | jq -e '.agents[] | select(.name==\"B\") | .status == \"done\"' >/dev/null 2>&1 || grep summon $FAKE/shell | tail -1 | grep -q '\"name\":\"B\"[^}]*\"status\":\"done\"'"
check "focusing a done tab clears it" "[[ \$(st class.a) == idle ]]"
monitors 1; $OA show B >/dev/null 2>&1; check "switching to a done tab clears it" "[[ \$(st class.b) == idle ]]"
$OA status-set A working; $OA show A >/dev/null 2>&1; check "focusing keeps working" "[[ \$(st class.a) == working ]]"
monitors 0
echo '{"hook_event_name":"UserPromptSubmit","session_id":"x"}' | $OA hook claude; check "claude prompt -> working" "[[ \$(st class.a) == working ]]"
echo '{"hook_event_name":"Notification","message":"Claude needs your permission to use Bash"}' | $OA hook claude; check "claude permission notification -> approval" "[[ \$(st class.a) == approval ]]"
echo '{"hook_event_name":"Stop"}' | $OA hook claude; check "claude stop -> done" "[[ \$(st class.a) == done ]]"
OUT=$(echo '{"hook_event_name":"Stop"}' | $OA hook claude); check "hook prints nothing" "[[ -z \$OUT ]]"
echo '{"hook_event_name":"StopFailure","hookEventName":"stop_failure"}' | $OA hook claude
check "grok payload via Claude's settings is tagged grok" "[[ \$(st class.b) == error && \$(st class.a) == done ]]"
echo '{"hook_event_name":"PermissionRequest"}' | $OA hook codex; check "agent not configured: ignored" "! ls $SD | grep -q codex"
echo '{"hook_event_name":"PreToolUse","hookEventName":"pre_tool_use","toolName":"ask_user_question"}' | $OA hook grok
check "Grok Build ask_user_question -> approval" "[[ \$(st class.b) == approval ]]"
echo '{"hook_event_name":"Notification","hookEventName":"notification","notificationType":"idle_prompt"}' | $OA hook grok
check "idle ping keeps the open question amber" "[[ \$(st class.b) == approval ]]"
echo '{"hook_event_name":"PostToolUse","hookEventName":"post_tool_use","toolName":"ask_user_question"}' | $OA hook grok
check "answered question -> working" "[[ \$(st class.b) == working ]]"
echo '{"hook_event_name":"PreToolUse","tool_name":"AskUserQuestion"}' | $OA hook claude
check "Claude AskUserQuestion -> approval" "[[ \$(st class.a) == approval ]]"
echo 'not json' | $OA hook claude; check "garbage input is harmless" "[[ \$? == 0 ]]"
printf 'signal time=1 sender=:1.5 -> destination=org.freedesktop.Notifications serial=9 path=/org/freedesktop/Notifications; interface=org.freedesktop.Notifications; member=Notify\n   string "Signal"\n' | $OA notif-watch --stdin
check "other app notification ignored" "[[ \$(st class.c) == idle ]]"
printf 'signal time=1 sender=:1.5 -> destination=org.freedesktop.Notifications serial=9 path=/org/freedesktop/Notifications; interface=org.freedesktop.Notifications; member=Notify\n   string "Grok Bot"\n   uint32 0\n' | $OA notif-watch --stdin
check "Grok Bot notification -> done (new reply)" "[[ \$(st class.c) == done ]]"

echo "== hook merge / unmerge"
mkdir -p "$HOME/.claude"; echo '{"model":"opus","hooks":{"Stop":[{"hooks":[{"type":"command","command":"mine.sh"}]}]}}' > "$HOME/.claude/settings.json"
cp "$HOME/.claude/settings.json" "$T/orig.json"
$OA hooks install >/dev/null
CS=$HOME/.claude/settings.json
check "claude: our hooks added, theirs kept" "jq -e '.model==\"opus\" and (.hooks.Stop|length)==2 and .hooks.Stop[0].hooks[0].command==\"mine.sh\" and (.hooks.UserPromptSubmit[0].hooks[0].command|test(\"hook claude\$\"))' $CS >/dev/null"
check "claude: backup made" "ls $HOME/.claude/ | grep -q 'settings.json.bak-agent-switcher-'"
check "codex + grok files created" "jq -e '.hooks.PermissionRequest[0].hooks[0].command|test(\"hook codex\$\")' $HOME/.codex/hooks.json >/dev/null && jq -e '.hooks.StopFailure[0].hooks[0].command|test(\"hook grok\$\")' $HOME/.grok/hooks/omarchy-agent-switcher.json >/dev/null"
A1=$(cat $CS $HOME/.codex/hooks.json); nb=$(find "$HOME/.claude" -maxdepth 1 -name '*bak-agent*' 2>/dev/null | wc -l)
$OA hooks install >/dev/null; check "install is idempotent (no dupes, no new backup)" "[[ \$(cat $CS $HOME/.codex/hooks.json) == \"\$A1\" && \$(ls $HOME/.claude | grep -c bak-agent) == $nb ]]"
$OA hooks uninstall >/dev/null
check "first backup still holds the original" "[[ \$(jq -cS . \$(ls $HOME/.claude/settings.json.bak-agent-switcher-* | sort | head -1)) == \"\$(jq -cS . $T/orig.json)\" ]]"
check "uninstall restores the user's settings exactly" "[[ \$(jq -cS . $CS) == \"\$(jq -cS . $T/orig.json)\" ]]"
check "uninstall removes files we created" "[[ ! -f $HOME/.codex/hooks.json && ! -f $HOME/.grok/hooks/omarchy-agent-switcher.json ]]"
$OA hooks uninstall >/dev/null; check "uninstall is idempotent" "[[ \$(jq -cS . $CS) == \"\$(jq -cS . $T/orig.json)\" ]]"
mkdir -p "$XDG_CONFIG_HOME/omarchy"; echo '{"bar":{"centerAnchor":"omarchy.clock","layout":{"center":[{"id":"omarchy.clock"},{"id":"omarchy.weather"}],"right":[{"id":"payton.chatbar"}]}}}' > "$XDG_CONFIG_HOME/omarchy/shell.json"
$OA bar-entry add >/dev/null; $OA bar-entry add >/dev/null
check "bar icon placed directly left of the clock, once" "[[ \$(jq -c '[.bar.layout.center[].id]' $XDG_CONFIG_HOME/omarchy/shell.json) == '[\"io.github.paytonorogers.agent-switcher\",\"omarchy.clock\",\"omarchy.weather\"]' && \$(jq -r .bar.centerAnchor $XDG_CONFIG_HOME/omarchy/shell.json) == omarchy.clock ]]"
$OA bar-entry remove >/dev/null; check "bar icon removed" "[[ \$(jq -c '[.bar.layout.center[].id]' $XDG_CONFIG_HOME/omarchy/shell.json) == '[\"omarchy.clock\",\"omarchy.weather\"]' ]]"
check "manifest declares the bar widget" "jq -e '(.kinds|index(\"bar-widget\")) and .entryPoints.barWidget==\"plugin/BarIcon.qml\"' $ROOT/manifest.json >/dev/null && [[ -f $ROOT/plugin/BarIcon.qml ]]"
echo "== passive refresh keeps auto-hide"
check "strip grace period starts only on open or tab switch" "grep -q 'if (!opened || (p.active !== undefined && p.active !== active)) lastShow = Date.now()' $ROOT/plugin/Switcher.qml && [[ \$(grep -c 'lastShow = Date.now()' $ROOT/plugin/Switcher.qml) == 1 ]]"
setup_world; monitors 1; clients "class.a:0xa1:243"; echo A > "$XDG_STATE_HOME/omarchy-agent-switcher/last"; rm -f "$XDG_STATE_HOME/omarchy-agent-switcher/acted"
$OA show A >/dev/null 2>&1; check "re-showing the active tab (refresh) doesn't mark our own action" "[[ ! -f $XDG_STATE_HOME/omarchy-agent-switcher/acted ]]"

echo "== status sound"
setup_world; SL=$T/sound.log; printf '#!/bin/sh\necho "$*" >> %s\n' "$SL" > "$T/rec"; chmod +x "$T/rec"; export OA_SOUND_PLAYER=$T/rec
snd() { sleep 0.3; cat "$SL" 2>/dev/null; }; sreset() { : > "$SL"; rm -f "$XDG_STATE_HOME/omarchy-agent-switcher/sound-last"; }
sreset; $OA status-set A working; check "working is silent" "[[ -z \$(snd) ]]"
sreset; $OA status-set A approval; check "approval plays message-new-instant (default)" "snd | grep -q 'message-new-instant'"
sreset; $OA status-set A approval; check "same state again is silent" "[[ -z \$(snd) ]]"
sreset; $OA status-set B 'done'; check "done plays complete" "snd | grep -q 'complete'"
$OA status-set C error; check "burst within 3s is rate-limited" "[[ \$(snd | wc -l) == 1 ]]"
sreset; $OA status-set C idle; echo 'sound = chime' >> "$XDG_CONFIG_HOME/omarchy-agent-switcher/agents.conf"; $OA status-set C error
check "chime mode plays the bundled error chime" "snd | grep -q 'sounds/chime-error.wav'"
check "bundled chimes exist and are licensed" "[[ -s $ROOT/share/sounds/chime-approval.wav && -s $ROOT/share/sounds/chime-done.wav && -s $ROOT/share/sounds/chime-error.wav ]] && grep -q CC0 $ROOT/share/sounds/LICENSE"
sreset; $OA status-set C idle; sed -i 's/^sound = chime/sound = off/' "$XDG_CONFIG_HOME/omarchy-agent-switcher/agents.conf"; $OA status-set C error; check "sound = off is silent" "[[ -z \$(snd) ]]"
sed -i '/^sound = /d' "$XDG_CONFIG_HOME/omarchy-agent-switcher/agents.conf"
sreset; $OA status-set C idle; mkdir -p "$XDG_STATE_HOME/omarchy"; echo '{"version":3,"dnd":true}' > "$XDG_STATE_HOME/omarchy/notifications.json"
$OA status-set C error; check "do-not-disturb is respected" "[[ -z \$(snd) ]]"; rm -f "$XDG_STATE_HOME/omarchy/notifications.json"
sreset; $OA status-set A idle; monitors 1; echo '{"class":"class.a","workspace":{"name":"special:agents"}}' > "$FAKE/activewindow.json"; $OA status-set A 'done'
check "no sound when that tab is open and focused" "[[ -z \$(snd) ]]"
sreset; $OA status-set B idle; $OA status-set B 'done'; check "other agent's sound still plays while A is in view" "snd | grep -q complete"
sreset; $OA status-set A idle; monitors 0; echo '{"class":"Class.A","workspace":{"name":"3"}}' > "$FAKE/activewindow.json"; $OA status-set A 'done'
check "focused on a normal workspace (class case-insensitive) is silent" "[[ -z \$(snd) ]]"
sreset; $OA status-set A idle; echo '{"class":"class.a","workspace":{"name":"special:agents"}}' > "$FAKE/activewindow.json"; $OA status-set A 'done'
check "agent focused but panel hidden still plays" "snd | grep -q complete"
sreset; $OA status-set A idle; monitors 1; printf 'method call time=1 sender=:1.9 -> destination=org.freedesktop.Notifications serial=7 path=/org/freedesktop/Notifications; interface=org.freedesktop.Notifications; member=Notify\n   string "Grok Bot"\n' > "$T/notif"
sed -i 's/^A | class.a/A | class.a/' "$XDG_CONFIG_HOME/omarchy-agent-switcher/agents.conf"; echo 'GB | grok-bot | agent-a | | | grok-bot' >> "$XDG_CONFIG_HOME/omarchy-agent-switcher/agents.conf"
echo '{"class":"grok-bot","workspace":{"name":"special:agents"}}' > "$FAKE/activewindow.json"; $OA notif-watch --stdin < "$T/notif" >/dev/null 2>&1
check "Grok Bot reply notification while Grok Bot is focused: status done, no sound" "[[ \$(st grok-bot) == done && -z \$(snd) ]]"
check "default player is pw-play with the theme file" "grep -q 'cmd=(pw-play \"\$f\")   # fastest start' $ROOT/bin/omarchy-agents"
unset OA_SOUND_PLAYER
echo "== click_through doesn't use modal dim_around"
setup_world; monitors 0; clients "class.a:0xa1:243"; : > "$FAKE/calls"; $OA show A >/dev/null 2>&1
check "click_through: agent gets dim_around 0 (no full-monitor hit box)" "evals | grep -q \"prop = 'dim_around', value = '0'\" && ! evals | grep -q \"dim_around', value = '1'\""
$OA rules >/dev/null 2>&1; check "rules dim via dim_special and restore it" "grep -q 'dim_special = math.max' $R && grep -q 'dim_special = s.ds' $R && grep -q 'agent_switcher.dim = true' $R"
echo 'click_through = false' >> "$XDG_CONFIG_HOME/omarchy-agent-switcher/agents.conf"; : > "$FAKE/calls"; $OA hide >/dev/null 2>&1; $OA show A >/dev/null 2>&1
check "click_through = false keeps modal dim_around" "evals | grep -q \"dim_around', value = '1'\""

echo "== hover never resizes the strip"
check "window width uses fixed hint metrics, not the live hint text" "grep -q 'hintLine.visible ? hintMetrics.width + 16' $ROOT/plugin/Switcher.qml && ! grep -q 'hintLine.implicitWidth' $ROOT/plugin/Switcher.qml"
check "hint line visibility doesn't depend on hover" "grep -q 'visible: (root.hint || root.arranging) && root.controlMode === \"\"' $ROOT/plugin/Switcher.qml"
check "no hidden reserved percent width on tabs" "! grep -q 'usageDisplay === \"percent\" || ma.containsMouse' $ROOT/plugin/Switcher.qml"

echo "== QML syntax"
QL=$(command -v qmllint || echo /usr/lib/qt6/bin/qmllint)
if [[ -x $QL ]]; then for f in "$ROOT"/plugin/*.qml; do
  check "$(basename "$f") has no QML syntax errors" "! \"$QL\" \"$f\" 2>&1 | grep -qiE 'syntax error|expected token|unexpected token'"; done
else echo "  skip qmllint not installed"; fi

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
mkdir -p "$T/repo"; cp -r "$ROOT/plugin" "$ROOT/manifest.json" "$ROOT/uninstall.sh" "$T/repo/"; bash "$T/repo/uninstall.sh" >/dev/null 2>&1
check "only the marker line removed when require line is missing" "[[ \$(cat $H) == \$'line1\nline-after-marker\nlast-line' ]]"

echo "== default sizing on different monitors"
mon() { # mon <w> <h> <scale> <transform> <reserved l,t,r,b>
  echo "[{\"name\":\"M\",\"x\":0,\"y\":0,\"width\":$1,\"height\":$2,\"scale\":$3,\"transform\":$4,\"reserved\":[$5],\"focused\":true,\"specialWorkspace\":{\"name\":\"\"}}]" > "$FAKE/monitors.json"; }
geo() { $OA geometry; }
setup_world; sed -i '/^width\|^height\|^top/d' "$XDG_CONFIG_HOME/omarchy-agent-switcher/agents.conf"
mon 1366 768 1 0 "0,26,0,0"; g=$(geo); echo "     1366x768:   $g"
check "1366x768: near-full width (>=1200), below bar" "[[ \$g =~ panel=([0-9]+)x([0-9]+)\+[0-9]+\+([0-9]+) ]] && (( BASH_REMATCH[1] >= 1200 && BASH_REMATCH[3] >= 26 ))"
check "1366x768: panel + strip fit in height" "[[ \$g =~ strip_top=([0-9]+) ]] && (( BASH_REMATCH[1] + 44 <= 768 ))"
mon 2560 1440 1.25 0 "0,26,0,0"; g=$(geo); echo "     2560x1440@1.25: $g"
check "2560x1440@1.25: logical 2048 wide, ~62% (1270)" "[[ \$g =~ area=2048x1126 && \$g =~ panel=12[0-9][0-9]x ]]"
mon 1920 1080 1 0 "0,0,0,0"; g=$(geo); echo "     1920x1080:  $g"
check "1920x1080: 62% = 1190, centered" "[[ \$g =~ panel=1190x[0-9]+\+365\+ ]]"
mon 3440 1440 1 0 "0,26,0,0"; g=$(geo); echo "     3440x1440:  $g"
check "3440x1440 ultrawide: narrower % (<=1600, <50%)" "[[ \$g =~ panel=([0-9]+)x ]] && (( BASH_REMATCH[1] <= 1600 && BASH_REMATCH[1] < 1720 ))"
mon 1080 1920 1 0 "0,26,0,0"; g=$(geo); echo "     1080x1920:  $g"
check "1080x1920 portrait: near-full width" "[[ \$g =~ panel=([0-9]+)x ]] && (( BASH_REMATCH[1] >= 1000 && BASH_REMATCH[1] <= 1056 ))"
mon 1920 1080 1 1 "0,0,0,0"; g=$(geo); echo "     1920x1080 rotated: $g"
check "rotation swaps width/height" "[[ \$g =~ area=1080x1920 ]]"
echo "max_width = 900px" >> "$XDG_CONFIG_HOME/omarchy-agent-switcher/agents.conf"; mon 3440 1440 1 0 "0,0,0,0"
check "max_width clamp" "[[ \$(geo) =~ panel=900x ]]"
sed -i '/^max_width/d' "$XDG_CONFIG_HOME/omarchy-agent-switcher/agents.conf"; echo "width = 1000px" >> "$XDG_CONFIG_HOME/omarchy-agent-switcher/agents.conf"
check "width in px" "[[ \$(geo) =~ panel=1000x ]]"
sed -i 's/^width = 1000px/width = 50%/' "$XDG_CONFIG_HOME/omarchy-agent-switcher/agents.conf"
check "width in %" "[[ \$(geo) =~ panel=1720x ]] || [[ \$(geo) =~ panel=1600x ]]"
setup_world; monitors 0 2; sed -i '/^width\|^height\|^top/d' "$XDG_CONFIG_HOME/omarchy-agent-switcher/agents.conf"
check "multi-monitor: uses focused monitor only" "[[ \$(geo) =~ monitor=eDP-1\ area=1280x720 ]]"

echo "== per-agent sizes"
setup_world; monitors 1; echo A > "$XDG_STATE_HOME/omarchy-agent-switcher/last"
clients "class.a:0xa1:243" "class.b:0xb1:1320" "class.c:0xc1:1320"
sed -i 's/"size":\[793,590\],"at":\[243/"size":[1000,500],"at":[243/' "$FAKE/clients.json"   # user resized A
: > "$FAKE/calls"; $OA show B
check "resized agent size saved per monitor" "[[ \$(cat $XDG_STATE_HOME/omarchy-agent-switcher/size/class.a@eDP-1) == '1000 500' ]]"
check "outgoing parks using its own (resized) width" "evals | grep -q \"address:0xa1', x = -1040\""
clients "class.a:0xa1:-1040" "class.b:0xb1:243" "class.c:0xc1:1320"; sed -i 's/"size":\[793,590\],"at":\[-1040/"size":[1000,500],"at":[-1040/' "$FAKE/clients.json"
: > "$FAKE/calls"; $OA show A
check "resized agent re-centred in slot ((1280-1000)/2=140)" "evals | grep -q \"address:0xa1', x = 140\""
check "resized agent keeps its size (no resize back)" "! evals | grep -q \"address:0xa1', x = 793\""
check "strip anchors under the active agent's height" "grep summon $FAKE/shell | tail -1 | grep -q '\"top\":553'"
$OA reset-size A >/dev/null; check "reset-size forgets it" "[[ ! -f $XDG_STATE_HOME/omarchy-agent-switcher/size/class.a@eDP-1 ]]"

echo "== shortcuts cheat sheet"
setup_world; monitors 0; clients "class.a:0xa1:243"
echo '[{"modmask":64,"key":"minus","submap":"","dispatcher":"resizeactive","arg":"-100 0","description":"Shrink window width"},{"modmask":64,"key":"mouse:273","submap":"","dispatcher":"resizewindow","arg":"","description":"Resize window with mouse"}]' > "$FAKE/binds.json"
echo "shortcuts_key = SUPER + SLASH" >> "$XDG_CONFIG_HOME/omarchy-agent-switcher/agents.conf"
$OA rules >/dev/null 2>&1
check "optional global shortcuts bind generated" "grep -q 'SUPER + SLASH\", \"Agent switcher shortcuts\"' $R"
$OA shortcuts; sleep 0.5; P=$(grep summon "$FAKE/shell" | tail -1)
check "shortcuts opens panel with sheet:true" "[[ \$P == *'\"sheet\":true'* ]] && evals | grep -q toggle_special"
check "sheet lists toggle key" "[[ \$P == *'Super+A'*'Open / close'* ]]"
check "sheet lists per-agent direct key" "[[ \$P == *'Super+Shift+A'*'A (open / switch / close)'* ]]"
check "sheet lists cycle keys" "[[ \$P == *'Previous agent'* && \$P == *'Next agent'* ]]"
check "sheet lists live resize binds (not mouse)" "[[ \$P == *'Super+minus'*'Shrink window width'* && \$P != *'with mouse'* ]]"
check "sheet lists reset-size + click actions" "[[ \$P == *'reset-size'* && \$P == *'Right-click tab'* ]]"
check "missing agent's key not in sheet" "[[ \$P != *'Super+Alt+M'* ]]"
monitors 1; echo "window=600x300 strip=400 sheet=true" > "$FAKE/metrics"; : > "$FAKE/shell"; : > "$FAKE/calls"
$OA shortcuts; sleep 0.5
check "shortcuts again closes an open sheet" "grep -qx 'agentswitcher shortcuts' $FAKE/shell && ! grep -q summon $FAKE/shell && ! evals | grep -q toggle_special"
echo "window=600x60 strip=400 sheet=false" > "$FAKE/metrics"; : > "$FAKE/shell"
$OA shortcuts; sleep 0.5
check "shortcuts with sheet closed reopens it" "grep summon $FAKE/shell | tail -1 | grep -q '\"sheet\":true' && ! grep -qx 'agentswitcher shortcuts' $FAKE/shell"
rm -f "$FAKE/metrics"
monitors 1; : > "$FAKE/calls"; $OA refocus
check "refocus hands the keyboard back to the active agent" "evals | grep -q \"focus({ window = 'address:0xa1' })\""
monitors 0; : > "$FAKE/calls"; $OA refocus
check "refocus does nothing while hidden" "! evals | grep -q focus"
check "plugin refocuses only on deliberate sheet close" "grep -q 'function hideSheet() .*run(\\[\"refocus\"\\])' $ROOT/plugin/Switcher.qml && grep -q 'root.sheet = false   // click-away' $ROOT/plugin/Switcher.qml"
monitors 1; : > "$FAKE/shell"; $OA show B >/dev/null 2>&1; sleep 0.5; check "normal updates close the sheet" "grep summon $FAKE/shell | tail -1 | grep -q '\"sheet\":false'"
echo "show_hint = false" >> "$XDG_CONFIG_HOME/omarchy-agent-switcher/agents.conf"; : > "$FAKE/shell"; $OA show A >/dev/null 2>&1; sleep 0.5
check "show_hint=false hides the hint line (hint:false)" "grep summon $FAKE/shell | tail -1 | grep -q '\"hint\":false'"

echo "== omarchy plugin add: first-load install (--from-shell)"
setup_world; rm "$HOME/.local/bin/omarchy-agents"; printf -- '-- user config\n' > "$XDG_CONFIG_HOME/hypr/hyprland.lua"
P=$XDG_CONFIG_HOME/omarchy/plugins/$(jq -r .id "$ROOT/manifest.json"); mkdir -p "$(dirname "$P")"; cp -r "$ROOT" "$P"   # what `omarchy plugin add` does
bash "$P/install.sh" --from-shell >"$T/inst" 2>&1; rc=$?; : "$rc"
check "from-shell install succeeds" "(( rc == 0 ))" || cat "$T/inst"
check "checkout left intact (not staged over itself)" "[[ -f $P/install.sh && -f $P/plugin/Switcher.qml && -d $P/tests ]]"
check "script + rules installed, include added" "[[ -x $HOME/.local/bin/omarchy-agents && -f $R ]] && grep -qx 'require(\"hypr.agent-switcher\")' $XDG_CONFIG_HOME/hypr/hyprland.lua"
check "marker written" "grep -q \"^\$(jq -r .version $ROOT/manifest.json) \" $XDG_STATE_HOME/omarchy-agent-switcher/installed"
check "no shell restart / enable from inside the shell" "! grep -q 'omarchy-restart-shell\|plugin enable' $FAKE/other 2>/dev/null"
: > "$FAKE/calls"; bash "$P/install.sh" --from-shell >/dev/null 2>&1
check "second load is a no-op" "! grep -q . $FAKE/calls"
setup_world; printf -- '-- user config\n' > "$XDG_CONFIG_HOME/hypr/hyprland.lua"; bash "$ROOT/install.sh" --yes --no-restart >/dev/null 2>&1
P=$XDG_CONFIG_HOME/omarchy/plugins/$(jq -r .id "$ROOT/manifest.json")
check "checkout install copies manifest + plugin/ only (no install.sh -> panel hook no-ops)" "[[ -f $P/manifest.json && -f $P/plugin/Switcher.qml && ! -e $P/install.sh ]]"
echo "== send to agent"
setup_world; monitors 1; echo "B" > "$XDG_STATE_HOME/omarchy-agent-switcher/last"
sed -i 's/^B | class.b | agent-b/B | class.b | omarchy-launch-tui --app-id=class.b agent-b/' "$XDG_CONFIG_HOME/omarchy-agent-switcher/agents.conf"
clients "class.a:0xa1:-833" "class.b:0xb1:243"
printf 'secret selected text' > "$FAKE/primary"; : > "$FAKE/wtype"
$OA send; sleep 1.2
check "send copies the primary selection" "grep -q 'selected text' $FAKE/copied"
check "send pastes with Ctrl+Shift+V into a TUI agent" "grep -q -- '-M ctrl -M shift v' $FAKE/wtype"
check "wl-copy never inherits the lock fd (it daemonizes)" "[[ ! -s $FAKE/wlcopy-fd9 ]]"
check "selected text is never logged" "! grep -q 'secret selected' $XDG_STATE_HOME/omarchy-agent-switcher/log"
echo A > "$XDG_STATE_HOME/omarchy-agent-switcher/last"; rm "$FAKE/primary"; printf 'clip' > "$FAKE/clipboard"; : > "$FAKE/wtype"
$OA send; sleep 1.2
check "falls back to clipboard; Ctrl+V for a GUI agent" "grep -q clip $FAKE/copied && grep -qx -- '-M ctrl v -m ctrl' $FAKE/wtype"
echo "send_key = SUPER + CTRL + S" >> "$XDG_CONFIG_HOME/omarchy-agent-switcher/agents.conf"
$OA rules >/dev/null 2>&1
check "send bind generated, no screenshot bind" "grep -q 'Send selection to agent' $R && ! grep -q 'Send screenshot' $R"
: > "$FAKE/shell"; $OA shortcuts; sleep 0.5
check "send key in cheat sheet, no screenshot entry" "grep summon $FAKE/shell | tail -1 | grep -q 'Send selected text' && ! grep summon $FAKE/shell | tail -1 | grep -q 'screenshot'"

echo "== send --text / send-files"
: > "$FAKE/wtype"; echo A > "$XDG_STATE_HOME/omarchy-agent-switcher/last"
$OA send --text "hello agent"; sleep 1.2
check "send --text pastes given text" "grep -q 'hello agent' $FAKE/copied"
echo piped | $OA send --text -; sleep 1.2
check "send --text - reads stdin" "grep -q piped $FAKE/copied"
mkdir -p "$T/files"; printf x > "$T/files/a b.txt"; printf x > "$T/files/c.txt"; printf PNG > "$T/files/pic.png"
$OA send-files A "$T/files/a b.txt" "$T/files/c.txt"; sleep 1.2
check "GUI: files as text/uri-list, percent-encoded" "grep -q 'type=text/uri-list' $FAKE/copied && grep -q 'file://.*/a%20b.txt' $FAKE/copied"
$OA send-files A "$T/files/pic.png"; sleep 1.2
check "GUI: single image as image data" "grep -q 'type=image/png' $FAKE/copied"
$OA send-files B "$T/files/a b.txt"; sleep 1.2
check "TUI: quoted path pasted" "grep -q 'type=text' $FAKE/copied && grep -qF 'a\\ b.txt' $FAKE/copied"
$OA send-files Nope "$T/files/c.txt" 2>/dev/null; check "send-files unknown agent fails" "(( \$? != 0 ))"

echo "== stuck lock recovery"
setup_world; monitors 1; clients "class.a:0xa1:243"; : > "$FAKE/shell"
( exec 7>"$XDG_STATE_HOME/omarchy-agent-switcher/lock"; flock 7; sleep 6 ) & hold=$!; sleep 0.3
$OA toggle >/dev/null 2>&1
check "toggle force-closes panel + strip when the lock is stuck" "grep -q 'agentswitcher hide' $FAKE/shell && evals | grep -q toggle_special"
check "stuck lock is logged with its holder" "grep -q 'lock timeout' $XDG_STATE_HOME/omarchy-agent-switcher/log"
kill $hold 2>/dev/null; wait $hold 2>/dev/null
setup_world; : > "$FAKE/shell"; $OA rules >/dev/null 2>"$T/err"
check "unset optional keys give no warnings" "! grep -q 'invalid' $T/err"
check "click-through while open (click-to-focus only, restored on close)" "grep -q 'special_fallthrough = true' $R && grep -q 'follow_mouse = 0' $R && grep -q 'float_switch_override_focus = 0' $R && grep -q 'float_switch_override_focus = s.fs' $R"
echo "click_through = false" >> "$XDG_CONFIG_HOME/omarchy-agent-switcher/agents.conf"; $OA rules >/dev/null 2>&1
check "click_through = false disables it" "grep -q 'agent_switcher.click_through = false' $R"

echo "== usage meter"
setup_world; monitors 1; clients "class.a:0xa1:243"
sed -i 's/^A | class.a | agent-a | SUPER + SHIFT + A |/A | class.a | agent-a | SUPER + SHIFT + A | | grok/; s/^C | class.c | agent-c | |/C | class.c | agent-c | | | claude/' "$XDG_CONFIG_HOME/omarchy-agent-switcher/agents.conf"
U=$HOME/.local/state/omarchy/agents/usage; mkdir -p "$U"
echo '{"id":"grok","ready":true,"token":"sk-SECRET","limits":[{"title":"Weekly","percent":0.42},{"title":"Daily","percent":0.95}]}' > "$U/grok.json"
echo '{"id":"claude","limits":[{"title":"5h","percent":0.3}]}' > "$U/claude.json"
J=$($OA usage --print)
check "highest limit per provider" "[[ \$(jq -r .grok.p <<<\"\$J\") == 0.95 && \$(jq -r .grok.t <<<\"\$J\") == 'Daily 95%' ]]"
check "tokens never surface" "[[ \$J != *SECRET* ]]"
: > "$FAKE/shell"; $OA show A >/dev/null 2>&1; sleep 0.5; P=$(grep summon "$FAKE/shell" | tail -1)
check "payload carries per-tab usage" "[[ \$P == *'\"name\":\"A\"'*'\"usage\":0.95'* && \$P == *'\"name\":\"C\"'*'\"usage\":0.3'* ]]"
check "agent without provider record = -1" "[[ \$P == *'\"name\":\"B\"'*'\"usage\":-1'* ]]"
check "thresholds + display sent" "[[ \$P == *'\"usageDisplay\":\"fill\"'*'\"usageWarn\":0.7'* ]]"
mkdir -p "$XDG_DATA_HOME/omarchy-agent-switcher/collectors"; printf '#!/bin/sh\necho ran >> "$FAKE/collect"; echo TOKEN-LEAK\n' > "$XDG_DATA_HOME/omarchy-agent-switcher/collectors/refresh"; chmod +x "$XDG_DATA_HOME/omarchy-agent-switcher/collectors/refresh"
rm -f "$XDG_STATE_HOME/omarchy-agent-switcher/usage.stamp"; $OA usage; sleep 0.5; $OA usage; sleep 0.5
check "collectors run lazily, once per refresh window" "[[ \$(wc -l < $FAKE/collect) == 1 ]]"
$OA usage --force; sleep 0.5; check "--force refreshes" "[[ \$(wc -l < $FAKE/collect) == 2 ]]"
check "collector output never logged" "! grep -q TOKEN-LEAK $XDG_STATE_HOME/omarchy-agent-switcher/log"
echo "usage_display = off" >> "$XDG_CONFIG_HOME/omarchy-agent-switcher/agents.conf"
check "usage_display=off -> no usage" "[[ \$($OA usage --print) == '{}' ]]"

echo "== usage freshness"
setup_world; monitors 0; clients "class.a:0xa1:243"
sed -i 's/^A | class.a | agent-a | SUPER + SHIFT + A |$/A | class.a | agent-a | SUPER + SHIFT + A | | grok-bot/' "$XDG_CONFIG_HOME/omarchy-agent-switcher/agents.conf"
U=$HOME/.local/state/omarchy/agents/usage; mkdir -p "$U"
echo '{"id":"grok-bot","usageStatusText":"Sign-in expired","limits":[{"title":"Weekly","percent":0.7655}]}' > "$U/grok-bot.json"
J=$($OA usage --print 2>/dev/null)
check "stale record says so (last known value)" "[[ \$J == *'Weekly 77%'*'Sign-in expired (last known value)'* ]]"
: > "$FAKE/shell"; $OA shortcuts >/dev/null 2>&1; sleep 0.5
check "cheat sheet has the usage disclaimer" "grep summon $FAKE/shell | tail -1 | grep -q 'can lag or differ slightly'"
check "README has the usage disclaimer" "grep -q 'can lag or differ slightly' $ROOT/README.md"
check "hover text has the disclaimer" "grep -q 'can lag or differ slightly from the provider' $ROOT/plugin/Switcher.qml"
mkdir -p "$XDG_DATA_HOME/omarchy-agent-switcher/collectors"; printf '#!/bin/sh\necho ran >> "$FAKE/collect"\n' > "$XDG_DATA_HOME/omarchy-agent-switcher/collectors/refresh"; chmod +x "$XDG_DATA_HOME/omarchy-agent-switcher/collectors/refresh"
touch -d '-3 minutes' "$XDG_STATE_HOME/omarchy-agent-switcher/usage.stamp"; rm -f "$FAKE/collect"
monitors 0; $OA show A >/dev/null 2>&1; sleep 1
check "open refreshes usage older than 2 min (usage_refresh_min 10)" "[[ -s $FAKE/collect ]]"
check "sheet click-away catcher exists under the strip" "grep -q 'omarchy-agent-switcher-sheet' $ROOT/plugin/Switcher.qml"

echo "== open_on"
for case in "last:B:0xb1" "first:B:0xa1" "C:A:0xc1" "class.c:A:0xc1" "Nope:B:0xa1"; do
  IFS=: read -r oo lst want <<<"$case"
  setup_world; clients "class.a:0xa1:-833" "class.b:0xb1:1320" "class.c:0xc1:1320"; echo "$lst" > "$XDG_STATE_HOME/omarchy-agent-switcher/last"
  echo "open_on = $oo" >> "$XDG_CONFIG_HOME/omarchy-agent-switcher/agents.conf"; $OA toggle
  check "open_on=$oo (last=$lst) opens $want" "evals | grep -q \"focus({ window = 'address:$want' })\""
done
check "missing open_on agent logged" "grep -q \"open_on 'Nope'\" $XDG_STATE_HOME/omarchy-agent-switcher/log"
monitors 1; : > "$FAKE/calls"; $OA direct class.b >/dev/null 2>&1
check "direct keys unaffected by open_on" "evals | grep -q \"address:0xb1', x = 243\""
setup_world; mkdir -p "$XDG_DATA_HOME/omarchy-agent-switcher"; cp "$ROOT/share/agents.conf.default" "$XDG_DATA_HOME/omarchy-agent-switcher/"
printf 'codex | A | tui | bin:agent-a | class.a | | \nclaude | B | tui | bin:agent-b | class.b | | \n' > "$XDG_DATA_HOME/omarchy-agent-switcher/registry.conf"
script -qc "printf 'y\ny\n\nB\n' | OMARCHY_AGENTS_NO_GUM=1 $OA setup" /dev/null >/dev/null 2>&1 || printf 'y\ny\n\nB\n' | OMARCHY_AGENTS_NO_GUM=1 $OA setup >/dev/null 2>&1
check "setup retains the opening default" "grep -qE '^open_on = (B|last)' $XDG_CONFIG_HOME/omarchy-agent-switcher/agents.conf && [[ \$(grep -c '^open_on' $XDG_CONFIG_HOME/omarchy-agent-switcher/agents.conf) == 1 ]]"

setup_world; rm "$XDG_CONFIG_HOME/omarchy-agent-switcher/agents.conf"; mkdir -p "$XDG_DATA_HOME/omarchy-agent-switcher"; cp "$ROOT/share/agents.conf.default" "$XDG_DATA_HOME/omarchy-agent-switcher/"
printf 'a | A | tui | bin:agent-a | class.a | | \ng | Grok Bot | tui | bin:agent-b | grok-bot | | \nc | C | tui | bin:agent-c | class.c | | \n' > "$XDG_DATA_HOME/omarchy-agent-switcher/registry.conf"
$OA setup --default >/dev/null 2>&1; C=$XDG_CONFIG_HOME/omarchy-agent-switcher/agents.conf
check "first-load default enables only Grok Bot" "[[ \$(grep -cE '^[^#=]+[|]' $C) == 1 ]] && grep -q '^Grok Bot' $C"
check "other detected agents listed commented out" "grep -q '^# A ' $C && grep -q '^# C ' $C"
printf 'a | A | tui | bin:agent-a | class.a | | \nc | C | tui | bin:agent-c | class.c | | \n' > "$XDG_DATA_HOME/omarchy-agent-switcher/registry.conf"; rm "$C"
$OA setup --default >/dev/null 2>&1
check "no Grok Bot: first detected only" "[[ \$(grep -cE '^[^#=]+[|]' $C) == 1 ]] && grep -q '^A ' $C"

echo "== install / uninstall with --with-nautilus (stubs)"
setup_world; rm "$HOME/.local/bin/omarchy-agents"; printf -- '-- user config\n' > "$XDG_CONFIG_HOME/hypr/hyprland.lua"
bash "$ROOT/install.sh" --yes --with-nautilus --no-restart >"$T/inst" 2>&1; rc=$?; : "$rc"
check "install succeeds" "(( rc == 0 ))" || cat "$T/inst"
check "require line added" "grep -qx 'require(\"hypr.agent-switcher\")' $XDG_CONFIG_HOME/hypr/hyprland.lua"
check "nautilus extension installed" "[[ -f $XDG_DATA_HOME/nautilus-python/extensions/omarchy-agent-switcher.py ]]"
check "send-files desktop entry installed" "grep -q 'send-files - %F' $XDG_DATA_HOME/applications/omarchy-agents-send.desktop"
check "collectors installed" "[[ -x $XDG_DATA_HOME/omarchy-agent-switcher/collectors/refresh ]]"
bash "$ROOT/install.sh" --yes --no-restart >/dev/null 2>&1
check "re-install idempotent (one require line)" "[[ \$(grep -c 'agent-switcher' $XDG_CONFIG_HOME/hypr/hyprland.lua) == 2 ]]"
bash "$ROOT/uninstall.sh" >/dev/null 2>&1
check "uninstall restores hyprland.lua" "[[ \$(cat $XDG_CONFIG_HOME/hypr/hyprland.lua) == '-- user config' ]]"
check "uninstall removes nautilus ext + desktop entry" "[[ ! -e $XDG_DATA_HOME/nautilus-python/extensions/omarchy-agent-switcher.py && ! -e $XDG_DATA_HOME/applications/omarchy-agents-send.desktop ]]"

echo "== strip allow-list"
setup_world
check "no only line shows every installed agent" "[[ \$($OA list) == \$'A\nB\nC' ]]"
$OA disable B >/dev/null
C=$XDG_CONFIG_HOME/omarchy-agent-switcher/agents.conf
check "disable keeps the others, in order" "grep -qx 'only = A, C' $C"
check "list hides the disabled agent" "[[ \$($OA list) == \$'A\nC' ]]"
check "hidden agent is left out of the window rule" "! grep -q 'class\\.b' $R"
$OA enable class.b >/dev/null
check "enable matches the window class, ignoring case" "grep -qx 'only = A, C, B' $C"
printf '# D | class.d | agent-a | |\n' >> "$C"
$OA enable D >/dev/null
check "enable uncomments a configured agent" "grep -q '^D |' $C && grep -qx 'only = A, C, B, D' $C"
$OA disable A C B D >/dev/null
check "disabling the last agent leaves an empty only line" "grep -qx 'only = ' $C"
check "empty only shows nothing" "[[ -z \$($OA list) ]]"
check "unknown disable fails" "! $OA disable Nope"
sed -i 's/^only = .*/only = C, A/' "$C"
check "only order is the tab order" "[[ \$($OA list) == \$'C\nA' ]]"

echo "== disabling an open agent"
setup_world; monitors 1; clients "class.a:0xa1:243" "class.b:0xb1:243"; echo B > "$XDG_STATE_HOME/omarchy-agent-switcher/last"
$OA disable B >/dev/null
check "disabled open agent closes" "evals | grep -q \"window.close({ window = 'address:0xb1' })\""
check "other open agents stay running" "! evals | grep -q \"window.close({ window = 'address:0xa1' })\""
check "membership change hides stale strip" "grep -q 'agentswitcher hide' $FAKE/shell"
: > "$FAKE/calls"; clients "class.b:0xb1:243"; $OA enable B >/dev/null
check "enable never closes an agent" "! evals | grep -q \"window.close\""
$OA disable B >/dev/null
clients "class.b:0xb1:243" "class.c:0xc1:243"
jq 'map(.workspace.name = "1")' "$FAKE/clients.json" > "$FAKE/normal.json"; mv "$FAKE/normal.json" "$FAKE/clients.json"
: > "$FAKE/calls"; $OA disable B >/dev/null
check "already-disabled detached window can be closed" "evals | grep -q \"window.close({ window = 'address:0xb1' })\""
check "normal workspace's other agents stay open" "! evals | grep -q \"window.close({ window = 'address:0xc1' })\""

echo "== interactive setup selections"
setup_registry() {
  for native in codex claude; do printf '#!/bin/sh\nexit 0\n' > "$T/agents/$native"; chmod +x "$T/agents/$native"; done
  mkdir -p "$XDG_DATA_HOME/omarchy-agent-switcher"
  cp "$ROOT/share/agents.conf.default" "$XDG_DATA_HOME/omarchy-agent-switcher/"
  printf 'codex | A | tui | bin:agent-a | class.a | | \nclaude | B | tui | bin:agent-b | class.b | | \n' > "$XDG_DATA_HOME/omarchy-agent-switcher/registry.conf"
}
interactive_setup() {
  printf '%s' "$1" | OMARCHY_AGENTS_NO_GUM=1 script -qec "$OA setup" /dev/null > "$T/setup.out" 2>&1
}
setup_world; setup_registry; C=$XDG_CONFIG_HOME/omarchy-agent-switcher/agents.conf; rm "$C"
interactive_setup $'\n\n\n\n'
check "fresh plain setup Enter selects all" "[[ \$($OA list) == \$'A\nB' ]] && grep -q '\\[Y/n\\]' $T/setup.out"
setup_world; setup_registry; C=$XDG_CONFIG_HOME/omarchy-agent-switcher/agents.conf; echo 'only = B' >> "$C"
interactive_setup $'\n\n\n'
check "existing plain setup Enter preserves selection" "[[ \$($OA list) == B ]]"
setup_world; setup_registry; C=$XDG_CONFIG_HOME/omarchy-agent-switcher/agents.conf; echo 'only = ' >> "$C"; cp "$C" "$T/before"
interactive_setup $'\n\n' || true
check "empty selection does not enable agents or overwrite config" "cmp -s $C $T/before && [[ -z \$($OA list) ]]"
setup_world; setup_registry; C=$XDG_CONFIG_HOME/omarchy-agent-switcher/agents.conf; rm "$C"
cat > "$T/agents/gum" <<'GUM'
#!/usr/bin/env bash
if [[ $1 == input ]]; then exit 0; fi
if [[ " $* " == *" --no-limit "* ]]; then
  printf '%s\n' "$*" >> "$FAKE/gum"
  while (( $# )); do
    if [[ $1 == --selected ]]; then printf '%s\n' "${2//,/$'\n'}"; exit 0; fi
    shift
  done
else echo last; fi
GUM
chmod +x "$T/agents/gum"
printf '\n' | script -qec "$OA setup" /dev/null > "$T/setup.out" 2>&1
check "fresh gum setup preselects all" "grep -q -- '--selected A,B' $FAKE/gum && [[ \$($OA list) == \$'A\nB' ]]"
echo 'only = B' >> "$C"; : > "$FAKE/gum"
printf '\n' | script -qec "$OA setup" /dev/null > "$T/setup.out" 2>&1
check "existing gum setup preselects current list" "grep -q -- '--selected B' $FAKE/gum && [[ \$($OA list) == B ]]"
printf 'A | class.a | agent-a | |\n' >> "$C"
echo 'only = B, A' >> "$C"
printf '\n' | script -qec "$OA setup" /dev/null > "$T/setup.out" 2>&1
check "Setup preserves existing tab order" "[[ \$($OA list) == \$'B\nA' ]]"
echo 'only = ' >> "$C"; cp "$C" "$T/before"; : > "$FAKE/gum"
printf '\n' | script -qec "$OA setup" /dev/null > "$T/setup.out" 2>&1 || true
check "empty gum selection stays empty" "! grep -q -- '--selected' $FAKE/gum && cmp -s $C $T/before"
setup_world; echo 'only = cLaSs.C, a' >> "$XDG_CONFIG_HOME/omarchy-agent-switcher/agents.conf"
check "mixed-case class and name preserve requested order" "[[ \$($OA list) == \$'C\nA' ]]"
check "interactive sign-in regression suite" "python3 \"$ROOT/tests/setup-login.py\""

check "strip configuration regression suite" "python3 \"$ROOT/tests/strip-config.py\""

check "theme roles and usage-fill contrast" "node \"$ROOT/tests/theme-contrast.js\""

check "Grok Bot session-check regression suite" "python3 \"$ROOT/tests/grok-login.py\""

echo
echo "passed: $PASS  failed: $FAILN"
(( FAILN == 0 ))
