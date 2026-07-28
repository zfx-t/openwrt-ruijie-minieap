#!/bin/sh
# Ruijie drop detection + soft recover (no full reauth thrash).
#
# Usage:
#   ruijie-net-watchdog.sh once      # cron: check + soft recover if offline
#   ruijie-net-watchdog.sh loop
#   ruijie-net-watchdog.sh snapshot
#   ruijie-net-watchdog.sh harvest
#
# Recover policy (stable):
#   1) if minieap dead -> service start only
#   2) soft post-auth (ubus renew, never ifdown)
#   3) at most one service restart + soft post-auth
#   Never call ruijie-reauth in a 2-minute loop (that caused exit storms).

LOG_FILE="${RUIJIE_NET_LOG:-/overlay/ruijie-net.log}"
STATE_DIR="/tmp/ruijie-watch"
STATE_FILE="$STATE_DIR/last"
PING_HOST="${RUIJIE_PING_HOST:-223.5.5.5}"
TAG="ruijie-net-watch"

mkdir -p "$STATE_DIR" 2>/dev/null || true

log() {
  ts=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null || date)
  line="[$ts] [$TAG] $*"
  logger -t "$TAG" "$*"
  echo "$line" >> "$LOG_FILE" 2>/dev/null || true
}

trim_log() {
  [ -f "$LOG_FILE" ] || return 0
  sz=$(wc -c < "$LOG_FILE" 2>/dev/null || echo 0)
  if [ "$sz" -gt 200000 ] 2>/dev/null; then
    tail -c 150000 "$LOG_FILE" > "$LOG_FILE.tmp" 2>/dev/null && mv "$LOG_FILE.tmp" "$LOG_FILE"
  fi
}

wan_ip() {
  ip -4 -o addr show wan 2>/dev/null | awk '{print $4}' | head -1
}

is_online() {
  if command -v curl >/dev/null 2>&1; then
    code=$(curl -4 -sS -m 5 -o /dev/null -w '%{http_code}' \
      "http://connect.rom.miui.com/generate_204" 2>/dev/null || echo 000)
    [ "$code" = "204" ] || [ "$code" = "200" ] || return 1
    ip route | grep -q '^default ' || return 1
    return 0
  fi
  ping -c 1 -W 3 "$PING_HOST" >/dev/null 2>&1
}

minieap_running() {
  pidof minieap >/dev/null 2>&1
}

soft_post_auth() {
  [ -x /usr/bin/ruijie-post-auth.sh ] && /usr/bin/ruijie-post-auth.sh 2>/dev/null || true
}

ensure_minieap() {
  if minieap_running; then
    return 0
  fi
  log "minieap not running -> start service only"
  if [ -x /etc/init.d/ruijie-minieap ]; then
    /etc/init.d/ruijie-minieap start 2>/dev/null || true
  fi
  sleep 8
  soft_post_auth
}

snapshot() {
  log "=== snapshot begin ==="
  {
    echo "date: $(date 2>/dev/null || true)"
    echo "uptime: $(cat /proc/uptime 2>/dev/null)"
    echo "--- status ---"
    if [ -x /usr/bin/ruijie-minieap-ctl ]; then
      ruijie-minieap-ctl status 2>/dev/null || true
    fi
    echo "--- ip ---"
    ip -4 addr show wan 2>/dev/null || true
    echo "--- route ---"
    ip route 2>/dev/null || true
    echo "--- ps ---"
    ps w 2>/dev/null | grep -E 'minieap|ruijie' | grep -v grep || true
    echo "--- logread tail ---"
    logread 2>/dev/null | grep -iE 'ruijie-minieap|ruijie-net-watch|minieap|netifd: wan|udhcpc' | tail -40 || true
  } >> "$LOG_FILE" 2>/dev/null || true
  log "=== snapshot end ==="
  trim_log
}

recover() {
  log "offline -> soft recover (no reauth thrash) wan=$(wan_ip)"
  snapshot
  ensure_minieap
  sleep 4
  soft_post_auth
  sleep 5
  if is_online; then
    log "recover success soft"
    echo "online $(date)" > "$STATE_FILE"
    return 0
  fi
  log "still offline -> one service restart + soft post-auth"
  if [ -x /etc/init.d/ruijie-minieap ]; then
    /etc/init.d/ruijie-minieap restart 2>/dev/null || true
  fi
  sleep 12
  soft_post_auth
  sleep 5
  if is_online; then
    log "recover success after restart"
    echo "online $(date)" > "$STATE_FILE"
    return 0
  fi
  log "recover failed wan=$(wan_ip)"
  snapshot
  echo "offline $(date)" > "$STATE_FILE"
  return 1
}

once() {
  trim_log
  wan=$(wan_ip)
  if is_online; then
    prev=$(cat "$STATE_FILE" 2>/dev/null || echo "")
    case "$prev" in
      online*) ;;
      *) log "ok online wan=$wan" ;;
    esac
    echo "online $(date)" > "$STATE_FILE"
    # process died but net still ok -> restart keepalive only
    minieap_running || ensure_minieap
    return 0
  fi
  log "detected offline wan=$wan"
  recover
}

log_snapshot_cron() {
  {
    echo "----- log harvest $(date) -----"
    logread 2>/dev/null | grep -iE 'ruijie-minieap|ruijie-net-watch|minieap|netifd: wan|udhcpc|Link is' | tail -80
  } >> "$LOG_FILE" 2>/dev/null || true
  trim_log
}

case "${1:-once}" in
  once) once ;;
  loop)
    while true; do
      once || true
      sleep "${RUIJIE_PING_INTERVAL:-120}"
    done
    ;;
  snapshot) snapshot ;;
  harvest) log_snapshot_cron ;;
  *) echo "usage: $0 {once|loop|snapshot|harvest}"; exit 2 ;;
esac
