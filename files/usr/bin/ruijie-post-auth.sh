#!/bin/sh
# Called by minieap after auth (dhcp-script). Refreshes OpenWrt WAN DHCP lease.
# Pre-auth IP is often an isolated subnet; without renew, traffic stays offline.

logger -t ruijie-minieap "post-auth: renew WAN DHCP"

# Prefer netifd renew; fall back to ifup
if command -v ubus >/dev/null 2>&1; then
  ubus call network.interface.wan renew 2>/dev/null \
    || ubus call network.interface.wan down 2>/dev/null
  sleep 1
  ubus call network.interface.wan up 2>/dev/null || true
fi

ifup wan 2>/dev/null || true

# Best-effort: signal udhcpc if present
for p in $(pidof udhcpc 2>/dev/null); do
  kill -USR1 "$p" 2>/dev/null || true
done

logger -t ruijie-minieap "post-auth: done"
exit 0
