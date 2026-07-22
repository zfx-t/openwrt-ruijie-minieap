#!/bin/sh
# Run ON the OpenWrt router (as root).
# Installs control scripts, env template, init service, and minieap if missing.
#
# Usage:
#   sh install.sh
#   RUIJIE_USERNAME=... RUIJIE_PASSWORD=... sh install.sh --start
#   sh install.sh --from-env /path/to/env

set -e

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)
FILES="$ROOT_DIR/files"
FROM_ENV=""
DO_START=0
DO_VERIFY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --from-env) FROM_ENV="$2"; shift 2 ;;
    --start) DO_START=1; shift ;;
    --verify) DO_VERIFY=1; DO_START=1; shift ;;
    -h|--help)
      echo "usage: $0 [--from-env FILE] [--start] [--verify]"
      exit 0
      ;;
    *) echo "unknown arg: $1"; exit 2 ;;
  esac
done

[ "$(id -u)" = "0" ] || { echo "run as root on OpenWrt"; exit 1; }
[ -d "$FILES" ] || { echo "missing $FILES"; exit 1; }

echo "==> install ruijie-minieap files"
mkdir -p /etc/ruijie /usr/bin /etc/init.d /var/log

cp -f "$FILES/usr/bin/ruijie-minieap-ctl" /usr/bin/ruijie-minieap-ctl
cp -f "$FILES/etc/init.d/ruijie-minieap" /etc/init.d/ruijie-minieap
cp -f "$FILES/etc/ruijie/env.example" /etc/ruijie/env.example
chmod +x /usr/bin/ruijie-minieap-ctl /etc/init.d/ruijie-minieap

if [ -n "$FROM_ENV" ]; then
  [ -f "$FROM_ENV" ] || { echo "env file not found: $FROM_ENV"; exit 1; }
  if [ "$(readlink -f "$FROM_ENV" 2>/dev/null || realpath "$FROM_ENV" 2>/dev/null || echo "$FROM_ENV")" != \
       "$(readlink -f /etc/ruijie/env 2>/dev/null || echo /etc/ruijie/env)" ]; then
    cp -f "$FROM_ENV" /etc/ruijie/env
  fi
  chmod 600 /etc/ruijie/env
  echo "==> installed /etc/ruijie/env from $FROM_ENV"
elif [ -n "${RUIJIE_USERNAME:-}" ] && [ -n "${RUIJIE_PASSWORD:-}" ]; then
  cat > /etc/ruijie/env <<EOF
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
  chmod 600 /etc/ruijie/env
  echo "==> wrote /etc/ruijie/env from environment variables"
elif [ ! -f /etc/ruijie/env ]; then
  cp -f /etc/ruijie/env.example /etc/ruijie/env
  chmod 600 /etc/ruijie/env
  echo "==> created /etc/ruijie/env from template — edit credentials before start"
fi

# ---- minieap binary ----
install_minieap() {
  if [ -x /usr/sbin/minieap ] && /usr/sbin/minieap -h >/dev/null 2>&1; then
    echo "==> minieap already present"
    return 0
  fi

  # load optional URL from env
  if [ -f /etc/ruijie/env ]; then
    # shellcheck disable=SC1091
    . /etc/ruijie/env 2>/dev/null || true
  fi

  if command -v opkg >/dev/null 2>&1; then
    echo "==> try opkg install minieap"
    opkg update 2>/dev/null || true
    if opkg install minieap 2>/dev/null; then
      return 0
    fi
  fi

  URL="${MINIEAP_IPK_URL:-}"
  if [ -z "$URL" ]; then
    # default for mipsel_24kc + older musl (OpenWrt ~21.x / Lean R21)
    arch=$(grep DISTRIB_ARCH /etc/openwrt_release 2>/dev/null | cut -d"'" -f2)
    case "$arch" in
      mipsel_24kc)
        URL="https://downloads.immortalwrt.org/releases/21.02.7/packages/mipsel_24kc/packages/minieap_0.93-3_mipsel_24kc.ipk"
        ;;
    esac
  fi

  if [ -n "$URL" ] && command -v wget >/dev/null 2>&1; then
    echo "==> download minieap ipk: $URL"
    wget -O /tmp/minieap.ipk "$URL" || curl -fL -o /tmp/minieap.ipk "$URL"
    opkg install /tmp/minieap.ipk
    return 0
  fi

  if [ -n "$URL" ] && command -v curl >/dev/null 2>&1; then
    echo "==> download minieap ipk: $URL"
    curl -fL -o /tmp/minieap.ipk "$URL"
    opkg install /tmp/minieap.ipk
    return 0
  fi

  echo "ERROR: minieap not installed. Set MINIEAP_IPK_URL or opkg install minieap"
  return 1
}

install_minieap

# sanity: minieap runs
/usr/sbin/minieap -h >/dev/null 2>&1 || {
  echo "ERROR: minieap binary not runnable (ABI mismatch?). Use an older ipk for your libc."
  exit 1
}

echo "==> enable boot service"
/etc/init.d/ruijie-minieap enable

# remove conflicting bare minieap init if ours is primary
if [ -f /etc/init.d/minieap ] && ! grep -q ruijie-minieap /etc/init.d/minieap 2>/dev/null; then
  /etc/init.d/minieap disable 2>/dev/null || true
  /etc/init.d/minieap stop 2>/dev/null || true
fi

if [ "$DO_START" = "1" ]; then
  echo "==> start service"
  /etc/init.d/ruijie-minieap stop 2>/dev/null || true
  killall minieap 2>/dev/null || true
  sleep 1
  /etc/init.d/ruijie-minieap start
  sleep 4
fi

if [ "$DO_VERIFY" = "1" ]; then
  /usr/bin/ruijie-minieap-ctl verify
fi

echo ""
echo "Install done."
echo "  env:     /etc/ruijie/env"
echo "  ctl:     ruijie-minieap-ctl {start|stop|status|verify}"
echo "  service: /etc/init.d/ruijie-minieap {start|stop|enable|disable}"
echo ""
if ! grep -q '^RUIJIE_USERNAME=.\+' /etc/ruijie/env 2>/dev/null || grep -q 'YOUR_STUDENT_ID' /etc/ruijie/env 2>/dev/null; then
  echo "Next: vi /etc/ruijie/env   # set username/password"
  echo "Then: /etc/init.d/ruijie-minieap start && ruijie-minieap-ctl verify"
fi
