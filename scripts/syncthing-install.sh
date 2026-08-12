#!/usr/bin/env bash

set -euo pipefail

service_name="syncthing.service"
state_root="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy-syncthing"
state_file="$state_root/installation.json"
operation_file="$state_root/operation.pid"
bin_link="$HOME/.local/bin/syncthing"
service_file="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/$service_name"
script_path="$(readlink -f -- "$0")"

fail() {
  printf 'Error: %s\n' "$*" >&2
  return 1
}

step() {
  printf '\n==> %s\n' "$*"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}

record_value() {
  jq -r --arg key "$1" '.[$key] // ""' "$state_file" 2>/dev/null
}

service_property() {
  systemctl --user show "$service_name" --property="$1" --value \
    2>/dev/null || true
}

operation_running() {
  local pid=""
  [[ -f $operation_file ]] || return 1
  pid="$(<"$operation_file")"
  [[ $pid =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null
}

detect_status() {
  local active_state="inactive" executable="" executable_path=""
  local executable_owner=""
  local installed_method="" installed_version="" label="Not installed"
  local load_state="not-found" service_unit="" state="missing"

  executable="$(command -v syncthing 2>/dev/null || true)"
  if [[ -n $executable ]]; then
    executable_path="$(readlink -f -- "$executable" 2>/dev/null || true)"
    [[ -n $executable_path ]] || executable_path="$executable"
    executable_owner="$(pacman -Qoq -- "$executable_path" 2>/dev/null || true)"
  fi

  load_state="$(service_property LoadState)"
  active_state="$(service_property ActiveState)"
  service_unit="$(service_property FragmentPath)"
  [[ -n $load_state ]] || load_state="not-found"
  [[ -n $active_state ]] || active_state="inactive"

  if [[ -f $state_file ]] && jq -e '.method | type == "string"' \
      "$state_file" >/dev/null 2>&1; then
    installed_method="$(record_value method)"
    installed_version="$(record_value version)"
    state="broken"

    if [[ $installed_method == package ]]; then
      label="Omarchy package"
      if [[ $executable_owner == syncthing &&
            $service_unit == /usr/lib/systemd/user/syncthing.service ]]; then
        state="managed"
      fi
    else
      # Removed source installs stay broken rather than deleting recorded paths.
      label="Invalid installation record"
    fi
  elif [[ -n $executable_path || $load_state != not-found ||
          -e $bin_link || -L $bin_link || -e $service_file ||
          -L $service_file ]]; then
    state="external"
    label="Existing installation"
  fi

  jq -n \
    --arg state "$state" \
    --arg method "$installed_method" \
    --arg version "$installed_version" \
    --arg label "$label" \
    --arg executable "$executable_path" \
    --argjson serviceAvailable \
      "$([[ $load_state != not-found ]] && echo true || echo false)" \
    --argjson serviceRunning \
      "$([[ $active_state == active ]] && echo true || echo false)" \
    --argjson operationRunning \
      "$(operation_running && echo true || echo false)" \
    '{
      state: $state,
      method: $method,
      version: $version,
      label: $label,
      executable: $executable,
      serviceAvailable: $serviceAvailable,
      serviceRunning: $serviceRunning,
      operationRunning: $operationRunning
    }'
}

installation_state() {
  detect_status | jq -r '.state'
}

write_record() {
  local version="$1" temporary=""

  mkdir -p -- "$state_root"
  temporary="$(mktemp "$state_root/installation.XXXXXX")"
  jq -n \
    --arg version "$version" \
    '{
      method: "package",
      version: $version,
      executable: "/usr/bin/syncthing"
    }' >"$temporary"
  chmod 600 "$temporary"
  mv -- "$temporary" "$state_file"
}

ensure_initial_install() {
  local state=""
  state="$(installation_state)"
  [[ $state == missing ]] || fail \
    "Syncthing must be absent before installing it (state: $state)"
}

install_package() {
  ensure_initial_install
  require_command omarchy
  require_command pacman

  step "Installing the official Arch package through Omarchy"
  omarchy pkg add syncthing
  write_record "$(pacman -Q syncthing | awk '{print $2}')"
  step "Enabling the Syncthing user service"
  systemctl --user daemon-reload
  systemctl --user enable --now "$service_name"
}

uninstall_syncthing() {
  local method=""

  [[ $(installation_state) == managed ]] || fail \
    "This plugin does not own the current Syncthing installation"
  method="$(record_value method)"
  [[ $method == package ]] || fail \
    "Unknown recorded installation method: $method"

  step "Stopping and disabling the Syncthing user service"
  systemctl --user disable --now "$service_name" >/dev/null 2>&1 || true
  step "Removing the official package through Omarchy"
  omarchy pkg drop syncthing
  rm -f -- "$state_file"
  systemctl --user daemon-reload
}

run_and_prompt() {
  local action="$1" result=0
  shift

  mkdir -p -- "$state_root"
  if operation_running; then
    fail "Another Syncthing operation is already running"
  fi
  printf '%s\n' "$$" >"$operation_file"
  trap 'rm -f -- "$operation_file"' EXIT

  printf 'Syncthing for Omarchy\n'
  printf '%s\n' '----------------------'
  set +e
  (
    set -Eeuo pipefail
    case "$action" in
      install-package) install_package ;;
      uninstall) uninstall_syncthing ;;
      *) fail "Unknown operation: $action" ;;
    esac
  )
  result=$?
  set -e

  if (( result == 0 )); then
    printf '\nDone. The Syncthing operation completed successfully.\n'
  else
    printf '\nThe operation failed. Review the error above.\n' >&2
  fi
  printf 'Press Enter to close this terminal. '
  IFS= read -r _
  return "$result"
}

launch_terminal() {
  local action="$1"
  shift
  require_command uwsm-app
  require_command xdg-terminal-exec
  exec uwsm-app -- xdg-terminal-exec --title="Syncthing setup" -- \
    bash "$script_path" run "$action" "$@"
}

case "${1:-status}" in
  status) detect_status ;;
  install) launch_terminal install-package ;;
  uninstall) launch_terminal uninstall ;;
  run)
    shift
    run_and_prompt "$@"
    ;;
  *)
    fail "usage: ${0##*/} {status|install|uninstall}"
    exit 2
    ;;
esac
