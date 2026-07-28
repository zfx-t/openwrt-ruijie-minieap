#!/usr/bin/env bash
# Deploy this repo FROM a PC to an OpenWrt router over SSH.
#
# Usage:
#   cp .env.example .env   # fill credentials + ROUTER=
#   ./deploy.sh
#   ./deploy.sh --verify
#
# Or:
#   ROUTER=192.168.3.1 SSH_USER=root RUIJIE_USERNAME=... RUIJIE_PASSWORD=... ./deploy.sh --verify

set -euo pipefail
ROOT=$(cd "$(dirname "$0")" && pwd)
cd "$ROOT"

if [ -f .env ]; then
  set -a
  # shellcheck disable=SC1091
  source .env
  set +a
fi

ROUTER="${ROUTER:-192.168.1.1}"
SSH_USER="${SSH_USER:-root}"
SSH_PORT="${SSH_PORT:-22}"
SSH_TARGET="${SSH_USER}@${ROUTER}"
VERIFY=0
START=1

while [ $# -gt 0 ]; do
  case "$1" in
    --verify) VERIFY=1; shift ;;
    --no-start) START=0; shift ;;
    -h|--help) echo "usage: $0 [--verify] [--no-start]"; exit 0 ;;
    *) echo "unknown: $1"; exit 2 ;;
  esac
done

SSH_OPTS=(-p "$SSH_PORT" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10)
SCP_OPTS=(-P "$SSH_PORT" -o StrictHostKeyChecking=accept-new)

ssh_cmd() {
  if [ -n "${SSH_PASS:-}" ] && command -v sshpass >/dev/null 2>&1; then
    sshpass -p "$SSH_PASS" ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "$@"
  else
    ssh "${SSH_OPTS[@]}" "$SSH_TARGET" "$@"
  fi
}

scp_cmd() {
  if [ -n "${SSH_PASS:-}" ] && command -v sshpass >/dev/null 2>&1; then
    sshpass -p "$SSH_PASS" scp "${SCP_OPTS[@]}" "$@"
  else
    scp "${SCP_OPTS[@]}" "$@"
  fi
}

# Prefer legacy scp on OpenWrt without sftp-server
if scp -O 2>&1 | grep -q 'legacy'; then
  SCP_OPTS+=(-O)
fi

echo "==> target $SSH_TARGET:$SSH_PORT"

# build remote env if credentials provided
TMP_ENV=$(mktemp)
if [ -f .env ]; then
  # only RUIJIE_* and MINIEAP_* lines
  grep -E '^(RUIJIE_|MINIEAP_)' .env > "$TMP_ENV" || true
fi
if [ -n "${RUIJIE_USERNAME:-}" ]; then
  cat > "$TMP_ENV" <<EOF
RUIJIE_USERNAME="$RUIJIE_USERNAME"
RUIJIE_PASSWORD="$RUIJIE_PASSWORD"
RUIJIE_NIC="${RUIJIE_NIC:-wan}"
RUIJIE_EAP_BCAST="${RUIJIE_EAP_BCAST:-1}"
RUIJIE_DHCP_TYPE="${RUIJIE_DHCP_TYPE:-2}"
RUIJIE_SERVICE="${RUIJIE_SERVICE:-internet}"
RUIJIE_VERSION_STR="${RUIJIE_VERSION_STR:-RG-SU For Linux V1.31}"
RUIJIE_FAKE_SERIAL="${RUIJIE_FAKE_SERIAL:-OPENWRT-001}"
RUIJIE_HEARTBEAT="${RUIJIE_HEARTBEAT:-60}"
RUIJIE_MODULE="${RUIJIE_MODULE:-rjv3}"
MINIEAP_IPK_URL="${MINIEAP_IPK_URL:-}"
EOF
fi

ssh_cmd "mkdir -p /tmp/ruijie-minieap-src /etc/ruijie"

# tar stream (works without sftp)
tar cf - \
  install.sh uninstall.sh \
  files/usr/bin/ruijie-minieap-ctl \
  files/usr/bin/ruijie-post-auth.sh \
  files/usr/bin/ruijie-net-watchdog.sh \
  files/usr/bin/ruijie-reauth \
  files/etc/init.d/ruijie-minieap \
  files/etc/ruijie/env.example \
  | ssh_cmd "tar xf - -C /tmp/ruijie-minieap-src"

if [ -s "$TMP_ENV" ]; then
  scp_cmd "$TMP_ENV" "$SSH_TARGET:/tmp/ruijie.env"
  INSTALL_ARGS="--from-env /tmp/ruijie.env"
else
  INSTALL_ARGS=""
fi
rm -f "$TMP_ENV"

[ "$START" = "1" ] && INSTALL_ARGS="$INSTALL_ARGS --start"
[ "$VERIFY" = "1" ] && INSTALL_ARGS="$INSTALL_ARGS --verify"

echo "==> remote install $INSTALL_ARGS"
ssh_cmd "cd /tmp/ruijie-minieap-src && sh install.sh $INSTALL_ARGS"

echo "==> deploy complete"
ssh_cmd "/usr/bin/ruijie-minieap-ctl status" || true
