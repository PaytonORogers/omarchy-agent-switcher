# omarchy-agent-switcher

One hotkey for all your AI agents on [Omarchy](https://omarchy.org). Press **Super+A** and a
drop-down panel slides up with your agent. A small tab strip under it switches between Grok Bot,
Grok Build, Claude Code, Codex, or any other GUI or terminal agent, sliding sideways in tab order.

![demo](docs/demo.gif) <!-- TODO: record docs/demo.gif -->

## Features
- **One shared drop-down.** Every agent lives in one Hyprland special workspace (`special:agents`). Opening and closing slide up from the bottom.
- **Tab strip.** It's a native Omarchy shell (quickshell) plugin with icons, theme colours, rounded corners and a small keyboard hint. Click a tab, scroll over the strip, or click it and use ← → / Tab / 1-9 / Esc.
- **Directional switching.** Picking a tab to the right brings that agent in from the right while the old one leaves left, and the reverse for tabs on the left. The slide is ~250 ms and only applies to switches; your other window animations aren't touched.
- **Cycle hotkeys** (default Super+Alt+← / →). They are only bound while the panel is open, so the rest of the time Omarchy's own binds on those keys work as normal.
- **Per-agent shortcuts** (e.g. Super+Shift+A opens Grok Bot directly).
- **Remembers** the last agent you used. Your mouse cursor is never moved, and only the visible agent dims the desktop.
- **Agent auto-detection.** Install finds the agents you have and lets you pick and order them. Agents that aren't installed are skipped.
- **Portable.** No hard-coded paths. Colours come from your active Omarchy theme, and the panel follows whichever monitor is focused, at any resolution or scale.

## Install
Requires Omarchy (Hyprland Lua config + the Omarchy shell), `jq`, and optionally `gum`.

`omarchy plugin add` clones this repo and enables the shell plugin. Omarchy does not run install scripts, so the panel finishes setup the first time it loads:

```sh
omarchy plugin add https://github.com/PaytonORogers/omarchy-agent-switcher --enable --yes
```

That first load is not just a shell plugin. It writes `omarchy-agents`, the icons, and `~/.config/hypr/agent-switcher.lua`, appends a `require` to `hyprland.lua`, reloads Hyprland, and turns on every agent it detects. Those agents get their direct keybinds. There is no picker on this path, and the shell is not restarted (a clone install does restart it). Run `omarchy-agents setup` afterwards to change the list.

The panel stays loaded, so every later shell start runs `install.sh --from-shell`. That exits immediately when the launcher, registry, config, Hyprland include, and generated rules are already in place and the launcher and registry are not older than the checkout. An icon-only change is copied on the next run that also updates `omarchy-agents` or `registry.conf`.

`omarchy plugin remove` deletes the checkout only. The launcher, icons, `agents.conf`, and Hyprland include stay until you run `uninstall.sh` from `~/.config/omarchy/plugins/io.github.paytonorogers.agent-switcher`. Until then, Super+A can still be bound with the tab strip gone.

To pick and order agents while installing, clone and run the installer instead:

```sh
git clone https://github.com/PaytonORogers/omarchy-agent-switcher.git
cd omarchy-agent-switcher
./install.sh          # interactive: pick + order detected agents (uses gum if present)
./install.sh --yes    # non-interactive: enable every detected agent
```
`install.sh` can be re-run safely. It:
- copies `omarchy-agents` to `~/.local/bin`
- copies the registry and icons to `~/.local/share/omarchy-agent-switcher`
- copies `manifest.json` and `plugin/Switcher.qml` to `~/.config/omarchy/plugins/io.github.paytonorogers.agent-switcher` (a `plugin add` checkout is already that directory, so this copy is skipped)
- writes `~/.config/hypr/agent-switcher.lua` (window rules and binds)
- adds one `require("hypr.agent-switcher")` line to `hyprland.lua` (backed up to `hyprland.lua.bak-agent-switcher`)
- enables the plugin and restarts the shell

Uninstall: `./uninstall.sh` reverts the launcher, icons, Hyprland include, and plugin directory, and keeps your config. `./uninstall.sh --purge` removes the config too. After `omarchy plugin add`, run it from the plugin directory before `omarchy plugin remove`, because remove does not run this script.

`./install.sh` now keeps `Switcher.qml` at `plugin/Switcher.qml`. If you previously installed an older revision and edited the flattened `Switcher.qml` next to the manifest, those edits are not copied; the old file is left in place and no longer loaded.

## Choosing agents
`omarchy-agents setup` re-runs detection at any time (`--yes` takes everything it finds). Detection uses
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
prev_key   = SUPER + ALT + LEFT     # only bound while the panel is open
next_key   = SUPER + ALT + RIGHT
accent     =                        # empty = theme accent; e.g. #9B7BD4
accent_inactive =                   # empty = theme selection colour
width = 0.62   height = 0.82   top = 0.06   # fractions of the focused monitor (one per line)
slide_ms = 250                      # agent-switch slide; sets Hyprland's windowsMove animation once
opacity = 0.82 0.75
rounding = 14
dim = true
show_hint = true                    # keyboard hint under the strip
start_hidden = grok-bot             # optional: launch this class hidden at login

# name | window class | launch command | direct key (optional) | icon (optional)
Grok Bot   | grok-bot              | uwsm-app -- grok-bot | SUPER + SHIFT + A | grok-bot
Grok Build | org.omarchy.grokbuild | omarchy-launch-tui --app-id=org.omarchy.grokbuild grok | SUPER + ALT + A | grok
```
After editing, run `omarchy-agents rules` to regenerate the Hyprland include and reload.

**Icons** can be a bundled name (`grok`, `grok-bot`, `claude`, `codex`, `hermes`), an icon-theme name, or an absolute path.

**Terminal agents:** use an absolute path or `$HOME/...` for the binary. Apps launched through uwsm don't see your shell's PATH.

## Keybinds (defaults)
| Keys | Action |
|---|---|
| Super+A | open / close the drop-down (last agent) |
| Super+Alt+← / → | previous / next agent (only while open) |
| per-agent `direct key` | open that agent, switch to it, or close it if it's already showing |
| scroll on strip, or click it then ← → Tab 1-9 Esc | switch / close |

The Super+Alt+←/→ defaults shadow Omarchy's "move window to group" only while the panel is open, and
are restored on close. If you pick keys that already do something else, `omarchy-agents rules` warns you.

## CLI
`omarchy-agents toggle | show <name> | next | prev | hide | direct <class> | list | setup [--yes] | rules | doctor | hint on|off|toggle`

`omarchy-agents hint off` hides the keyboard hint right away and saves `show_hint = false` in your config. Use `hint on` or `hint toggle` to change it back.

## Troubleshooting
- **No strip:** run `omarchy-agents doctor`, then `omarchy plugin enable io.github.paytonorogers.agent-switcher && omarchy-restart-shell`. Editing the QML may need a full shell restart; hot reload can fail.
- **Agent not floating or in the wrong place:** check its real class with `hyprctl clients`, fix it in `agents.conf`, then run `omarchy-agents rules`.
- **Agent tab shows a plain terminal or takes a while the first time:** that's the agent's own first run. For example, Omarchy's `~/.local/bin/claude` installs Claude Code with mise on first launch, which is a one-time download of ~200 MB, and Codex shows a sign-in screen until you log in. Switching never waits for a starting agent: its window pops into the panel when it's ready, and you get a "Starting …" notification.
- **Launch lines:** `$HOME` and `~` are expanded, and bare program names are resolved against PATH plus mise shims, `~/.local/bin`, npm, bun and cargo before launching. Apps started through uwsm/systemd don't see your shell's PATH.
- **Pre-launch:** `start_hidden = grok-bot, org.omarchy.agent.claude` takes a comma list of classes to start hidden at login, so the first open is instant.
- **Tab missing:** its program wasn't found. `doctor` lists skipped agents.
- **Config errors:** `hyprctl configerrors`. The generated file is `~/.config/hypr/agent-switcher.lua`.
- **Multi-monitor:** the panel opens on the focused monitor. Inactive agents wait just past that monitor's left and right edges, which can overlap a neighbouring monitor. Please report any issues.

## Credits
- Built for Omarchy by DHH and contributors, on Hyprland and quickshell.
- Agent icons come from [auxxed's Omarchy agents plugin](https://github.com/auxxed) (MIT).
- Author: Payton Rogers. MIT licensed, see LICENSE.

## Updating
```sh
omarchy plugin update io.github.paytonorogers.agent-switcher
```
The next time the shell loads the panel, it copies `omarchy-agents` and `registry.conf` again when the checkout copies are newer, and copies the icons in that same pass. `agents.conf` is left alone.

A git clone still updates with `cd omarchy-agent-switcher && git pull && ./install.sh`.
