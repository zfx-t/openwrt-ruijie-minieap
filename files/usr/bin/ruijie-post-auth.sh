#!/bin/sh
# Minimal post-auth: SOFT DHCP renew only.
# NEVER ifdown/ifup — that RELEASEs the lease and drops the WAN link
# (reboot failure: stuck on 172.23 isolation after auth success).
logger -t ruijie-minieap "post-auth: soft renew"
if command -v ubus >/dev/null 2>&1; then
  ubus call network.interface.wan renew 2>/dev/null || true
fi
for p in $(pidof udhcpc 2>/dev/null); do
  kill -USR1 "$p" 2>/dev/null || true
done
logger -t ruijie-minieap "post-auth: done"
exit 0
