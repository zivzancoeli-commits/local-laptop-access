#!/bin/bash
set -euo pipefail
cd "$HOME/.config/moonlight-web"
# shellcheck disable=SC1091
. "$HOME/.config/moonlight-web/bin/load-host-settings.sh"
export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
export MACOSX_DEPLOYMENT_TARGET=15.0
export WEB_PORT

# Phone hotspots are often IPv6-only, so a small proxy also accepts that port.
pkill -f "$HOME/.config/moonlight-web/bin/ipv6-listen" >/dev/null 2>&1 || true
nohup python3 "$HOME/.config/moonlight-web/bin/ipv6-listen" \
  >>"$HOME/.config/moonlight-web/logs/ipv6-listen.log" 2>&1 &
echo $! > "$HOME/.config/moonlight-web/ipv6-listen.pid"

server="$HOME/.config/moonlight-web/web-server"
args=(
  --config-path "$HOME/.config/moonlight-web/server/config.json"
  --bind-address "0.0.0.0:${WEB_PORT}"
  --streamer-path "$HOME/.config/moonlight-web/streamer"
  --log-file "$HOME/.config/moonlight-web/logs/web-server.log"
)
if [ -n "$WEB_PATH" ]; then
  args+=(--path-prefix "$WEB_PATH")
fi
if [ "$(uname -m)" = "arm64" ] && file -b "$server" | grep -q x86_64 && ! file -b "$server" | grep -q arm64; then
  exec arch -x86_64 "$server" "${args[@]}"
fi
exec "$server" "${args[@]}"
