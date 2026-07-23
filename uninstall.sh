#!/bin/sh
# Run on OpenWrt as root to remove service and scripts (keeps minieap package).

set -e
[ "$(id -u)" = "0" ] || { echo "root required"; exit 1; }

echo "==> stop service"
/etc/init.d/ruijie-minieap stop 2>/dev/null || true
/etc/init.d/ruijie-minieap disable 2>/dev/null || true
killall minieap 2>/dev/null || true

# remove net watchdog cron lines
if [ -f /etc/crontabs/root ]; then
  sed -i '/ruijie-net-watchdog/d' /etc/crontabs/root 2>/dev/null || true
  if [ -x /etc/init.d/cron ]; then
    /etc/init.d/cron restart 2>/dev/null || true
  fi
fi

rm -f /etc/init.d/ruijie-minieap
rm -f /usr/bin/ruijie-minieap-ctl
rm -f /usr/bin/ruijie-post-auth.sh
rm -f /usr/bin/ruijie-net-watchdog.sh
rm -f /etc/minieap.conf
# keep /etc/ruijie/env by default (secrets)
if [ "${REMOVE_ENV:-0}" = "1" ]; then
  rm -rf /etc/ruijie
  echo "removed /etc/ruijie"
else
  echo "kept /etc/ruijie/env (set REMOVE_ENV=1 to delete)"
fi

# keep persistent net log unless asked
if [ "${REMOVE_LOG:-0}" = "1" ]; then
  rm -f /overlay/ruijie-net.log
  echo "removed /overlay/ruijie-net.log"
else
  echo "kept /overlay/ruijie-net.log (set REMOVE_LOG=1 to delete)"
fi

echo "uninstall done (minieap package left installed)"
