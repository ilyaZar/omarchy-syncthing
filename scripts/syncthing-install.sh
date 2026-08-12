#!/usr/bin/env bash

set -euo pipefail

service_name="syncthing.service"
state_root="${XDG_STATE_HOME:-$HOME/.local/state}/omarchy-syncthing"
state_file="$state_root/installation.json"
operation_file="$state_root/operation.pid"
owner_marker=".omarchy-syncthing-owner"
bin_link="$HOME/.local/bin/syncthing"
service_file="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user/$service_name"
script_path="$(readlink -f -- "$0")"
repository_url="https://github.com/syncthing/syncthing.git"

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

directory_is_owned() {
  local path="$1" token="$2"
  [[ -n $path && -n $token && -f $path/$owner_marker ]] &&
    [[ $(<"$path/$owner_marker") == "$token" ]]
}

detect_status() {
  local active_state="inactive" source_root="" executable=""
  local executable_path="" executable_owner="" install_root=""
  local installed_method="" installed_version="" label="Not installed"
  local load_state="not-found" recorded_executable=""
  local ownership_token="" service_command="" service_unit="" state="missing"

  executable="$(command -v syncthing 2>/dev/null || true)"
  if [[ -n $executable ]]; then
    executable_path="$(readlink -f -- "$executable" 2>/dev/null || true)"
    [[ -n $executable_path ]] || executable_path="$executable"
    executable_owner="$(pacman -Qoq -- "$executable_path" 2>/dev/null || true)"
  fi

  load_state="$(service_property LoadState)"
  active_state="$(service_property ActiveState)"
  service_unit="$(service_property FragmentPath)"
  service_command="$(service_property ExecStart)"
  [[ -n $load_state ]] || load_state="not-found"
  [[ -n $active_state ]] || active_state="inactive"

  if [[ -f $state_file ]] && jq -e '.method | type == "string"' \
      "$state_file" >/dev/null 2>&1; then
    installed_method="$(record_value method)"
    installed_version="$(record_value version)"
    install_root="$(record_value installRoot)"
    source_root="$(record_value sourceRoot)"
    recorded_executable="$(record_value executable)"
    ownership_token="$(record_value ownershipToken)"
    state="broken"

    case "$installed_method" in
      package)
        label="Omarchy package"
        if [[ $executable_owner == syncthing &&
              $service_unit == /usr/lib/systemd/user/syncthing.service ]]; then
          state="managed"
        fi
        ;;
      release|git)
        if [[ $installed_method == release ]]; then
          label="Pinned release v$installed_version"
        else
          label="Latest GitHub checkout"
        fi
        if [[ -x $recorded_executable && -d $source_root/.git &&
              -L $bin_link &&
              $(readlink -f -- "$bin_link" 2>/dev/null || true) == "$recorded_executable" &&
              $service_unit == "$service_file" &&
              $service_command == *"$recorded_executable"* ]] &&
            directory_is_owned "$install_root" "$ownership_token" &&
            directory_is_owned "$source_root" "$ownership_token"; then
          state="managed"
          executable_path="$recorded_executable"
        fi
        ;;
      *) label="Invalid installation record" ;;
    esac
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
  local method="$1" version="$2" commit="$3" executable="$4"
  local install_root="$5" source_root="$6" ownership_token="$7"
  local temporary=""

  mkdir -p -- "$state_root"
  temporary="$(mktemp "$state_root/installation.XXXXXX")"
  jq -n \
    --arg method "$method" \
    --arg version "$version" \
    --arg commit "$commit" \
    --arg executable "$executable" \
    --arg installRoot "$install_root" \
    --arg sourceRoot "$source_root" \
    --arg ownershipToken "$ownership_token" \
    '{
      method: $method,
      version: $version,
      commit: $commit,
      executable: $executable,
      installRoot: $installRoot,
      sourceRoot: $sourceRoot,
      ownershipToken: $ownershipToken
    }' >"$temporary"
  chmod 600 "$temporary"
  mv -- "$temporary" "$state_file"
}

