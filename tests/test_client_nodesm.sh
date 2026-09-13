#!/usr/bin/env bash

set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d "${TMPDIR:-/tmp}/de_GWD-nodesm-test.XXXXXX")
trap 'rm -rf -- "$test_root"' EXIT

root="$test_root/opt/de_GWD"
config="$root/vtrui/config.json"
zero_config="$root/0conf"
bin_dir="$test_root/bin"
mkdir -p "$root/vtrui" "$bin_dir"

cat >"$bin_dir/systemctl" <<'SYSTEMCTLEOF'
#!/bin/sh
exit 0
SYSTEMCTLEOF
chmod +x "$bin_dir/systemctl"
cat >"$bin_dir/sponge" <<'SPONGEEOF'
#!/bin/sh
target="$1"
tmp="${target}.tmp.$$"
cat > "$tmp" && mv "$tmp" "$target"
SPONGEEOF
chmod +x "$bin_dir/sponge"

cat >"$bin_dir/ui-V2routingDomain" <<'ROUTINGEOF'
#!/bin/sh
tag="$1"
domain="$2"
jq --arg tag "$tag" --argjson domain "$domain"   '.routing.rules += [{"type":"field","domain":$domain,"outboundTag":$tag}]'   "$DE_GWD_VTRUI_CONFIG" > "$DE_GWD_VTRUI_CONFIG.tmp" && mv "$DE_GWD_VTRUI_CONFIG.tmp" "$DE_GWD_VTRUI_CONFIG"
ROUTINGEOF
chmod +x "$bin_dir/ui-V2routingDomain"

cat >"$bin_dir/ui-V2outbound" <<'OUTBOUNDEOF'
#!/bin/sh
tag="$1"
addr="$2"
host=$(echo "$addr" | cut -d: -f1)
port=$(echo "$addr" | cut -d: -f2)
[ -z "$port" ] || [ "$port" = "$host" ] && port=443
jq --arg tag "$tag" --arg host "$host" --argjson port "$port"   '.outbounds += [{"tag":$tag,"protocol":"vmess","settings":{"vnext":[{"address":$host,"port":$port}]}}]'   "$DE_GWD_VTRUI_CONFIG" > "$DE_GWD_VTRUI_CONFIG.tmp" && mv "$DE_GWD_VTRUI_CONFIG.tmp" "$DE_GWD_VTRUI_CONFIG"
OUTBOUNDEOF
chmod +x "$bin_dir/ui-V2outbound"

cat >"$bin_dir/ui-submitListBWsm" <<'SUBMITEOF'
#!/bin/sh
exit 0
SUBMITEOF
chmod +x "$bin_dir/ui-submitListBWsm"

cat >"$config" <<'CONFIGEOF'
{
  "outbounds": [
    {"tag":"direct","protocol":"freedom"}
  ],
  "routing": {
    "rules": [
      {"type":"field","ip":["geoip:private"],"outboundTag":"direct"}
    ]
  }
}
CONFIGEOF

cat >"$zero_config" <<'ZEROEOF'
{
  "v2node": [
    {"name":"Node 1 US","domain":"us.example.com:443","tls":"us.example.com","uuid":"11111111-1111-1111-1111-111111111111","path":"/us"},
    {"name":"Node 2 JP","domain":"jp.example.com:8443","tls":"jp.example.com","uuid":"22222222-2222-2222-2222-222222222222","path":"/jp"}
  ],
  "v2nodeDIV": {
    "nodeSM": {
      "status": "off",
      "hdh": "us.example.com:443",
      "tvb": "jp.example.com:8443",
      "bahamut": "jp.example.com:8443"
    }
  }
}
ZEROEOF

export PATH="$bin_dir:$PATH"
export DE_GWD_CONFIG_FILE="$zero_config"
export DE_GWD_VTRUI_CONFIG="$config"
export DE_GWD_ROUTING_DOMAIN_CMD="$bin_dir/ui-V2routingDomain"
export DE_GWD_OUTBOUND_CMD="$bin_dir/ui-V2outbound"
export DE_GWD_SUBMIT_LIST_CMD="$bin_dir/ui-submitListBWsm"

node_sm="$repo_dir/resource/client/ui-script/ui-NodeSM"
node_sm_check="$repo_dir/resource/client/ui-script/ui-NodeSMcheck"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

# 1. Test set-json mode
"$node_sm" set-json '{"openai":1,"claude":2,"apple":1,"steam":"proxy"}' r || fail "ui-NodeSM set-json failed"

# Check legacy keys pruned
[[ $(jq '.v2nodeDIV.nodeSM | has("hdh") or has("tvb") or has("bahamut")' "$zero_config") = "false" ]] || fail "Legacy keys not pruned"

# Check 0conf dictionary stored correctly
[[ $(jq -r '.v2nodeDIV.nodeSM.openai' "$zero_config") = "us.example.com:443" ]] || fail "OpenAI address in 0conf incorrect"
[[ $(jq -r '.v2nodeDIV.nodeSM.claude' "$zero_config") = "jp.example.com:8443" ]] || fail "Claude address in 0conf incorrect"
[[ $(jq -r '.v2nodeDIV.nodeSM.status' "$zero_config") = "on" ]] || fail "Status should be on"

# Check outbounds and routing in vtrui
[[ $(jq '.outbounds[] | select(.tag == "nodeSMopenai") | .settings.vnext[0].address' "$config" -r) = "us.example.com" ]] || fail "OpenAI outbound missing"
[[ $(jq '.outbounds[] | select(.tag == "nodeSMclaude") | .settings.vnext[0].address' "$config" -r) = "jp.example.com" ]] || fail "Claude outbound missing"
[[ $(jq '.routing.rules[] | select(.outboundTag == "nodeSMopenai") | .domain | length' "$config") -gt 0 ]] || fail "OpenAI routing rule missing"

# 2. Test ui-NodeSMcheck output
check_output=$("$node_sm_check")
echo "$check_output" | grep -q "Node 1 US" || fail "NodeSMcheck does not report Node 1 US"
echo "$check_output" | grep -q "Node 2 JP" || fail "NodeSMcheck does not report Node 2 JP"

# 3. Test positional mode reset
"$node_sm" r 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 || fail "ui-NodeSM reset failed"
[[ $(jq -r '.v2nodeDIV.nodeSM.status' "$zero_config") = "off" ]] || fail "Status should be off after reset"
[[ $(jq '.outbounds | map(select(.tag | startswith("nodeSM"))) | length' "$config") = 0 ]] || fail "All nodeSM outbounds should be cleared"

echo "PASS: client predefined domain routing tests completed successfully"
