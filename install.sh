#!/usr/bin/env bash
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
#
# Copyright (c) 2026 Nicholas Smith

# Install battery-time: build the standalone "Battery Time.app", symlink it into
# ~/Applications, ask about Start at Login, and (re)launch it.
# Optional: `./install.sh --swiftbar` instead wires the retired SwiftBar plugin
# and its power-watch launchd agent (see README).
set -euo pipefail

# Menumon release rule — every push is a release. Arm the pre-push hook in
# every Menumon repo cloned beside this one (local git config, so a fresh
# clone has none until this runs). StatusItemKit README, "Releases".
RELEASE_KIT="$(cd "$(dirname "$0")/.." && pwd)/StatusItemKit/scripts/release/adopt.sh"
if [ -x "$RELEASE_KIT" ]; then
    "$RELEASE_KIT" --hooks-only || echo "Release hook: adopt.sh failed" >&2
else
    echo "Release hook: StatusItemKit not found beside this repo — clone it and re-run" >&2
fi

SRC_DIR="$(cd "$(dirname "$0")" && pwd)"
LABEL="com.nicholassmith.battery-time-power-watch"
PLUGIN_DIR="${SWIFTBAR_PLUGIN_DIR:-$HOME/.config/SwiftBar}"

if [[ "${1:-}" == "--swiftbar" ]]; then
    # --- retired SwiftBar plugin (opt-in) ---
    chmod +x "$SRC_DIR/battery-time.5s.sh" "$SRC_DIR/set-tempunit.sh" "$SRC_DIR/show-tips.sh" "$SRC_DIR/set-display.sh"
    mkdir -p "$PLUGIN_DIR"
    rm -f "$PLUGIN_DIR/battery-time.30s.sh" "$PLUGIN_DIR/battery-time.sh"  # prior installs
    rm -f "$HOME/Library/Caches/battery-time-24h.cache"                   # regenerate w/ current fields
    ln -sf "$SRC_DIR/battery-time.5s.sh" "$PLUGIN_DIR/battery-time.5s.sh"
    echo "Linked plugin -> $PLUGIN_DIR/battery-time.5s.sh"

    # --- compile the menu-bar image renderer (optional; plugin falls back to text) ---
    if command -v swiftc >/dev/null 2>&1; then
      mkdir -p "$SRC_DIR/bin"
      if swiftc -O "$SRC_DIR/render-title.swift" -o "$SRC_DIR/bin/render-title" 2>/dev/null; then
        echo "Compiled menu-bar image renderer (tight spacing)."
      else
        echo "WARNING: render-title.swift failed to compile; menu bar uses the wider text form."
      fi
    else
      echo "NOTE: swiftc not found; menu bar uses the wider text form. Install Xcode CLT for tight rendering."
    fi

    # --- power-watch launchd agent ---
    WATCH="$SRC_DIR/power-watch.sh"
    LOG="$HOME/Library/Logs/battery-time-power-watch.log"
    LA="$HOME/Library/LaunchAgents"
    PLIST="$LA/$LABEL.plist"
    chmod +x "$WATCH"
    mkdir -p "$LA"
    sed -e "s|__WATCH_SCRIPT__|$WATCH|g" -e "s|__LOG__|$LOG|g" "$SRC_DIR/$LABEL.plist" > "$PLIST"
    launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$PLIST" 2>/dev/null || launchctl load -w "$PLIST"
    echo "Loaded launchd agent $LABEL (instant plug/unplug refresh)."
    echo "Reload SwiftBar to pick up the plugin (or it refreshes within 5s)."
else
    # --- standalone app ---
    APP_NAME="Battery Time.app"
    "$SRC_DIR/scripts/build-app.sh"
    mkdir -p "$HOME/Applications"
    ln -sfn "$SRC_DIR/build/$APP_NAME" "$HOME/Applications/$APP_NAME"
    echo "Linked $HOME/Applications/$APP_NAME -> $SRC_DIR/build/$APP_NAME"

    # The app watches power sources in-process, so retire the plugin's pieces.
    if [ -L "$PLUGIN_DIR/battery-time.5s.sh" ]; then
        rm -f "$PLUGIN_DIR/battery-time.5s.sh"
        echo "Removed the retired SwiftBar plugin link."
    fi
    if [ -f "$HOME/Library/LaunchAgents/$LABEL.plist" ]; then
        launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null || true
        rm -f "$HOME/Library/LaunchAgents/$LABEL.plist"
        echo "Retired the $LABEL launchd agent."
    fi

    # Ask to turn on Start at Login. SMAppService can only register the calling
    # process's own bundle, so this runs the installed binary's headless --login.
    APP="$HOME/Applications/$APP_NAME"
    BIN="$APP/Contents/MacOS/BatteryTime"
    PROC="${APP##*/}/Contents/MacOS/BatteryTime"   # matches the symlink-resolved path too
    if [ "$("$BIN" --login status 2>/dev/null)" = "on" ]; then
        echo "Start at Login: already on"
    elif [ -t 0 ]; then
        read -r -p "Start Battery Time at login? [Y/n] " answer
        case "$answer" in
            [nN]*) echo "Start at Login: left off (turn it on from the menu)" ;;
            *) if "$BIN" --login on >/dev/null; then
                   echo "Start at Login: on"
               else
                   echo "Start at Login: could not register (turn it on from the menu)" >&2
               fi ;;
        esac
    else
        echo "Start at Login: off (not asked: no terminal). Turn it on from the menu, or run"
        echo "    \"$BIN\" --login on"
    fi

    # `open` on a running app only activates it, so quit the old build first or the
    # new one never launches. Wait for it to go so both don't briefly sit in the bar.
    if pgrep -f "$PROC" >/dev/null; then
        osascript -e "tell application id \"$(defaults read "$APP/Contents/Info" CFBundleIdentifier)\" to quit" >/dev/null 2>&1 || true
        for _ in 1 2 3 4 5 6 7 8 9 10; do pgrep -f "$PROC" >/dev/null || break; sleep 0.5; done
        pkill -f "$PROC" 2>/dev/null || true
        sleep 1
    fi
    /usr/bin/open "$APP"
    echo "Battery Time is running in the menu bar."
fi

# --- Low Power Mode toggle: one-time passwordless-sudo rule ---
if [ ! -f /etc/sudoers.d/battery-time-powermode ]; then
  echo "NOTE: the dropdown's Low Power Mode toggle needs a one-time setup:"
  echo "    sudo $SRC_DIR/install-powermode-sudoers.sh"
fi

