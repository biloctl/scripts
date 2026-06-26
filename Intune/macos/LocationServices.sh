#!/bin/bash
# Minimal enable Location Services (macOS)

PLIST_DIR="/var/db/locationd/Library/Preferences/ByHost"
PLIST="${PLIST_DIR}/com.apple.locationd"
UUID="$(/usr/sbin/system_profiler SPHardwareDataType 2>/dev/null | awk -F': ' '/Hardware UUID/ {print $2; exit}')"

# 1) Write generic key
/usr/bin/defaults write "${PLIST}" LocationServicesEnabled -bool true

# 2) Write UUID-scoped key if available
if [ -n "$UUID" ]; then
  /usr/bin/defaults write "${PLIST}.${UUID}" LocationServicesEnabled -bool true
fi

# 3) Ensure ownership so locationd will read it
/usr/sbin/chown -R _locationd:wheel /var/db/locationd

# 4) Try to apply without reboot (some OS versions still need a reboot)
if ! /bin/launchctl kickstart -k system/com.apple.locationd 2>/dev/null; then
  echo "locationd restart failed; a reboot may be required."
fi
