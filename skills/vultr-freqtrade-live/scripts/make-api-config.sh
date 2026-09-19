#!/usr/bin/env bash
# Write user_data/config-api-private.json on the VPS with random credentials for an API
# server that listens on 127.0.0.1 only. Run it on the server (openssl is present on Ubuntu);
# it refuses to overwrite an existing file. Nothing here is published on a host port —
# docker-compose.live.yml maps no ports, and the agent talks to the bot with
#   docker exec <container> freqtrade-client --config /freqtrade/user_data/config-api-private.json <cmd>
set -euo pipefail

TARGET="${1:-user_data/config-api-private.json}"
if [ -e "$TARGET" ]; then
  echo "refusing to overwrite $TARGET" >&2
  exit 1
fi

umask 077
JWT="$(openssl rand -hex 32)"
PASSWORD="$(openssl rand -base64 30 | tr '+/' '-_' | tr -d '=')"
WS_TOKEN="$(openssl rand -base64 30 | tr '+/' '-_' | tr -d '=')"

cat > "$TARGET" <<EOF
{
  "api_server": {
    "enabled": true,
    "listen_ip_address": "127.0.0.1",
    "listen_port": 8080,
    "verbosity": "error",
    "enable_openapi": false,
    "jwt_secret_key": "$JWT",
    "CORS_origins": [],
    "username": "freqtrade-local",
    "password": "$PASSWORD",
    "ws_token": "$WS_TOKEN"
  }
}
EOF
chmod 600 "$TARGET"
python3 -m json.tool "$TARGET" > /dev/null && echo "wrote $TARGET (mode 600)"
