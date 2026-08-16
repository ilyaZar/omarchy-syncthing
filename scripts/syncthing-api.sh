#!/bin/bash

set -euo pipefail

curl_args=(
  --silent
  --insecure
  --noproxy "*"
  --request "$1"
  --header "Accept: application/json"
  --write-out $'\n%{http_code}'
)

if (( $# == 3 )); then
  curl_args+=(
    --header "Content-Type: application/json"
    --data-binary "$3"
  )
fi

printf 'header = "X-API-Key: %s"\n' "$SYNCTHING_API_KEY" |
  curl --config - "${curl_args[@]}" "$2"
