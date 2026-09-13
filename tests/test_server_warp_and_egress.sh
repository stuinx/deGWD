#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
server_script="$repo_dir/server"
test_root=$(mktemp -d "${TMPDIR:-/tmp}/de_GWD-warp-egress-test.XXXXXX")
trap 'rm -rf -- "$test_root"' EXIT

data_dir="$test_root/opt/de_GWD"
wg_dir="$test_root/etc/wireguard"
sysd_dir="$test_root/etc/systemd/system"
bin_dir="$test_root/bin"
mkdir -p "$data_dir" "$wg_dir" "$sysd_dir" "$bin_dir"

cat >"$bin_dir/wgcf" <<'SH'
#!/bin/sh
exit 0
SH
chmod +x "$bin_dir/wgcf"

cat >"$bin_dir/tun2socks" <<'SH'
#!/bin/sh
exit 0
SH
chmod +x "$bin_dir/tun2socks"

# Mock profile
cat >"$test_root/wgcf-profile.conf" <<'CFG'
[Interface]
PrivateKey = test_warp_private_key=
Address = 172.16.0.2/32
Address = 2606:4700:110:8a49:60ae:213b:a6f5:a7ff/128
DNS = 1.1.1.1
MTU = 1280
[Peer]
PublicKey = test_warp_public_key=
AllowedIPs = 0.0.0.0/0
AllowedIPs = ::/0
Endpoint = engage.cloudflareclient.com:2408
Reserved = [1, 2, 3]
CFG

export DE_GWD_TEST_MODE=1
export DE_GWD_DATA_DIR="$data_dir"
export DE_GWD_WIREGUARD_DIR="$wg_dir"
export DE_GWD_WGCF_CONF="$wg_dir/wgcf.conf"
export DE_GWD_WARP_POSTUP="$data_dir/warp_postup.sh"
export DE_GWD_WARP_POSTDOWN="$data_dir/warp_postdown.sh"
export DE_GWD_WARP_SETTINGS="$data_dir/warp.json"
export DE_GWD_TCPPF_SETTINGS="$data_dir/tcppf.json"
export DE_GWD_SOCKS5_EGRESS_SETTINGS="$data_dir/socks5_egress.json"
export DE_GWD_SOCKS5_EGRESS_SERVICE="$sysd_dir/de_GWD-socks5-egress.service"
export DE_GWD_SOCKS5_POSTUP="$data_dir/socks5_egress_postup.sh"
export DE_GWD_SOCKS5_POSTDOWN="$data_dir/socks5_egress_postdown.sh"
mkdir -p "$test_root/etc/nginx/conf.d"
cat >"$test_root/etc/nginx/conf.d/default.conf" <<'NGX'
server_name test.example;
listen 443 default;
NGX
export DE_GWD_NGINX_CONF_DIR="$test_root/etc/nginx/conf.d"
export PATH="$bin_dir:$PATH"
export TERM=xterm

source "$server_script" >/dev/null 2>&1

