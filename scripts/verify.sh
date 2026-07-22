#!/bin/sh
# Run on OpenWrt: scripts/verify.sh
# Or from PC after deploy: ssh root@router ruijie-minieap-ctl verify

if [ -x /usr/bin/ruijie-minieap-ctl ]; then
  exec /usr/bin/ruijie-minieap-ctl verify
fi

echo "ruijie-minieap-ctl not installed; run install.sh first"
exit 1
