#!/bin/sh
# Ruijie drop detection + recover (minieap + post-auth DHCP)
# Persist forensics to overlay so reboot does not wipe evidence.
#
# Usage:
#   ruijie-net-watchdog.sh once      # cron: check + recover if offline
#   ruijie-net-watchdog.sh loop      # foreground loop
#   ruijie-net-watchdog.sh snapshot  # dump status into log
#   ruijie-net-watchdog.sh harvest   # append logread excerpts to log

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
  # keep ~200KB
  [ -f "$LOG_FILE" ] || return 0
  sz=$(wc -c < "$LOG_FILE" 2>/dev/null || echo 0)
  if [ "$sz" -gt 200000 ] 2>/dev/null; then
    tail -c 150000 "$LOG_FILE" > "$LOG_FILE.tmp" 2>/dev/null && mv "$LOG_FILE.tmp" "$LOG_FILE"
  fi
}

is_online() {
  if command -v curl >/dev/null 2>&1; then
    code=$(curl -sS -m 5 -o /dev/null -w '%{http_code}' \
      "http://connect.rom.miui.com/generate_204" 2>/dev/null || echo 000)
    [ "$code" = "204" ] || [ "$code" = "200" ] && return 0
  fi
  ping -c 1 -W 3 "$PING_HOST" >/dev/null 2>&1
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
  log "offline -> recover: snapshot + restart minieap + post-auth"
  snapshot
  if [ -x /etc/init.d/ruijie-minieap ]; then
    /etc/init.d/ruijie-minieap restart 2>/dev/null || true
  else
    killall minieap 2>/dev/null || true
  fi
  sleep 8
  if [ -x /usr/bin/ruijie-post-auth.sh ]; then
    /usr/bin/ruijie-post-auth.sh 2>/dev/null || true
  fi
  sleep 5
  if is_online; then
    log "recover success"
    echo "online $(date)" > "$STATE_FILE"
    return 0
  fi
  log "recover still offline -> second post-auth"
  if [ -x /usr/bin/ruijie-post-auth.sh ]; then
    /usr/bin/ruijie-post-auth.sh 2>/dev/null || true
  fi
  sleep 5
  if is_online; then
    log "recover success (2nd post-auth)"
    echo "online $(date)" > "$STATE_FILE"
    return 0
  fi
  log "recover failed"
  snapshot
  echo "offline $(date)" > "$STATE_FILE"
  return 1
}

once() {
  trim_log
  if is_online; then
    prev=$(cat "$STATE_FILE" 2>/dev/null || echo "")
    case "$prev" in
      online*) ;;
      *) log "ok online"; echo "online $(date)" > "$STATE_FILE" ;;
    esac
    wan=$(ip -4 -o addr show wan 2>/dev/null | awk '{print $4}' | head -1)
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ok online wan=$wan" >> "$LOG_FILE" 2>/dev/null || true
    return 0
  fi
  log "detected offline"
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
      sleep "${RUIJIE_PING_INTERVAL:-60}"
    done
    ;;
  snapshot) snapshot ;;
  harvest) log_snapshot_cron ;;
  *) echo "usage: $0 {once|loop|snapshot|harvest}"; exit 2 ;;
esac