write_user_service() {
  local executable="$1" temporary=""

  mkdir -p -- "$(dirname -- "$service_file")"
  temporary="$(mktemp "${service_file}.XXXXXX")"
  printf '%s\n' \
    '[Unit]' \
    'Description=Syncthing file synchronization' \
    'Documentation=https://docs.syncthing.net/' \
    'After=network.target' \
    '' \
    '[Service]' \
    "ExecStart=\"$executable\" serve --no-browser --no-restart --no-upgrade" \
    'Restart=on-failure' \
    'RestartSec=5' \
    'SuccessExitStatus=3 4' \
    '' \
    '[Install]' \
    'WantedBy=default.target' >"$temporary"
  chmod 644 "$temporary"
  mv -- "$temporary" "$service_file"
}

expand_path() {
  local value="$1"
  case "$value" in
    '~') value="$HOME" ;;
    '~/'*) value="$HOME/${value#\~/}" ;;
  esac
  [[ $value == /* ]] || fail "Use an absolute path or start it with ~/"
  realpath -m -- "$value"
}

paths_overlap() {
  local left="${1%/}" right="${2%/}"
  [[ -n $left ]] || left="/"
  [[ -n $right ]] || right="/"
  [[ $left == / || $right == / || $left == "$right" ||
      $left == "$right"/* || $right == "$left"/* ]]
}

validate_managed_path() {
  local path="$1" reserved=""
  [[ -n $path && $path == /* ]] || fail "Installation paths must be absolute"
  [[ $path =~ ^/[A-Za-z0-9._/-]+$ ]] || fail \
    "Managed paths may use letters, numbers, slash, dot, underscore, and hyphen"
  for reserved in "$bin_link" "$service_file" "$state_root" "$script_path"; do
    ! paths_overlap "$path" "$reserved" || fail \
      "Managed path overlaps plugin files: $path"
  done
}

validate_github_paths() {
  local source_root="$1" install_root="$2"
  validate_managed_path "$install_root"
  if [[ -n $source_root ]]; then
    validate_managed_path "$source_root"
    ! paths_overlap "$source_root" "$install_root" || fail \
      "Clone and install paths must not overlap"
  fi
}

ensure_initial_install() {
  local state=""
  state="$(installation_state)"
  [[ $state == missing ]] || fail \
    "Syncthing must be absent before using the Omarchy package (state: $state)"
}

ensure_github_change() {
  local method="" state=""
  state="$(installation_state)"
  if [[ $state == missing ]]; then
    return
  fi
  [[ $state == managed ]] || fail \
    "The current Syncthing installation is not managed by this plugin"
  method="$(record_value method)"
  [[ $method == release || $method == git ]] || fail \
    "Uninstall the Omarchy package before choosing a GitHub source"
}

install_package() {
  ensure_initial_install
  require_command omarchy
  require_command pacman

  step "Installing the official Arch package through Omarchy"
  omarchy pkg add syncthing
  write_record package "$(pacman -Q syncthing | awk '{print $2}')" "" \
    /usr/bin/syncthing "" "" ""
  step "Enabling the Syncthing user service"
  systemctl --user daemon-reload
  systemctl --user enable --now "$service_name"
}

validate_version() {
  [[ $1 =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail \
    "Use a stable Syncthing version such as 2.1.3 (without v)"
}

build_source() {
  local method="$1" version="$2" source_root="$3"

  if [[ $method == release ]]; then
    validate_version "$version"
    step "Checking official release tag v$version"
    git ls-remote --exit-code --tags "$repository_url" \
      "refs/tags/v$version" >/dev/null || fail \
      "Syncthing has no official release tag v$version"
    step "Cloning release tag v$version"
    git clone --depth 1 --branch "v$version" "$repository_url" "$source_root"
  else
    step "Cloning the latest Syncthing source from GitHub"
    git clone --depth 1 "$repository_url" "$source_root"
  fi
  step "Building Syncthing"
  (cd "$source_root" && go run build.go install syncthing)
  [[ -x $source_root/bin/syncthing ]] || fail \
    "The Git build produced no Syncthing executable"
}

activate_github() {
  local built_executable="$1" method="$2" version="$3" commit="$4"
  local install_root="$5" source_payload="$6" source_root="$7"
  local install_parent="" install_stage="" source_parent="" source_stage=""
  local old_install="" old_method="" old_source="" old_token=""
  local ownership_token=""

  ensure_github_change
  validate_github_paths "$source_root" "$install_root"

  if [[ -f $state_file ]]; then
    old_method="$(record_value method)"
    if [[ $old_method == release || $old_method == git ]]; then
      old_install="$(record_value installRoot)"
      old_source="$(record_value sourceRoot)"
      old_token="$(record_value ownershipToken)"
    fi
  fi
  if [[ -e $install_root && $install_root != "$old_install" ]]; then
    fail "Install path already exists: $install_root"
  fi
  if [[ -e $source_root && $source_root != "$old_source" ]]; then
    fail "Clone path already exists: $source_root"
  fi
  if [[ -n $old_install && -d $old_install ]]; then
    directory_is_owned "$old_install" "$old_token" || fail \
      "The previous install path lost its ownership marker"
  fi
  if [[ -n $old_source && -d $old_source ]]; then
    directory_is_owned "$old_source" "$old_token" || fail \
      "The previous source path lost its ownership marker"
  fi
  if [[ -n $old_install ]]; then
    ! paths_overlap "$install_root" "$old_source" || fail \
      "The new install path overlaps the previous source path"
    ! paths_overlap "$source_root" "$old_install" || fail \
      "The new clone path overlaps the previous install path"
    [[ $install_root == "$old_install" ]] ||
      ! paths_overlap "$install_root" "$old_install" || fail \
        "The new install path overlaps the previous install path"
    [[ $source_root == "$old_source" ]] ||
      ! paths_overlap "$source_root" "$old_source" || fail \
        "The new clone path overlaps the previous clone path"
  fi

  install_parent="$(dirname -- "$install_root")"
  source_parent="$(dirname -- "$source_root")"
  mkdir -p -- "$install_parent" "$source_parent"
  install_stage="$(mktemp -d \
    "$install_parent/.omarchy-syncthing-install.XXXXXX")"
  if ! source_stage="$(mktemp -d \
      "$source_parent/.omarchy-syncthing-source.XXXXXX")"; then
    rm -rf -- "$install_stage"
    fail "Could not stage the Syncthing source"
  fi
  ownership_token="$(date +%s%N)-$$-$RANDOM"
  if ! (
    install -m 755 -- "$built_executable" "$install_stage/syncthing"
    cp -a -- "$source_payload/." "$source_stage/"
    printf '%s\n' "$ownership_token" >"$install_stage/$owner_marker"
    printf '%s\n' "$ownership_token" >"$source_stage/$owner_marker"
    chmod 600 "$install_stage/$owner_marker" "$source_stage/$owner_marker"
  ); then
    rm -rf -- "$install_stage" "$source_stage"
    fail "Could not stage the new Syncthing installation"
  fi

  systemctl --user stop "$service_name" >/dev/null 2>&1 || true
  [[ -n $old_install ]] && rm -rf -- "$old_install"
  [[ -n $old_source ]] && rm -rf -- "$old_source"
  mv -T -- "$install_stage" "$install_root"
  mv -T -- "$source_stage" "$source_root"
  mkdir -p -- "$(dirname -- "$bin_link")"
  rm -f -- "$bin_link"
  ln -s -- "$install_root/syncthing" "$bin_link"
  write_user_service "$install_root/syncthing"
  write_record "$method" "$version" "$commit" "$install_root/syncthing" \
    "$install_root" "$source_root" "$ownership_token"
  systemctl --user daemon-reload
  systemctl --user enable --now "$service_name"
}

install_github() {
  local method="$1" version="$2" install_root="" source_root=""
  local commit="" temporary=""
  install_root="$(expand_path "$3")"
  source_root="$(expand_path "$4")"
  ensure_github_change
  validate_github_paths "$source_root" "$install_root"
  require_command git
  require_command go
  require_command jq
  temporary="$(mktemp -d)"
  trap 'rm -rf -- "$temporary"' EXIT
  build_source "$method" "$version" "$temporary/source"
  commit="$(git -C "$temporary/source" rev-parse HEAD)"
  activate_github "$temporary/source/bin/syncthing" "$method" "$version" \
    "$commit" "$install_root" "$temporary/source" "$source_root"
}

latest_release_version() {
  local tag=""
  tag="$(git ls-remote --tags --refs "$repository_url" |
    awk -F/ '$3 ~ /^v[0-9]+\.[0-9]+\.[0-9]+$/ {print $3}' |
    sort -V | tail -n 1)"
  tag="${tag#v}"
  validate_version "$tag"
  printf '%s\n' "$tag"
}

update_github() {
  local current="" install_root="" latest="" method="" remote=""
  local source_root=""

  [[ $(installation_state) == managed ]] || fail \
    "A healthy plugin-managed GitHub installation is required"
  method="$(record_value method)"
  install_root="$(record_value installRoot)"
  source_root="$(record_value sourceRoot)"
  case "$method" in
    release)
      current="$(record_value version)"
      latest="$(latest_release_version)"
      if [[ $(printf '%s\n%s\n' "$current" "$latest" | sort -V | tail -n 1) == "$current" ]]; then
        printf 'Pinned release v%s is already current.\n' "$current"
        return
      fi
      printf 'A newer official release is available: v%s\n' "$latest"
      install_github release "$latest" "$install_root" "$source_root"
      ;;
    git)
      current="$(record_value commit)"
      remote="$(git ls-remote "$repository_url" HEAD | awk '{print $1}')"
      [[ $remote =~ ^[0-9a-f]{40}$ ]] || fail \
        "Could not resolve the latest GitHub commit"
      if [[ $remote == "$current" ]]; then
        printf 'The GitHub checkout is already current.\n'
        return
      fi
      printf 'A newer GitHub commit is available.\n'
      install_github git latest "$install_root" "$source_root"
      ;;
    *) fail "Only GitHub-managed installations can update in place" ;;
  esac
}

uninstall_syncthing() {
  local source_root="" executable="" install_root="" method=""
  local ownership_token=""

  [[ $(installation_state) == managed ]] || fail \
    "This plugin does not own the current Syncthing installation"
  method="$(record_value method)"
  executable="$(record_value executable)"
  install_root="$(record_value installRoot)"
  source_root="$(record_value sourceRoot)"
  ownership_token="$(record_value ownershipToken)"

  if [[ $method == release || $method == git ]]; then
    validate_github_paths "$source_root" "$install_root"
    directory_is_owned "$install_root" "$ownership_token" || fail \
      "The install path is no longer owned by this plugin"
    directory_is_owned "$source_root" "$ownership_token" || fail \
      "The source path is no longer owned by this plugin"
    [[ $executable == "$install_root/syncthing" ]] || fail \
      "Refusing an unexpected executable path: $executable"
    [[ -f $service_file ]] || fail "The recorded user service is missing"
    grep -Fq -- "$executable" "$service_file" || fail \
      "The user service no longer belongs to this installation"
  fi

  step "Stopping and disabling the Syncthing user service"
  systemctl --user disable --now "$service_name" >/dev/null 2>&1 || true
  case "$method" in
    package)
      step "Removing the official package through Omarchy"
      omarchy pkg drop syncthing
      ;;
    release|git)
      rm -f -- "$service_file"
      rm -rf -- "$install_root"
      [[ -n $source_root ]] && rm -rf -- "$source_root"
      ;;
    *) fail "Unknown recorded installation method: $method" ;;
  esac
  if [[ -L $bin_link &&
        $(readlink -f -- "$bin_link" 2>/dev/null || true) == "$executable" ]]; then
    rm -f -- "$bin_link"
  fi
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
      install-release) install_github release "$1" "$2" "$3" ;;
      install-git) install_github git latest "$1" "$2" ;;
      update) update_github ;;
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
  install)
    method="${2:-}"
    case "$method" in
      package) launch_terminal install-package ;;
      release) launch_terminal install-release "${3:-}" "${4:-}" "${5:-}" ;;
      git) launch_terminal install-git "${3:-}" "${4:-}" ;;
      *) fail "usage: ${0##*/} install {package|release|git} [arguments]" ;;
    esac
    ;;
  update) launch_terminal update ;;
  uninstall) launch_terminal uninstall ;;
  run)
    shift
    run_and_prompt "$@"
    ;;
  *)
    fail "usage: ${0##*/} {status|install|update|uninstall}"
    exit 2
    ;;
esac
