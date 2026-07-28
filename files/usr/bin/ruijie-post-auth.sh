#!/bin/sh
# Soft WAN DHCP renew after 802.1x success.
# Pre-auth isolation IP (e.g. 172.23.x) -> formal campus IP (e.g. 172.20.x).
#
# IMPORTANT: never ifdown/ifup or flap the link here.
# Hard renew races with udhcpc and can RELEASE a good 172.20 lease back to 172.23,
# and can kill the minieap 802.1x session.
#
# Optional (discouraged): RUIJIE_POST_AUTH_HARD=1 enables ifdown/ifup.

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

log "post-auth SOFT renew ip_before=$(wan_ip)"

# 1) Soft renew via netifd (does not tear down L2 / 802.1x)
if command -v ubus >/dev/null 2>&1; then
  ubus call network.interface.wan renew 2>/dev/null || true
fi

# 2) Signal udhcpc (USR1 = renew)
for p in $(pidof udhcpc 2>/dev/null); do
  kill -USR1 "$p" 2>/dev/null || true
done

sleep 2

# 3) Hard path only if explicitly requested (may disturb 802.1x)
if [ "$HARD" = "1" ]; then
  log "post-auth HARD renew (ifdown/ifup) — may disturb 802.1x / drop lease"
  if command -v ubus >/dev/null 2>&1; then
    ubus call network.interface.wan down 2>/dev/null || true
    sleep 1
    ubus call network.interface.wan up 2>/dev/null || true
  fi
  ifdown wan 2>/dev/null || true
  sleep 1
  ifup wan 2>/dev/null || true
  sleep 2
  if command -v ubus >/dev/null 2>&1; then
    ubus call network.interface.wan renew 2>/dev/null || true
  fi
  for p in $(pidof udhcpc 2>/dev/null); do
    kill -USR1 "$p" 2>/dev/null || true
  done
fi

log "post-auth SOFT done ip_after=$(wan_ip)"
exit 0
