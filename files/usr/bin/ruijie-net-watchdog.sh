#!/bin/sh
LOG_FILE="${RUIJIE_NET_LOG:-/overlay/ruijie-net.log}"
STATE_DIR="/tmp/ruijie-watch"
STATE_FILE="$STATE_DIR/last"
TAG="ruijie-net-watch"
mkdir -p "$STATE_DIR" 2>/dev/null || true
log(){ ts=$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null||date); line="[$ts] [$TAG] $*"; logger -t "$TAG" "$*"; echo "$line" >>"$LOG_FILE" 2>/dev/null||true; }
trim_log(){ [ -f "$LOG_FILE" ]||return 0; sz=$(wc -c <"$LOG_FILE" 2>/dev/null||echo 0); [ "$sz" -gt 200000 ] 2>/dev/null && tail -c 150000 "$LOG_FILE" >"$LOG_FILE.tmp" 2>/dev/null && mv "$LOG_FILE.tmp" "$LOG_FILE"; }
wan_ip(){ ip -4 -o addr show wan 2>/dev/null|awk '{print $4}'|head -1; }
is_online(){
  code=$(curl -4 -sS -m 5 -o /dev/null -w '%{http_code}' http://connect.rom.miui.com/generate_204 2>/dev/null||echo 000)
  [ "$code" = "204" ] || [ "$code" = "200" ] && return 0
  ping -c 1 -W 3 223.5.5.5 >/dev/null 2>&1
}
soft_post(){ [ -x /usr/bin/ruijie-post-auth.sh ] && /usr/bin/ruijie-post-auth.sh 2>/dev/null||true; }
once(){
  trim_log
  wan=$(wan_ip)
  if is_online; then
    log "ok online wan=$wan"
    echo "online $(date)" >"$STATE_FILE"
    pidof minieap >/dev/null 2>&1 || /etc/init.d/ruijie-minieap start 2>/dev/null || true
    return 0
  fi
  log "offline wan=$wan -> soft recover"
  pidof minieap >/dev/null 2>&1 || /etc/init.d/ruijie-minieap start 2>/dev/null || true
  sleep 8
  soft_post
  sleep 6
  if is_online; then log "recover success"; echo "online $(date)" >"$STATE_FILE"; return 0; fi
  # one restart only
  /etc/init.d/ruijie-minieap restart 2>/dev/null || true
  sleep 12
  soft_post
  sleep 6
  if is_online; then log "recover success after restart"; echo "online $(date)" >"$STATE_FILE"; return 0; fi
  log "recover failed wan=$(wan_ip)"
  echo "offline $(date)" >"$STATE_FILE"
  return 1
}
case "${1:-once}" in
  once) once ;;
  loop) while true; do once||true; sleep 120; done ;;
  snapshot) log "snapshot"; { date; ip -4 addr show wan; ip route; ps w|grep minieap|grep -v grep; tail -15 /var/log/minieap.log; } >>"$LOG_FILE" 2>/dev/null ;;
  harvest) { echo "----- harvest $(date) -----"; logread 2>/dev/null|grep -iE 'minieap|ruijie|udhcpc|netifd: wan'|tail -40; } >>"$LOG_FILE" 2>/dev/null; trim_log ;;
  *) echo "usage: $0 {once|loop|snapshot|harvest}"; exit 2 ;;
esac
