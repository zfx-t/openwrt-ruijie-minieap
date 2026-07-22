#!/bin/sh
# Run on OpenWrt as root to remove service and scripts (keeps minieap package).

set -e
[ "$(id -u)" = "0" ] || { echo "root required"; exit 1; }

echo "==> stop service"
/etc/init.d/ruijie-minieap stop 2>/dev/null || true
/etc/init.d/ruijie-minieap disable 2>/dev/null || true
killall minieap 2>/dev/null || true

rm -f /etc/init.d/ruijie-minieap
rm -f /usr/bin/ruijie-minieap-ctl
rm -f /etc/minieap.conf
# keep /etc/ruijie/env by default (secrets)
if [ "${REMOVE_ENV:-0}" = "1" ]; then
  rm -rf /etc/ruijie
  echo "removed /etc/ruijie"
else
  echo "kept /etc/ruijie/env (set REMOVE_ENV=1 to delete)"
fi

echo "uninstall done (minieap package left installed)"
