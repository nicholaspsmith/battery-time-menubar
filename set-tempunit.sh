#!/usr/bin/env bash
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
#
# Copyright (c) 2026 Nicholas Smith

# set-tempunit.sh <C|F> — persist the dropdown temperature unit for battery-time.
# Called by the plugin's "Switch to °F / °C" dropdown item.
set -eu
dir="$HOME/.config/battery-time"
mkdir -p "$dir"
case "${1:-}" in
  C|F) printf '%s\n' "$1" > "$dir/tempunit" ;;
  *)   echo "usage: $0 <C|F>" >&2; exit 1 ;;
esac
