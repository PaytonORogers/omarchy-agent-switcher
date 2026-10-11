# HANDOFF — omarchy-agent-switcher v1.1 (for Grok Build / next agent)

## Goal
Polished, portable Super+A agent drop-down for Omarchy (bash `bin/omarchy-agents` + quickshell plugin `plugin/Switcher.qml`
+ generated `~/.config/hypr/agent-switcher.lua`). v1.1 = fix the 39-item review of v1.0. Branch `v1.1` only, never push master.

## State (2026-10-10, built on the box, NOT yet run on a real Omarchy desktop)
Done and unit-tested (fake Hyprland): items 1-17, 19-22, 24-27, 29, 30, 36-39.
Done best-effort, **needs laptop verification**: 18 (QML "Cannot override FINAL property": not reproduced; check `journalctl --user -u omarchy-shell`/shell log after restart), 23 (theme hook at `~/.config/omarchy/hooks/theme-set` — confirm Omarchy runs this hook name), 28/33/35 (tab states running/starting/stopped, "…" while starting), 32 (right-click Restart/Close row, middle-click close), 34 (focus ring, Accessible names; reduced motion = `slide_ms = 0`), 7 (per-call Process via Component + wheel throttle), 6 (payload `seq`).
Skipped (needs Payton's decision / design): 31 first-run settings panel/wizard UI (CLI wizard exists); 33 "activity dot" (needs per-agent activity signal); demo GIF recording (item 10 placeholder only).

Item map: 1 uninstall exact lines · 2 one-setting-per-line + warnings · 3 validation+Lua escaping (`lq`, `valid_class`, `valid_key`) · 4 `idx_of` no fallback, `need_idx` · 5 `pcall` per dispatch, hide restores opacity · 6 seq · 7 Process per call · 8 restore only real Omarchy default (`OMARCHY_DEFAULT_*`) · 9 README: use install.sh not `omarchy plugin add` · 10 version 1.1.0/CHANGELOG · 11 SELF=~/.local/bin copy · 12 launch timeout + notify · 13 slide_ms clamp/0=off · 14 autohide on empty focus · 15 `program_of`/`resolve_cmd` keep args · 16 unknown agent error · 17 hint w/o config · 19 registry validation in detect · 20 AGENT_PATH appended, used only for agent lookup · 21 address/int validation · 22 park outside whole desktop (DX0/DX1) · 24 `override_slide_animation` · 25 atomic staging in install · 26 preflight + `--no-restart` · 27 log + `OMARCHY_AGENTS_DEBUG` · 29 doctor deps, README min versions · 30 single jq payload · 36 THIRD_PARTY.md · 37 docs · 38 CI · 39 issue template.

## Test env
`tests/run.sh` (needs bash, jq, flock; lua5.4 `luac` optional) — 40 checks, fake `hyprctl`/`omarchy-shell` in `tests/stubs` serve JSON from `$FAKE`, record calls in `$FAKE/calls`. Lint: `shellcheck -S warning bin/omarchy-agents install.sh uninstall.sh tests/run.sh tests/stubs/*`; QML syntax: `/usr/lib/qt6/bin/qmlformat plugin/Switcher.qml >/dev/null` (qmllint can't resolve Quickshell modules → noise). CI: `.github/workflows/ci.yml`.

## Gotchas
- `setsid` in `launch` doesn't fork → never `wait` for all children at script end (would block on the agent).
- Hyprland Lua: `hl.dispatch(hl.dsp.*)` builders throw before dispatch → wrap the whole call in `pcall(function() ... end)` (helper `q`).
- Hidden special workspaces clamp off-screen windows: open_idx sets opacity 0 on others, toggles, re-parks, restores.
- Payton: lazy start, `start_hidden = grok-bot` only; no ChatGPT in his config; keep `show_hint = true`.
- Hot-reloading QML is flaky → `omarchy-restart-shell`.

## Exact next steps (on the laptop)
1. `git fetch <bundle> v1.1:v1.1` (or pull branch v1.1), `git checkout v1.1`, `tests/run.sh`.
2. `./install.sh` (keeps agents.conf). `omarchy-agents doctor`; `hyprctl configerrors` empty.
3. Verify: Super+A open/close slides up; switch L/R directions; cursor stays; click link → panel+strip hide; first launch of an uninstalled-yet agent shows "…" then window; right-click menu; `omarchy-agents hint toggle`; theme change (`omarchy-theme-set <x>`) recolours borders; 2-monitor parking.
4. Fix anything from step 3, bump CHANGELOG, open PR v1.1 → master (Payton merges).
