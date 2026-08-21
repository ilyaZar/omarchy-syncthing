#!/bin/bash
set -euo pipefail

usage() {
  printf 'Usage: syncthing-theme.sh generate <gui-assets-dir> [colors.toml]\n' >&2
  exit 2
}

[[ ${1:-} == "generate" && ( $# == 2 || $# == 3 ) ]] || usage

assets_root=$2
colors_file=${3:-}
theme_dir="$assets_root/syncthing-omarchy/assets/css"

declare -A colors=()
if [[ -n $colors_file ]]; then
  color_command=(omarchy-theme-color --file "$colors_file" --all)
else
  color_command=(omarchy-theme-color --all)
fi
while IFS=$'\t' read -r key value; do
  [[ $key =~ ^[A-Za-z0-9_-]+$ ]] || continue
  [[ $value =~ ^#[0-9A-Fa-f]{6}$|^(dark|light)$ ]] || continue
  colors[$key]=$value
done < <("${color_command[@]}")

required=(
  background foreground accent muted selection
  lighter_background darker_background dark_foreground light_foreground
  red yellow green cyan blue magenta orange
)
for key in "${required[@]}"; do
  [[ -n ${colors[$key]:-} ]] || {
    printf 'Omarchy theme is missing the resolved color %s\n' "$key" >&2
    exit 1
  }
done

mkdir -p -- "$theme_dir"
wrapper_tmp=$(mktemp --tmpdir="$theme_dir" .theme.css.XXXXXX)
palette_tmp=$(mktemp --tmpdir="$theme_dir" .omarchy-theme.css.XXXXXX)
trap 'rm -f -- "$wrapper_tmp" "$palette_tmp"' EXIT

printf '%s\n' \
  '@import "/theme-assets/default/assets/css/theme.css";' \
  '@import "omarchy_syncthing_theme.css";' >"$wrapper_tmp"

sed \
  -e "s/{{background}}/${colors[background]}/g" \
  -e "s/{{foreground}}/${colors[foreground]}/g" \
  -e "s/{{accent}}/${colors[accent]}/g" \
  -e "s/{{muted}}/${colors[muted]}/g" \
  -e "s/{{selection}}/${colors[selection]}/g" \
  -e "s/{{surface}}/${colors[lighter_background]}/g" \
  -e "s/{{surface_dark}}/${colors[darker_background]}/g" \
  -e "s/{{foreground_dark}}/${colors[dark_foreground]}/g" \
  -e "s/{{foreground_light}}/${colors[light_foreground]}/g" \
  -e "s/{{red}}/${colors[red]}/g" \
  -e "s/{{yellow}}/${colors[yellow]}/g" \
  -e "s/{{green}}/${colors[green]}/g" \
  -e "s/{{cyan}}/${colors[cyan]}/g" \
  -e "s/{{blue}}/${colors[blue]}/g" \
  -e "s/{{magenta}}/${colors[magenta]}/g" \
  -e "s/{{orange}}/${colors[orange]}/g" \
  "$(dirname -- "$0")/../webui/omarchy_syncthing_theme.css" \
  >"$palette_tmp"

grep -q '{{' "$palette_tmp" && {
  printf 'Generated Syncthing theme contains unresolved colors\n' >&2
  exit 1
}

chmod 644 -- "$wrapper_tmp" "$palette_tmp"
mv -- "$wrapper_tmp" "$theme_dir/theme.css"
mv -- "$palette_tmp" "$theme_dir/omarchy_syncthing_theme.css"
trap - EXIT

printf '%s\n' "$theme_dir"
