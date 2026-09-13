#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
server_script="$repo_dir/server"
fixture_dir=$(mktemp -d /tmp/de_GWD-xray-protocols.XXXXXX)
trap 'rm -rf "$fixture_dir"' EXIT

mkdir -p "$fixture_dir/data" "$fixture_dir/xray" "$fixture_dir/nginx" "$fixture_dir/bin"
cat >"$fixture_dir/bin/sponge" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
tmp=$(mktemp "${1}.XXXXXX")
cat >"$tmp"
mv -f "$tmp" "$1"
EOF
chmod +x "$fixture_dir/bin/sponge"

cat >"$fixture_dir/data/vless.json" <<'EOF'
{"enabled":true,"domain":"vless.example","port":8443,"uuid":"11111111-1111-4111-8111-111111111111","path":"/vless"}
EOF
cat >"$fixture_dir/data/reality.json" <<'EOF'
{"enabled":true,"domain":"reality.example","port":9443,"uuid":"22222222-2222-4222-8222-222222222222","flow":"xtls-rprx-vision","dest":"example.com:443","serverName":"example.com","privateKey":"private-key","publicKey":"public-key","shortId":"0123456789abcdef"}
EOF
cat >"$fixture_dir/data/socks5.json" <<'EOF'
{"enabled":true,"domain":"socks.example","port":1080,"user":"test-user","password":"test-password"}
EOF
cat >"$fixture_dir/data/dokodemo.json" <<'EOF'
{"enabled":true,"domain":"dokodemo.example","port":10086,"target":"127.0.0.1","targetPort":8080,"network":"tcp,udp"}
EOF
cat >"$fixture_dir/filter.jq" <<'EOF'
(.inbounds | map(.protocol) | sort) == ["dokodemo-door","socks","vless","vless","vmess"]
and (.inbounds | map(select(.protocol == "vless" and .streamSettings.network == "ws")) | length) == 1
and (.inbounds | map(select(.protocol == "vless" and .streamSettings.security == "reality")) | length) == 1
and (.inbounds | map(select(.protocol == "socks" and .settings.auth == "password")) | length) == 1
and (.inbounds | map(select(.protocol == "dokodemo-door" and .settings.network == "tcp,udp")) | length) == 1
and (.outbounds | map(.tag) | sort) == ["blocked","direct"]
EOF

PATH="$fixture_dir/bin:$PATH" \
DE_GWD_TEST_MODE=1 \
DE_GWD_DATA_DIR="$fixture_dir/data" \
DE_GWD_XRAY_DIR="$fixture_dir/xray" \
DE_GWD_NGINX_CONF_DIR="$fixture_dir/nginx" \
DE_GWD_XRAY_BIN="$fixture_dir/bin/xray" \
bash -c '
  source "$1"
  XrayInbound
  XrayOutboundDirect
  jq -e -f "$2" "$DE_GWD_XRAY_DIR/config.json" >/dev/null
' _ "$server_script" "$fixture_dir/filter.jq"

bash -n "$server_script"
test "$(rg -c '^    66\)$' "$server_script")" -eq 2
test "$(rg -c '66\.Add Xray protocol' "$server_script")" -eq 2
test "$(rg -c '33\.Set Cloudflare wireguard upstream' "$server_script")" -eq 1
rg -A2 '^    33\)$' "$server_script" | grep -q 'changeWGCF'
for symbol in changeVLESS changeVLESSReality changeSocks5 changeDokodemo changeXrayNode; do
    rg -q "^${symbol}\(\)" "$server_script"
done

echo "PASS: server menu 66 and Xray protocol configuration are present"