fail(){
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_file_contains(){
  local needle=$1 file=$2 message=$3
  grep -F -- "$needle" "$file" >/dev/null 2>&1 || fail "$message"
}

systemctl(){
  return 0
}

# 1. Test WARP IPv4 config generation
warp_render_scripts "ipv4"
warp_render_config "ipv4" "$test_root/wgcf-profile.conf"

assert_file_contains "Table = 51820" "$DE_GWD_WGCF_CONF" "WARP config does not specify Table = 51820"
assert_file_contains "test_warp_private_key=" "$DE_GWD_WGCF_CONF" "WARP config missing private key"
assert_file_contains "Reserved = [1, 2, 3]" "$DE_GWD_WGCF_CONF" "WARP config missing reserved parameter"
assert_file_contains "priority 51810" "$DE_GWD_WARP_POSTUP" "WARP postup missing priority 51810 for local IP"
assert_file_contains "priority 51811" "$DE_GWD_WARP_POSTUP" "WARP postup missing priority 51811 for SSH"
assert_file_contains "priority 51820" "$DE_GWD_WARP_POSTUP" "WARP postup missing priority 51820 lookup"
assert_file_contains "flush table 51820" "$DE_GWD_WARP_POSTDOWN" "WARP postdown does not flush table 51820"

# 2. Test WARP Dual-Stack config generation
warp_render_scripts "dual"
warp_render_config "dual" "$test_root/wgcf-profile.conf"

assert_file_contains "AllowedIPs = ::/0" "$DE_GWD_WGCF_CONF" "Dual-stack WARP missing IPv6 AllowedIPs"
assert_file_contains "ip -6 rule add lookup 51820 priority 51820" "$DE_GWD_WARP_POSTUP" "Dual-stack WARP postup missing IPv6 table 51820 rule"

# 3. Test WARP start and rollback on failure
FAKE_WARP_FAIL=0 warp_start "ipv4" "$test_root/wgcf-profile.conf" >/dev/null
[[ $(jq -r '.enabled' "$DE_GWD_WARP_SETTINGS") = "true" ]] || fail "WARP start did not persist enabled state"

FAKE_WARP_FAIL=1 warp_start "ipv4" "$test_root/wgcf-profile.conf" >/dev/null 2>&1 || true
[[ $(jq -r '.enabled' "$DE_GWD_WARP_SETTINGS") = "false" ]] || fail "WARP failure did not rollback and persist disabled state"

# Restore WARP active state for printNode testing
printf '{"enabled":true,"mode":"dual"}\n' > "$DE_GWD_WARP_SETTINGS"

# 4. Test SOCKS5 Upstream Egress
if socks5_egress_start "bad host!" 1080 >/dev/null 2>&1; then
  fail "Invalid SOCKS5 server was accepted"
fi
if socks5_egress_start "proxy.example.com" 99999 >/dev/null 2>&1; then
  fail "Invalid SOCKS5 port was accepted"
fi

FAKE_SOCKS5_EGRESS_FAIL=0 socks5_egress_start "proxy.example.com" 1080 "testuser" "testpass" >/dev/null
[[ $(jq -r '.enabled' "$DE_GWD_SOCKS5_EGRESS_SETTINGS") = "true" ]] || fail "SOCKS5 egress did not persist enabled state"
[[ $(jq -r '.server' "$DE_GWD_SOCKS5_EGRESS_SETTINGS") = "proxy.example.com" ]] || fail "SOCKS5 egress server mismatch"
[[ $(jq -r '.port' "$DE_GWD_SOCKS5_EGRESS_SETTINGS") = "1080" ]] || fail "SOCKS5 egress port mismatch"

assert_file_contains "socks5://testuser:testpass@proxy.example.com:1080" "$DE_GWD_SOCKS5_EGRESS_SERVICE" "SOCKS5 service missing proxy URL"
assert_file_contains "priority 51831" "$DE_GWD_SOCKS5_POSTUP" "SOCKS5 postup missing priority 51831 for local IP"
assert_file_contains "priority 51832" "$DE_GWD_SOCKS5_POSTUP" "SOCKS5 postup missing priority 51832 for SSH"
assert_file_contains "priority 51834" "$DE_GWD_SOCKS5_POSTUP" "SOCKS5 postup missing priority 51834 for DNS"
assert_file_contains "priority 51835" "$DE_GWD_SOCKS5_POSTUP" "SOCKS5 postup missing priority 51835 for SOCKS server"
assert_file_contains "priority 51839" "$DE_GWD_SOCKS5_POSTUP" "SOCKS5 postup missing priority 51839 for table 51830"
assert_file_contains "flush table 51830" "$DE_GWD_SOCKS5_POSTDOWN" "SOCKS5 postdown does not flush table 51830"

# 5. Test SOCKS5 start rollback on failure
FAKE_SOCKS5_EGRESS_FAIL=1 socks5_egress_start "proxy.example.com" 1080 >/dev/null 2>&1 || true
[[ $(jq -r '.enabled' "$DE_GWD_SOCKS5_EGRESS_SETTINGS") = "true" ]]

# Test HAProxy rules JSON for printNode
printf '{"rules":[{"localPort":20001,"upstream":"upstream.example:8443"}]}\n' > "$DE_GWD_TCPPF_SETTINGS"

# 6. Test menu integration and printNode
print_out=$(printNode 2>&1 || true)
printf '%s\n' "$print_out" | grep -q "Cloudflare WARP (Table 51820)" || fail "printNode missing WARP info"
printf '%s\n' "$print_out" | grep -q "System SOCKS5 Upstream Egress" || fail "printNode missing SOCKS5 egress info"
printf '%s\n' "$print_out" | grep -q "HAProxy TCP Forward Rules" || fail "printNode missing HAProxy rules info"

# Menu symbols and switches
grep -q '33\.Set Cloudflare wireguard upstream' "$server_script" || fail "Menu 33 title missing"
grep -q '35\.Set System SOCKS5 Upstream Egress' "$server_script" || fail "Menu 35 title missing"
grep -A2 '35)' "$server_script" | grep -q 'changeSocks5Egress' || fail "Menu 35 case branch missing"

socks5_egress_stop >/dev/null
[[ $(jq -r '.enabled' "$DE_GWD_SOCKS5_EGRESS_SETTINGS") = "false" ]] || fail "SOCKS5 egress stop did not update state"

printf '%s\n' 'PASS: server menu 33 (WARP table 51820) and menu 35 (SOCKS5 egress) verified'
