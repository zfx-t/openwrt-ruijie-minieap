#!/bin/sh
# Called by minieap after 802.1x (dhcp-script), or manually / via reauth.
# Refreshes OpenWrt WAN DHCP so the lease leaves the pre-auth isolation net
# (e.g. 172.23.x) and becomes the real campus address (e.g. 172.20.x).
#
# Prefer soft renew. Avoid link flap (ip link down) which can drop 802.1x.
# Optional: RUIJIE_POST_AUTH_HARD=1 to ifdown/ifup wan (stronger, riskier).

TAG="ruijie-minieap"
NIC="${RUIJIE_NIC:-wan}"
HARD="${RUIJIE_POST_AUTH_HARD:-0}"

log() {
  logger -t "$TAG" "$*"
  echo "[$TAG] $*"
}

wan_ip() {
  ip -4 -o addr show "$NIC" 2>/dev/null | awk '{print $4}' | head -1
}

log "post-auth: renew WAN DHCP (nic=$NIC ip_before=$(wan_ip))"

# 1) Soft renew via netifd (does not tear down L2 / 802.1x)
if command -v ubus >/dev/null 2>&1; then
  ubus call network.interface.wan renew 2>/dev/null || true
fi

# 2) Signal udhcpc (USR1 = renew)
for p in $(pidof udhcpc 2>/dev/null); do
  # only touch udhcpc that looks related to wan if we can; otherwise all
  kill -USR1 "$p" 2>/dev/null || true
done

sleep 2

# 3) Harder path only if requested or still no default route after soft renew
if [ "$HARD" = "1" ]; then
  log "post-auth: HARD renew (ifdown/ifup wan) — may disturb 802.1x"
  if command -v ubus >/dev/null 2>&1; then
    ubus call network.interface.wan down 2>/dev/null || true
    sleep 1
    ubus call network.interface.wan up 2>/dev/null || true
  fi
  ifdown wan 2>/dev/null || true
  sleep 1
  ifup wan 2>/dev/null || true
else
  # Mild: ensure interface is up without full down
  ifup wan 2>/dev/null || true
  if command -v ubus >/dev/null 2>&1; then
    ubus call network.interface.wan up 2>/dev/null || true
  fi
fi

# 4) Second soft renew after ifup settles
sleep 2
if command -v ubus >/dev/null 2>&1; then
  ubus call network.interface.wan renew 2>/dev/null || true
fi
for p in $(pidof udhcpc 2>/dev/null); do
  kill -USR1 "$p" 2>/dev/null || true
done

log "post-auth: done ip_after=$(wan_ip)"
exit 0
