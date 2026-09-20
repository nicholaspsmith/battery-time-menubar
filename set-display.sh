#!/usr/bin/env bash
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
#
# Copyright (c) 2026 Nicholas Smith

# set-display.sh <icon|pct|time> — toggle a menu-bar display element on/off.
# Called by the dropdown's "Menu bar shows..." items. Defaults: icon=1 pct=0 time=1.
set -eu
case "${1:-}" in icon|pct|time) ;; *) echo "usage: $0 <icon|pct|time>" >&2; exit 1 ;; esac
dir="$HOME/.config/battery-time"; mkdir -p "$dir"
f="$dir/$1"
cur="$(cat "$f" 2>/dev/null || true)"
if [ -z "$cur" ]; then case "$1" in pct) cur=0 ;; *) cur=1 ;; esac; fi
if [ "$cur" = 1 ]; then printf '0\n' > "$f"; else printf '1\n' > "$f"; fi
