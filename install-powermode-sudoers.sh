#!/usr/bin/env bash
# install-powermode-sudoers.sh
# Run with sudo:  sudo ./install-powermode-sudoers.sh
#
# Installs a tightly-scoped passwordless-sudo rule so battery-time's dropdown can
# toggle Low Power <-> Automatic energy mode without a password prompt. The rule
# permits ONLY the four exact pmset commands the toggle uses and nothing else.
set -euo pipefail

if [ "$(id -u)" -ne 0 ]; then
  echo "Please run with sudo:  sudo $0" >&2
  exit 1
fi

USER_NAME="${SUDO_USER:-$(logname)}"
DEST="/etc/sudoers.d/battery-time-powermode"
TMP="$(mktemp)"

cat > "$TMP" <<EOF
# battery-time-menubar: let $USER_NAME toggle Low Power / Automatic energy mode
# without a password. Scoped to exactly these commands.
$USER_NAME ALL=(root) NOPASSWD: /usr/bin/pmset -b powermode 0, /usr/bin/pmset -b powermode 1, /usr/bin/pmset -b powermode 2, /usr/bin/pmset -c powermode 0, /usr/bin/pmset -c powermode 1, /usr/bin/pmset -c powermode 2
EOF

# Validate syntax before installing so a typo can never break sudo.
visudo -cf "$TMP"
install -m 0440 -o root -g wheel "$TMP" "$DEST"
rm -f "$TMP"
echo "Installed and validated $DEST"
