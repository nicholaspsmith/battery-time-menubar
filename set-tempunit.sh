#!/usr/bin/env bash
# set-tempunit.sh <C|F> — persist the dropdown temperature unit for battery-time.
# Called by the plugin's "Switch to °F / °C" dropdown item.
set -eu
dir="$HOME/.config/battery-time"
mkdir -p "$dir"
case "${1:-}" in
  C|F) printf '%s\n' "$1" > "$dir/tempunit" ;;
  *)   echo "usage: $0 <C|F>" >&2; exit 1 ;;
esac
