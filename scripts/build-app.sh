#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
exec ../StatusItemKit/scripts/make-app.sh BatteryTime "Battery Time"
