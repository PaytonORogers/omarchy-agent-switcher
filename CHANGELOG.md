# Changelog

## 1.1.0 — 2026-10
### Fixed
- `uninstall.sh` removes exactly its two lines from `hyprland.lua` (a missing marker could delete the rest of the file).
- Config: one setting per line is documented; unknown settings and several-settings-per-line are reported.
- Agent names/classes/keys are validated and Lua-escaped before going into the generated Hyprland include and `hyprctl eval`.
- `show`/`direct` for an unknown or uninstalled agent now errors instead of silently acting on the first tab; `start_hidden` skips missing agents.
- Every Hyprland dispatch is isolated (`pcall`), so one failure can't leave agent windows invisible; `hide` always restores opacity.
- Strip updates carry a sequence number; out-of-order updates are dropped. Clicks and scrolls are never lost (one process per call); touchpad scrolling is throttled.
- Cycle keys only restore an Omarchy default that was really bound; custom binds are no longer overwritten on close.
- Generated binds always point at `~/.local/bin/omarchy-agents`.
- Failed agent launches are detected (20 s) and reported by notification; the "starting" marker clears.
- `slide_ms = 0` disables the slide instead of producing speed 0; tiny values are clamped.
- Auto-hide also closes when focus goes to nothing (empty desktop).
- Launch lines: only the program word is resolved; arguments and quoting are kept verbatim. Flatpak detection handles `flatpak run` options.
- `hint` works without an existing config.
- Extra agent search paths no longer shadow system tools.
- Inactive agents park outside the whole desktop (no peeking onto neighbouring monitors).
### Added
- Theme-change hook regenerates border colours.
- `override_slide_animation = false` keeps your own `windowsMove` animation.
- `install.sh` preflight checks, atomic file swaps, `--no-restart`.
- Log file + `OMARCHY_AGENTS_DEBUG=1`; `doctor` checks dependencies and shows recent log lines.
- Tab states (running / starting / not started), right-click Restart/Close menu, middle-click close, keyboard focus ring, accessibility names.
- `close`, `restart`, `version`, `rules --reload` subcommands.
- Unit tests with a fake Hyprland (`tests/run.sh`), GitHub Actions CI, issue template, THIRD_PARTY.md.

## 1.0.0
- First public release.
