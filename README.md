# omarchy-agent-switcher

One hotkey for all your AI agents on [Omarchy](https://omarchy.org). Press **Super+A** and a
drop-down panel slides up with your agent. A small tab strip under it switches between Grok Bot,
Grok Build, Claude Code, Codex, or any other GUI or terminal agent, sliding sideways in tab order.

<!-- Demo GIF coming soon: docs/demo.gif -->

## Features
- **One shared drop-down.** Every agent lives in one Hyprland special workspace (`special:agents`). Opening and closing slide up from the bottom.
- **Tab strip.** It's a native Omarchy shell (quickshell) plugin with icons, theme colours, rounded corners and a hint line under the tabs; `?` on the strip or `shortcuts_key` (e.g. Super+/) opens a cheat sheet of every switcher key, built from your config. Click a tab, scroll over the strip, or click it and use ← → / Tab / 1-9 / Esc. Right-click a tab for Restart / Close; middle-click closes. Tabs show whether an agent is running, starting (…) or not started yet.
- **Directional switching.** Picking a tab to the right brings that agent in from the right while the old one leaves left, and the reverse for tabs on the left. The slide is ~250 ms and only applies to switches; your other window animations aren't touched.
- **Cycle hotkeys** (default Super+Alt+← / →). They are only bound while the panel is open, so the rest of the time Omarchy's own binds on those keys work as normal.
- **Per-agent shortcuts** (e.g. Super+Shift+A opens Grok Bot directly).
- **Remembers** the last agent you used. Your mouse cursor is never moved, and only the visible agent dims the desktop.
- **Agent auto-detection.** Install finds the agents you have and lets you pick and order them. Agents that aren't installed are skipped.
- **Portable.** No hard-coded paths. Colours come from your active Omarchy theme, and the panel follows whichever monitor is focused, at any resolution or scale.

- **Send to agent.** `send_key` pastes your selected text into the agent; right-click files in Nautilus → *Send to agent*.
- **Usage meter.** Each tab fills left to right with that agent's plan usage (accent → amber → red), percent on hover.
- **Status.** A dot on each tab, and a bar icon, shows working, a question waiting on you, an error, or a finished reply. A short sound can play for those, except while that agent's window is the one you are looking at.

## Install
Requires Omarchy 3.x with the Hyprland **Lua** config (Hyprland 0.55+, tested on 0.56.2) and the Omarchy shell, plus `jq`, `flock` (util-linux) and optionally `gum`.

```sh
omarchy plugin add https://github.com/PaytonORogers/omarchy-agent-switcher --enable --yes
```
On first load the panel runs the bundled `install.sh --from-shell` once. That enables one agent (Grok Bot if it is installed, otherwise the first one found) and lists the rest commented out. Run `omarchy-agents setup` to pick and order them.

Or from a checkout (interactive agent picker):
```sh
git clone https://github.com/PaytonORogers/omarchy-agent-switcher.git
cd omarchy-agent-switcher
./install.sh          # interactive: pick + order detected agents (uses gum if present)
./install.sh --yes    # non-interactive: enable every detected agent
./install.sh --no-restart   # skip the shell restart (strip loads next time the shell restarts)
./install.sh --with-nautilus  # optional: "Send to agent" in the Nautilus right-click menu (needs python-nautilus)
```
`install.sh` can be re-run safely. It:
- copies `omarchy-agents` to `~/.local/bin`
- copies the registry and icons to `~/.local/share/omarchy-agent-switcher`
- copies the plugin to `~/.config/omarchy/plugins/io.github.paytonorogers.agent-switcher`
- writes `~/.config/hypr/agent-switcher.lua` (window rules and binds)
- adds one `require("hypr.agent-switcher")` line to `hyprland.lua` (backed up to `hyprland.lua.bak-agent-switcher`)
- adds a line to `~/.config/omarchy/hooks/theme-set` so border colours follow theme changes
- enables the plugin and restarts the shell

It checks dependencies first and swaps files in atomically, so a failed install leaves the old version working.

Uninstall: `./uninstall.sh` reverts all of that and keeps your config. `./uninstall.sh --purge` removes the config too.

## Choosing agents
Installed does not mean shown. The strip is the `only` list when that line is set, otherwise every agent line in the config. A first `omarchy plugin add` still enables one agent and leaves the rest commented out.

```sh
omarchy-agents agents                 # what is on and what is installed but hidden
omarchy-agents disable Cursor Codex   # hide these; the rest stay, in the same order
omarchy-agents enable "Claude Code"   # add one back
omarchy-agents setup                  # checklist of everything detected (space toggles)
```

`only = Grok Bot, Claude Code` in `agents.conf` is the same list, in tab order. `setup` rewrites the agent lines from what you check and clears `only`. `setup --yes` still takes every detected agent.

Detection uses
`share/registry.conf`, one line per known agent:

```
id | name | gui|tui | bin:<cmd> / desktop:<file.desktop> / flatpak:<app-id> | window class | launch | icon
```
- **Desktop apps:** Grok Bot, Claude, ChatGPT, Cursor, Hermes.
- **Terminal agents:** grok, claude, codex, gemini, opencode, aider, cursor-agent, copilot, crush, goose, amp, qwen, hermes. They are found on PATH, including mise / npm / bun / cargo / `~/.local/bin` shims, and launched with `omarchy-launch-tui --app-id=<unique class>`.

PRs adding agents are welcome. It's one line.

## Config: `~/.config/omarchy-agent-switcher/agents.conf`
```ini
toggle_key = SUPER + A
open_on = last                      # toggle opens: last | first | <agent name or class> (missing agent -> first)
prev_key   = SUPER + ALT + LEFT     # only bound while the panel is open
next_key   = SUPER + ALT + RIGHT
accent     =                        # empty = theme accent; e.g. #9B7BD4
accent_inactive =                   # empty = theme selection colour
width = auto                        # auto | 0.62 | 62% | 1200px  (auto: ~62% on 16:9, ~88% on small, ~45% ultrawide, ~94% portrait)
height = auto                       # auto fills the screen below the bar, leaving room for the strip
top = auto                          # gap above the panel: auto | fraction | px
max_width = 1600                    # logical px clamp for width (min_width = 640)
slide_ms = 250                      # agent-switch slide; 0 = no slide
override_slide_animation = true     # false = keep your own windowsMove animation
opacity = 0.82 0.75
rounding = 14
dim = true
show_hint = true                    # hint line under the tabs
click_through = true                # while open, clicks on outside windows focus them (closes the panel)
shortcuts_key =                     # optional global bind for the cheat sheet, e.g. SUPER + SLASH
start_hidden = grok-bot             # optional: launch this class hidden at login

# name | window class | launch command | direct key (optional) | icon (optional)
Grok Bot   | grok-bot              | uwsm-app -- grok-bot | SUPER + SHIFT + A | grok-bot
Grok Build | org.omarchy.grokbuild | omarchy-launch-tui --app-id=org.omarchy.grokbuild grok | SUPER + ALT + A | grok
```
One setting per line. Window classes may only contain letters, digits, `.`, `_` and `-`; bad lines are skipped and reported by `rules` and `doctor`.

**Note:** `slide_ms` sets Hyprland's global `windowsMove` animation, so it affects every window move, not just agents. Set `override_slide_animation = false` to keep yours.

After editing, run `omarchy-agents rules` to regenerate the Hyprland include and reload.

**Icons** can be a bundled name (`grok`, `grok-bot`, `claude`, `codex`, `hermes`), an icon-theme name, or an absolute path. Cursor's theme name is `co.anysphere.cursor` (the `Icon=` in its desktop file), not `cursor`. A name that is neither bundled nor installed in the icon theme is replaced by that desktop file's icon when the icon is installed.

**Terminal agents:** use an absolute path or `$HOME/...` for the binary. Apps launched through uwsm don't see your shell's PATH.

## Send to agent
| How | What happens |
|---|---|
| `send_key` (e.g. `SUPER + CTRL + S`, unbound by default) / `omarchy-agents send` | Pastes the highlighted text (primary selection, else clipboard) into the active agent. Works in any app, including browsers. |
| Nautilus right-click → *Send to agent* → *Send to Claude Code* (`--with-nautilus`) | `omarchy-agents send-files <agent> <paths…>` |
| Other file managers: *Open With → Send to agent* | `omarchy-agents send-files - <paths…>` (active agent) |
| `omarchy-agents send --text "…"` or `… | omarchy-agents send --text -` | Scripts |

GUI agents get files as a `text/uri-list` (a single image as image data) and a Ctrl+V; terminal agents get shell-quoted paths and Ctrl+Shift+V.
The panel opens on the agent first. Keystrokes use `wtype`, else `ydotool`, else Hyprland's `sendshortcut`. Note: this replaces your clipboard.
Selected text is never written to the log.

## Usage meter
Usage comes from the same records as Omarchy's agent usage (`~/.local/state/omarchy/agents/usage/<provider>.json`). Omarchy's own
`omarchy-agent-usage-update` covers Claude/Codex, and the bundled collectors from auxxed's agents plugin cover Grok, Grok Bot and Hermes.
Each tab shows the highest limit for its provider. The provider is guessed from the class/command (grok, grok-bot, claude, codex, hermes, …);
set it explicitly as an optional 6th field: `Name | class | launch | key | icon | provider`.
```ini
strip_edge = auto           # auto (same edge as the Omarchy bar; left/right -> bottom) | top | bottom
usage_display = fill        # fill | percent | off
usage_warn = 0.70           # amber from here
usage_crit = 0.90           # red from here
usage_refresh_min = 10      # collectors run on open, at most this often, and on this interval while open
sound = default             # default | chime | off
```
`omarchy-agents usage --force` refreshes now. Collector output is never logged.

`sound` plays a short sound when an agent needs approval, hits an error, or finishes (not when it starts working). `default` uses the freedesktop sound theme (`message-new-instant` for approval and error, `complete` for done) via `pw-play` (falling back to `paplay`, then `canberra-gtk-play`); `chime` uses the bundled original tones in `share/sounds` (CC0, generated by `tools/gen-chimes.py`), distinct for approval, done and error. Nothing plays while Omarchy's do-not-disturb is on, when that agent's window is focused and on screen, or more than once per 3 seconds.

Usage numbers refresh periodically (on open if older than 2 minutes, and every `usage_refresh_min` while open), so they can lag or differ slightly from the provider's own number. If a collector can't sign in (e.g. "Sign-in expired"), the tab keeps the last known value and the hover text says so.

## Sizing
Sizes are computed from the focused monitor's logical size (scale and rotation applied) minus reserved space such as the top bar.
**Resize any agent with Omarchy's normal resize keys** while it's showing; the switcher remembers that agent's size per monitor,
keeps it centred, and anchors the strip under it. `omarchy-agents reset-size [name|all]` forgets saved sizes.
`omarchy-agents geometry` prints the computed layout.

## Keybinds (defaults)
| Keys | Action |
|---|---|
| Super+A | open / close the drop-down (last agent) |
| Super+Alt+← / → | previous / next agent (only while open) |
| per-agent `direct key` | open that agent, switch to it, or close it if it's already showing |
| scroll on strip, or click it then ← → Tab 1-9 Esc | switch / close |
| `?` on the focused strip, `shortcuts_key`, or `omarchy-agents shortcuts` | cheat sheet (Esc or click away closes) |

The Super+Alt+←/→ defaults shadow Omarchy's "move window to group" only while the panel is open, and
are restored on close (only if the Omarchy default was really there). If you pick keys that already do something else, `omarchy-agents rules` warns you.

## CLI
`omarchy-agents toggle | show <name> | next | prev | hide | direct <class> | close <name> | restart <name> | reset-size [name|all] | shortcuts | geometry | send [--text T] | send-files <agent|-> <path…> | usage [--force|--print] | agents | enable <name>... | disable <name>... | list | setup [--yes] | rules [--reload] | doctor | hint on|off|toggle | version`

`omarchy-agents hint off` hides the hint line right away and saves `show_hint = false` in your config. Use `hint on` or `hint toggle` to change it back.

## Troubleshooting
- **No strip:** run `omarchy-agents doctor`, then `omarchy plugin enable io.github.paytonorogers.agent-switcher && omarchy-restart-shell`. Editing the QML may need a full shell restart; hot reload can fail.
- **Agent not floating or in the wrong place:** check its real class with `hyprctl clients`, fix it in `agents.conf`, then run `omarchy-agents rules`.
- **Agent tab shows a plain terminal or takes a while the first time:** that's the agent's own first run. For example, Omarchy's `~/.local/bin/claude` installs Claude Code with mise on first launch, which is a one-time download of ~200 MB, and Codex shows a sign-in screen until you log in. Switching never waits for a starting agent: its window pops into the panel when it's ready, and you get a "Starting …" notification.
- **Launch lines:** `$HOME` and `~` are expanded, and bare program names are resolved against PATH plus mise shims, `~/.local/bin`, npm, bun and cargo before launching. Apps started through uwsm/systemd don't see your shell's PATH.
- **Pre-launch:** `start_hidden = grok-bot, org.omarchy.agent.claude` takes a comma list of classes to start hidden at login, so the first open is instant.
- **Too many tabs:** `omarchy-agents disable NAME`, or edit `only =` in `agents.conf`. Installed agents you leave out stay off the strip.
- **Tab missing:** its program wasn't found. `doctor` lists skipped agents.
- **Agent didn't start:** you get a notification after 20 s. Logs are in `~/.local/state/omarchy-agent-switcher/log` (`doctor` shows the tail); `OMARCHY_AGENTS_DEBUG=1 omarchy-agents show <name>` prints them live.
- **Config errors:** `hyprctl configerrors`. The generated file is `~/.config/hypr/agent-switcher.lua`.
- **Multi-monitor:** the panel opens on the focused monitor. Inactive agents wait outside the whole desktop, so they never peek onto a neighbouring monitor. Please report any issues.

## Credits
- Built for Omarchy by DHH and contributors, on Hyprland and quickshell.
- Usage collectors (`share/collectors/`) and agent icons come from [auxxed's Omarchy agents plugin](https://github.com/auxxed) (MIT). See THIRD_PARTY.md.
- `omarchy plugin add` support: [Theron Rogers](https://github.com/TheronRogers) (PR #1).
- Author: Payton Rogers. MIT licensed, see LICENSE.

## Updating
```sh
cd omarchy-agent-switcher && git pull && ./install.sh   # keeps your agents.conf
```
See [CHANGELOG.md](CHANGELOG.md). `omarchy-agents version` prints the installed version.

## Development
`tests/run.sh` runs the unit tests against a fake `hyprctl`/`omarchy-shell` (no Hyprland needed). CI also runs shellcheck and a QML syntax check.
