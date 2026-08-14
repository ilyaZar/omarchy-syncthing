#!/usr/bin/env bash

set -uo pipefail

script_dir="$(dirname -- "$(realpath -- "${BASH_SOURCE[0]}")")"
picker_qml="$script_dir/folder-picker.qml"
picker_title="Choose a Syncthing folder"

float_picker() {
  local client address floating selector float_command place_command
  local stable=0

  for ((attempt = 0; attempt < 100; attempt++)); do
    client="$(
      hyprctl clients -j 2>/dev/null \
        | jq -r --arg title "$picker_title" \
          '[.[] | select(.title == $title or .initialTitle == $title)]
           | (.[-1] // {})
           | [(.address // ""), ((.floating // false) | tostring)]
           | @tsv' 2>/dev/null
    )"
    IFS=$'\t' read -r address floating <<< "$client"
    if [[ -n "$address" ]]; then
      selector="address:$address"
      float_command="hl.dispatch(hl.dsp.window.float({ action = \"float\", "
      float_command+="window = \"$selector\" }))"
      place_command="hl.dispatch(hl.dsp.window.resize({ x = 875, y = 600, "
      place_command+="relative = false, window = \"$selector\" })); "
      place_command+="hl.dispatch(hl.dsp.window.center({ window = \"$selector\" }))"
      if [[ "$floating" == "true" ]]; then
        hyprctl eval "$place_command" >/dev/null 2>&1 || true
        ((stable += 1))
        if ((stable >= 5)); then return; fi
      else
        stable=0
        hyprctl eval "$float_command" >/dev/null 2>&1 || true
      fi
    else
      stable=0
    fi
    sleep 0.1
  done
}

float_picker &
float_pid=$!
output="$(
  cd "$HOME" || exit 1
  env -u QT_QPA_PLATFORMTHEME QT_FORCE_STDERR_LOGGING=1 \
    qml6 -f "$picker_qml" 2>&1
)"
status=$?
kill "$float_pid" 2>/dev/null || true
wait "$float_pid" 2>/dev/null || true

while IFS= read -r line; do
  case "$line" in
    *SYNCTHING_FOLDER=*)
      printf '%s\n' "${line#*SYNCTHING_FOLDER=}"
      ;;
  esac
done <<< "$output"

exit "$status"
