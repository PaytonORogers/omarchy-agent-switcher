#!/usr/bin/env bash
# shellcheck disable=SC2034  # Fields and globals are shared with the caller.
# Shared configuration commands. Sourced by omarchy-agents.
mutation_lock() { exec 7>"$STATE/config.lock"; flock -w 10 7 || die "configuration is busy; retry"; }

configuration_rows() {
  local line raw n c l id kind det launch icon
  if [[ -f $CONF ]]; then
    while IFS= read -r line; do
      raw=$(trim "$line"); [[ $raw == \#* ]] && raw=$(trim "${raw#\#}")
      [[ $raw == *'|'* ]] || continue
      IFS='|' read -r n c l _ icon _ <<<"$raw"
      n=$(trim "$n"); c=$(trim "$c"); l=$(trim "$l")
      valid_class "$c" && available "$l" || continue
      id=""; line=$(find_registry "$c") && IFS='|' read -r id _ <<<"$line"
      jq -cn --arg name "$n" --arg class "$c" --arg id "$(trim "$id")" --arg line "$raw" '{name:$name,class:$class,id:$id,line:$line}'
    done < "$CONF"
  fi
  while IFS= read -r line; do
    IFS='|' read -r id n kind det c launch icon <<<"$line"
    jq -cn --arg name "$(trim "$n")" --arg class "$(trim "$c")" --arg id "$(trim "$id")" --arg line "$(agent_line "$line")" '{name:$name,class:$class,id:$id,line:$line}'
  done < <(detect)
}
catalog_json() {
  load_conf
  local enabled; enabled=$(printf '%s\n' "${names[@]+"${names[@]}"}" | jq -R . | jq -sc 'map(select(length>0))')
  configuration_rows | jq -sc --argjson enabled "$enabled" --argjson shortcuts "$(shortcuts_json)" --arg open "${S[open_on]}" --arg hint "${S[show_hint]:-true}" --arg usage "${S[usage_display]}" --arg opacity "${S[opacity]}" '
    reduce .[] as $a ([]; if any(.[]; (.class|ascii_downcase)==($a.class|ascii_downcase)) then . else .+[$a] end)
    | map(. + {enabled: (.name as $n | $enabled | index($n)!=null)} | del(.line))
    | {agents:., enabled:$enabled, shortcuts:$shortcuts, settings:{open_on:$open,show_hint:($hint!="false"),usage_display:$usage,opacity:$opacity}}'
}
auth_json() {
  local row id rc
  row=$(configuration_rows | jq -sc --arg n "${1,,}" 'first(.[] | select((.name|ascii_downcase)==$n or (.class|ascii_downcase)==$n or (.id|ascii_downcase)==$n)) // empty')
  [[ -n $row ]] || die "agent is not installed: $1"
  id=$(jq -r .id <<<"$row")
  setup_auth_status "$id"; rc=$?
  local state=confirmation_needed
  (( rc == 0 )) && state=verified
  (( rc == 1 )) && state=signed_out
  jq -c --arg state "$state" '. + {state:$state} | del(.line)' <<<"$row"
}
upsert_setting() {
  local key=$1 value=$2 tmp
  mkdir -p "$(dirname "$CONF")"
  [[ -f $CONF ]] || { cp "$DATA/agents.conf.default" "$CONF"; upsert_only ""; }
  tmp=$(mktemp "$CONF.setting.XXXXXX")
  awk -v k="$key" -v v="$value" 'BEGIN{done=0} $0 ~ "^[[:space:]]*" k "[[:space:]]*=" {if(!done) print k " = " v; done=1; next} {print} END{if(!done) print k " = " v}' "$CONF" > "$tmp"
  mv "$tmp" "$CONF"
}
settings_update() {
  local key=${1:-} value=${2:-} i
  load_conf
  case $key in
    open_on) if [[ $value != last && $value != first ]]; then i=$(idx_of "$value"); [[ -n $i ]] || die "unknown opening target"; value=${names[$i]}; fi ;;
    show_hint) [[ $value == true || $value == false ]] || die "show_hint needs true or false" ;;
    usage_display) [[ $value == fill || $value == percent || $value == off ]] || die "usage_display needs fill, percent, or off" ;;
    opacity) [[ $value =~ ^(0(\.[0-9]+)?|1(\.0+)?)(\ (0(\.[0-9]+)?|1(\.0+)?))?$ ]] || die "opacity must be between 0 and 1" ;;
    *) die "unsupported setting: $key" ;;
  esac
  upsert_setting "$key" "$value"
  gen_rules >/dev/null; hyprctl reload >/dev/null
  "$SELF" refresh >/dev/null 2>&1
}
move_agent() {
  local i j v joined n
  load_conf; i=$(need_idx "${1:-}") || return 1
  case ${2:-} in left) j=$((i-1)) ;; right) j=$((i+1)) ;; *) die "usage: move NAME left|right" ;; esac
  (( j >= 0 && j < ${#names[@]} )) || return 0
  v=${names[$j]}; names[$j]=${names[$i]}; names[$i]=$v
  joined=${names[0]}; for n in "${names[@]:1}"; do joined+=", $n"; done
  upsert_only "$joined"
  "$SELF" refresh >/dev/null 2>&1
}
configure_show() {
  desktop_ready || return 0
  if [[ $(signin_pending_json) != null && $(timeout 2 omarchy-shell -q agentswitcher resumeSignin show 2>/dev/null) == handled ]]; then return 0; fi
  load_conf
  local payload mon top
  mon=$(hyprctl -j monitors | jq -c 'first(.[]|select(.focused))')
  top=$(jq -r '((.reserved[1] // 0) + 12)' <<<"$mon")
  payload=$(jq -cn --arg bin "$SELF" --arg mon "$(jq -r .name <<<"$mon")" --argjson top "$top" --arg key "${S[toggle_key]}" --argjson picker "${1:-false}" '{bin:$bin,monitor:$mon,top:$top,edge:"top",toggleKey:$key,agents:[],active:"",configureOpen:true,picker:$picker}')
  timeout 3 omarchy-shell -q shell summon "$PLUGIN_ID" "$payload"
}
login_window_command() {
  desktop_ready || die "Return to the desktop before opening the agent."
  local row reg c line workspace=${2:-} address deadline
  [[ $workspace =~ ^[0-9]+$ ]] || die "normal workspace required"
  row=$(configuration_rows | jq -sc --arg n "${1,,}" 'first(.[]|select((.name|ascii_downcase)==$n or (.class|ascii_downcase)==$n)) // empty')
  [[ -n $row ]] || die "agent is not installed"
  c=$(jq -r .class <<<"$row"); line=$(jq -r .line <<<"$row")
  reg="$(jq -r .id <<<"$row") | $(jq -r .name <<<"$row") | gui | bin:unused | $c | $(cut -d'|' -f3 <<<"$line") |"
  setup_login_window "$reg" "$workspace" >/dev/null || return 1
  deadline=$((SECONDS + ${OMARCHY_AGENTS_LOGIN_TIMEOUT:-20}))
  while (( SECONDS < deadline )); do
    address=$(client_addr "$c")
    if is_addr "$address"; then
      # Apply to late-mapping launches as well as already-open windows.
      hyprctl eval "hl.dispatch(hl.dsp.window.move({ workspace = '$workspace', follow = false, window = 'address:$address' }))" >/dev/null || return 1
      if [[ $(hyprctl -j clients | jq -r --arg a "$address" 'first(.[]|select(.address==$a)).floating // false') == true ]]; then
        hyprctl eval "hl.dispatch(hl.dsp.window.float({ window = 'address:$address', action = 'toggle' }))" >/dev/null || return 1
      fi
      hyprctl eval "hl.dispatch(hl.dsp.focus({ window = 'address:$address' }))" >/dev/null || return 1
      if [[ $(hyprctl -j clients | jq -r --arg a "$address" 'first(.[]|select(.address==$a)).workspace.name // ""') != "$workspace" ]]; then
        echo "The agent could not move to the normal workspace. Retry or cancel." >&2; return 1
      fi
      jq -cn --arg address "$address" '{state:"opening",address:$address}'; return 0
    fi
    sleep 0.2
  done
  echo "The agent window did not appear. Check its launcher and retry." >&2; return 1
}
arrange_keys() {
  local on=${1:-off}
  if [[ $on == on ]]; then
    hyprctl eval "hl.dispatch(hl.dsp.submap('agent-switcher-arrange'))" >/dev/null
  else
    # Do not reset another application's submap.
    hyprctl eval "if agent_switcher and agent_switcher.arranging then hl.dispatch(hl.dsp.submap('reset')) end" >/dev/null
  fi
  hyprctl eval "if agent_switcher then agent_switcher.arranging=$([[ $on == on ]] && echo true || echo false) end" >/dev/null
}
