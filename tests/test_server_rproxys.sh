#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
server_script="$repo_dir/server"

bash -n "$server_script"

for symbol in RproxyS_valid_uuid RproxyS_valid_port RproxySsave RproxySstop printRproxyS changeRproxyS; do
    rg -q "^${symbol}\(\)" "$server_script"
done

# The generated server config must contain the same reverse-tunnel primitives as the client.
rg -q '"reverseTunnel"' "$server_script"
rg -q '"reverse.localhost"' "$server_script"
rg -q '"dokodemo-door"' "$server_script"

# RproxyS must be installed and restarted through a dedicated systemd unit.
rg -q 'RproxyS\.service' "$server_script"
rg -q 'ExecStart=/opt/de_GWD/RproxyS/RproxyS run -config /opt/de_GWD/RproxyS/config\.json' "$server_script"
rg -q 'systemctl is-active --quiet RproxyS' "$server_script"

# Existing enabled settings are restored after install and update, and the feature is reachable in both menus.
rg -q 'RproxySsave' "$server_script"
rg -q '55\.Set RproxyS reverse proxy' "$server_script"
rg -q '\[3\]: Show RproxyS settings' "$server_script"
test "$(rg -c '^    55\)$' "$server_script")" -eq 2

echo "PASS: server-side RproxyS reverse proxy lifecycle and menu are present"
