# HANDOFF — omarchy-agent-switcher v1.1 → v1.2 (for Grok Build / next agent)

## Goal
Polished, portable Super+A agent drop-down for Omarchy (bash `bin/omarchy-agents` + quickshell plugin `plugin/Switcher.qml`
+ generated `~/.config/hypr/agent-switcher.lua`). v1.1 = fix the 39-item review of v1.0. Branch `v1.1` only, never push master.

## State (2026-10-10, built on the box, NOT yet run on a real Omarchy desktop)
Done and unit-tested (fake Hyprland): items 1-17, 19-22, 24-27, 29, 30, 36-39.
Done best-effort, **needs laptop verification**: 18 (QML "Cannot override FINAL property": not reproduced; check `journalctl --user -u omarchy-shell`/shell log after restart), 23 (theme hook at `~/.config/omarchy/hooks/theme-set` — confirm Omarchy runs this hook name), 28/33/35 (tab states running/starting/stopped, "…" while starting), 32 (right-click Restart/Close row, middle-click close), 34 (focus ring, Accessible names; reduced motion = `slide_ms = 0`), 7 (per-call Process via Component + wheel throttle), 6 (payload `seq`).
Skipped (needs Payton's decision / design): 31 first-run settings panel/wizard UI (CLI wizard exists); 33 "activity dot" (needs per-agent activity signal); demo GIF recording (item 10 placeholder only).

Item map: 1 uninstall exact lines · 2 one-setting-per-line + warnings · 3 validation+Lua escaping (`lq`, `valid_class`, `valid_key`) · 4 `idx_of` no fallback, `need_idx` · 5 `pcall` per dispatch, hide restores opacity · 6 seq · 7 Process per call · 8 restore only real Omarchy default (`OMARCHY_DEFAULT_*`) · 9 README: use install.sh not `omarchy plugin add` · 10 version 1.1.0/CHANGELOG · 11 SELF=~/.local/bin copy · 12 launch timeout + notify · 13 slide_ms clamp/0=off · 14 autohide on empty focus · 15 `program_of`/`resolve_cmd` keep args · 16 unknown agent error · 17 hint w/o config · 19 registry validation in detect · 20 AGENT_PATH appended, used only for agent lookup · 21 address/int validation · 22 park outside whole desktop (DX0/DX1) · 24 `override_slide_animation` · 25 atomic staging in install · 26 preflight + `--no-restart` · 27 log + `OMARCHY_AGENTS_DEBUG` · 29 doctor deps, README min versions · 30 single jq payload · 36 THIRD_PARTY.md · 37 docs · 38 CI · 39 issue template.

## Added later in v1.1 (box-tested only)
- Sizing: `geometry()`/`size_for()`/`capture_user_size()` in bin/omarchy-agents; saved sizes in `$STATE/size/<class>@<monitor>`. A size change is detected at the next open/switch/hide (no Hyprland resize event), so the strip re-anchors then, not live.
- Shortcuts sheet: payload `shortcuts` + `sheet`; QML `sheetBox` above the strip (window grows upward); `resize_binds()` reads `hyprctl binds -j` dispatchers matching /resize/ — **verify Omarchy's Lua binds report `dispatcher` that way**; if not, the sheet simply omits resize keys.
- `omarchy plugin add` (from PR #1): manifest.json at repo root, entry plugin/Switcher.qml; panel runs ../install.sh --from-shell once (marker $STATE/installed = "version source"). Laptop check: `omarchy plugin add <url> --enable --yes` on a clean user.
- Laptop checks: sizes on the real monitor; resize with Omarchy keys → switch away/back keeps size; strip under resized agent; slide between different-size agents; `?`/button/Esc/click-away on the sheet; sheet doesn't go off the top of the screen.

## v1.2 (branch v1.2, box-tested only)
- send / send-files (`send_text`, `send_files`, `paste_into`, `kind_of` in bin/omarchy-agents). Keystroke: wtype → ydotool → `hyprctl dispatch sendshortcut` (unverified under the Lua config). Chromium extension was dropped at Payton's request; selected text goes only via `send_key`.
- Nautilus: integrations/nautilus/omarchy-agent-switcher.py (`--with-nautilus`). Written against the standard nautilus-python MenuProvider API, NOT checked against /usr/share/omarchy/default/nautilus-python (not on the box).
- Usage meter: vendored collectors in share/collectors (auxxed MIT), `usage_json`/`usage_refresh`/`provider_of`; QML fill + hover %. Records read from ~/.local/state/omarchy/agents/usage/*.json (percent 0..1).
- `open_on` (`open_on_idx`): toggle target when hidden; setup wizard asks (default last).
- Laptop checks: paste lands in Grok Bot (Ctrl+V) and in TUI agents (Ctrl+Shift+V); image paste into Grok Bot; slurp cancel; Nautilus menu shows and sends; usage fill shows real numbers for grok/grok-bot/claude/codex; tokens absent from ~/.local/state/omarchy-agent-switcher/log; whether `omarchy-capture-region` exists/accepts a path.

## Test env
`tests/run.sh` (needs bash, jq, flock; lua5.4 `luac` optional) — 99 checks, fake `hyprctl`/`omarchy-shell` in `tests/stubs` serve JSON from `$FAKE`, record calls in `$FAKE/calls`. Lint: `shellcheck -S warning bin/omarchy-agents install.sh uninstall.sh tests/run.sh tests/stubs/*`; QML syntax: `/usr/lib/qt6/bin/qmlformat plugin/Switcher.qml >/dev/null` (qmllint can't resolve Quickshell modules → noise). CI: `.github/workflows/ci.yml`.

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

## Deferred: send-shot (removed from v1.2 at Payton's request)
Region screenshot → agent. Re-add: `shot_key` setting + bind in gen_rules ("Send screenshot to agent" → `send-shot`), cheat-sheet entry, `send-shot) send_shot ;;` case, README/default conf lines, tests (stubs grim/slurp kept). Use `wlc` (not bare wl-copy) so the clipboard daemon never holds the lock. Code as it was:

```bash
  (( ${#paths[@]} )) || die "send-files: no existing files given"
  local kind; kind=$(kind_of "$i")
  if [[ $kind == tui ]]; then printf '%q ' "${paths[@]}" | wlc
  elif (( ${#paths[@]} == 1 )) && [[ ${paths[0],,} =~ \.(png|jpe?g|gif|webp)$ ]]; then
    local ext=${paths[0]##*.}; ext=${ext,,}; [[ $ext == jpg ]] && ext=jpeg; wlc --type "image/$ext" < "${paths[0]}"
  else printf '%s\n' "${paths[@]}" | jq -Rr '"file://" + (split("/") | map(@uri) | join("/"))' | wlc --type text/uri-list; fi
  show_target "$i"; paste_into "$i" "$kind"; log "send-files: ${#paths[@]} file(s) -> ${names[$i]} ($kind)"
}
capture_region() { # capture_region <file>: grim+slurp, else Omarchy's capture helper
  if command -v grim >/dev/null && command -v slurp >/dev/null; then local g; g=$(slurp 2>/dev/null) || return 1; grim -g "$g" "$1"
  elif command -v omarchy-capture-region >/dev/null; then omarchy-capture-region "$1"
  else die "send-shot needs grim + slurp (or omarchy-capture-region)"; fi
  [[ -s $1 ]]
}
send_shot() {
  command -v wl-copy >/dev/null || die "send-shot needs wl-clipboard"
  local d=$STATE/shots f i kind; mkdir -p "$d"; f=$d/shot-$(date +%Y%m%d-%H%M%S).png
  # the capture is interactive: release the lock so the strip stays usable meanwhile
  flock -u 9
  capture_region "$f" || { log "send-shot: cancelled"; return 0; }
  flock -w 3 9 || exit 0
  i=$(target_idx); kind=$(kind_of "$i")
  if [[ $kind == gui ]]; then wlc --type image/png < "$f"; else printf '%s' "$f" | wlc; fi
  show_target "$i"; paste_into "$i" "$kind"; log "send-shot: $f -> ${names[$i]} ($kind)"
}

pretty() { local k=${1// /}; k=${k//SUPER/Super}; k=${k//SHIFT/Shift}; k=${k//ALT/Alt}; k=${k//CTRL/Ctrl}; k=${k//LEFT/←}; k=${k//RIGHT/→}; k=${k//UP/↑}; k=${k//DOWN/↓}; echo "$k"; }
```

## Deferred: richer Grok Bot states (approval, working)

Grok Bot has no hook system. Today its only signal is a desktop notification per reply
(app "Grok Bot", summary = agent name, body = first line of the reply), which drives the
green "new reply" dot (validated). Feasibility of approval/working (next sprint):
- Notification history JSON (~/.local/state/omarchy/notifications/history/*.json) carries
  app, summary, body, urgency, timestamp. No actions, category or hints that mark an
  approval card; approval prompts look like ordinary replies ("Post this comment and close PR #1?").
- Heuristics on body text (question mark, "approve", "OK to") would be unreliable.
- Feasible routes: (1) ask the Grok Bot app for a notification category/hint or action
  buttons on approval cards (then map in notif-watch); (2) a local status API/file from the app.
- Window title is static ("Grok Bot"): not usable.

## Status 2026-10-11 20:05 PT (handoff to Grok Build)

Branch tips (local only, nothing pushed): see `git log -1 v1.2` and `git log -1 feature/status-dots`. No stashes.

- **#5 click-through: fixed in code (5cc4ab4), needs Payton to retest with a real click.** The real cause wasn't resize_on_border, which is already off on his laptop. `dim_around` on a window makes Hyprland use the whole monitor as that window's hit box (`CWindow::getWindowBoxUnified`), so every outside click hit the agent and showed a resize cursor. With `click_through` on, agents now get `dim_around 0` and the screen is dimmed with `decoration:dim_special` (max(user, 0.4)) while the panel is open; the user's value is restored on close.
- **Strip hover resize/flicker: fixed in code, not checked by eye.** The window width now comes from TextMetrics of the default hint text, and the hover text is elided into that fixed width. The hint line no longer appears or disappears on hover. Hovering can't be simulated with `hyprctl dispatch movecursor` because it sends no pointer motion to layer surfaces, so Payton needs to check by hand. If `hint` is off, no hover detail is shown (the usage fill and the a11y name still show it).
- **Purple right-edge artifact: likely fixed, not confirmed.** There was no artifact in a static crop (/workspace/talos/strip-before.png on the box). Best guess: the invisible reserved "100%" width on the last tab, plus that tab's 1px accent hover border. The reserved space is now gone except in usage_display=percent mode. Ask Payton whether it's still there.
- **Grok Bot sound delay: open.** The watcher reacts immediately: the history file was written at 19:53:54.700 and our status/sound fired in the same second. The watcher is dbus-monitor (event-driven, no polling). canberra-gtk-play took about 1.36 s total, so the default player is now pw-play (starts in about 25 ms) and the log has ms timestamps. If there's still a delay, the Grok Bot app sends its notification late, which we can't change. Omarchy's notification service plays no sound itself, so there's no double play.
- **Sound while Grok Bot focused: fixed (feature/status-dots 06af112), needs Payton's retest.** The check now uses the real active window (class matched case-insensitively), and it counts if the window is on a normal workspace or on a special workspace that's currently shown. The Grok Bot notification path goes through the same check, and there's a test for it.
- **Grok Bot usage "Sign-in expired": research only, nothing built.** The collector reads `~/.config/Grok Bot/sand-secrets.json` (cursor-accounts → access/refresh tokens). Those tokens are encrypted Chromium-style v10, with the key from the "Grok Bot Safe Storage" libsecret item (fallback "peanuts"). It falls back to `~/.cursor/auth.json`. When the token has expired it refreshes in memory via `api2.cursor.sh/oauth/token` and never writes back. So it already reuses the app's current session. "Sign-in expired" means the stored access token is expired AND the refresh failed. The likely cause is refresh-token rotation, or the app keeping its fresh token only in memory and writing the file only at login (the file was last written at 19:28 when the app restarted). Options: re-read after the app rewrites the file, or ask the app to expose usage. A silent refresh that writes the file back would race the app and could log it out, so don't. Security: sand-secrets.json is mode 644 (world-readable, encrypted, but the fallback key is public), which is the app's problem to fix. A re-login in the app is the reliable fix today.
