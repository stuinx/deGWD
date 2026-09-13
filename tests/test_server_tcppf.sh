#!/usr/bin/env bash

set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d "${TMPDIR:-/tmp}/de_GWD-tcppf-test.XXXXXX")
trap 'rm -rf -- "$test_root"' EXIT

data_dir="$test_root/opt/de_GWD"
nginx_dir="$test_root/etc/nginx/conf.d"
haproxy_dir="$test_root/etc/haproxy"
bin_dir="$test_root/bin"
txn_dir="$test_root/tmp"
mkdir -p "$data_dir" "$nginx_dir" "$haproxy_dir" "$bin_dir" "$txn_dir"

cat >"$bin_dir/haproxy" <<'EOF'
#!/bin/sh
if [ "${FAKE_HAPROXY_FAIL:-0}" = 1 ]; then
  exit 1
fi
exit 0
EOF
chmod +x "$bin_dir/haproxy"
cat >"$nginx_dir/default.conf" <<'EOF'
server_name node.example;
listen 443 default;
EOF

export DE_GWD_TEST_MODE=1
export DE_GWD_DATA_DIR="$data_dir"
export DE_GWD_NGINX_CONF_DIR="$nginx_dir"
export DE_GWD_TCPPF_SETTINGS="$data_dir/tcppf.json"
export DE_GWD_HAPROXY_CONFIG="$haproxy_dir/haproxy.cfg"
export DE_GWD_HAPROXY_SERVICE="$test_root/etc/systemd/system/haproxy.service"
export DE_GWD_HAPROXY_BIN="$bin_dir/haproxy"
export DE_GWD_TXN_TMPDIR="$txn_dir"
export PATH="$bin_dir:$PATH"
export TERM=xterm

source "$repo_dir/server" >/dev/null 2>&1

fail(){
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_file_contains(){
  local needle=$1 file=$2 message=$3
  grep -F -- "$needle" "$file" >/dev/null 2>&1 || fail "$message"
}

assert_file_not_contains(){
  local needle=$1 file=$2 message=$3
  if grep -F -- "$needle" "$file" >/dev/null 2>&1; then
    fail "$message"
  fi
}

# macOS does not provide flock; the transaction behavior is still exercised in
# one process with the lock boundary stubbed.
configLockAcquire(){ return 0; }
configLockRelease(){ :; }
systemctl(){
  [[ ${1:-} = "is-active" && ${2:-} = "--quiet" ]] && return 0
  return 0
}

printf '%s\n' '{"rules":[]}' >"$DE_GWD_TCPPF_SETTINGS"
printf 'upstream-one.example:8443\n20001\n' | tcppf_add >/dev/null
printf 'upstream-two.example:9443\n20002\n' | tcppf_add >/dev/null

[[ $(jq '.rules | length' "$DE_GWD_TCPPF_SETTINGS") = 2 ]] || fail "two TCP forwarding rules were not persisted"
assert_file_contains 'frontend p20001' "$DE_GWD_HAPROXY_CONFIG" "first frontend was not rendered"
assert_file_contains 'server endpoint upstream-one.example:8443' "$DE_GWD_HAPROXY_CONFIG" "first upstream was not rendered"
assert_file_contains 'frontend p20002' "$DE_GWD_HAPROXY_CONFIG" "second frontend was not rendered"
assert_file_contains 'server endpoint upstream-two.example:9443' "$DE_GWD_HAPROXY_CONFIG" "second upstream was not rendered"

if printf 'duplicate.example:443\n20002\n' | tcppf_add >/dev/null 2>&1; then
  fail "duplicate local port was accepted"
fi
[[ $(jq '.rules | length' "$DE_GWD_TCPPF_SETTINGS") = 2 ]] || fail "duplicate rejection changed settings"

printf '20001\n' | tcppf_del >/dev/null
[[ $(jq '.rules | length' "$DE_GWD_TCPPF_SETTINGS") = 1 ]] || fail "single-rule deletion removed the wrong number of rules"
assert_file_not_contains 'frontend p20001' "$DE_GWD_HAPROXY_CONFIG" "deleted frontend remained in HAProxy config"
assert_file_contains 'frontend p20002' "$DE_GWD_HAPROXY_CONFIG" "remaining frontend was removed"

tcppf_del_all >/dev/null
[[ $(jq '.rules | length' "$DE_GWD_TCPPF_SETTINGS") = 0 ]] || fail "delete-all did not clear persisted rules"
[[ ! -e $DE_GWD_HAPROXY_CONFIG ]] || fail "delete-all did not remove the HAProxy config"

# Import a legacy single-frontend HAProxy file when no JSON state exists.
rm -f -- "$DE_GWD_TCPPF_SETTINGS"
cat >"$DE_GWD_HAPROXY_CONFIG" <<'EOF'
frontend legacy-name
  bind :21001
  default_backend legacy-name

backend legacy-name
  server endpoint [2001:db8::1]:10443 check resolvers local init-addr none
EOF
tcppf_load
[[ $(jq '.rules | length' "$DE_GWD_TCPPF_SETTINGS") = 1 ]] || fail "legacy HAProxy rule was not imported"
jq -e '.rules[0].localPort == 21001 and .rules[0].upstream == "[2001:db8::1]:10443"' "$DE_GWD_TCPPF_SETTINGS" >/dev/null || fail "legacy HAProxy rule was imported incorrectly"

# A failed HAProxy validation must restore both the JSON state and rendered cfg.
tcppf_apply
cp "$DE_GWD_TCPPF_SETTINGS" "$test_root/settings.before"
cp "$DE_GWD_HAPROXY_CONFIG" "$test_root/config.before"
candidate="$test_root/candidate.json"
jq '.rules += [{localPort:21002,upstream:"rollback.example:443"}]' "$DE_GWD_TCPPF_SETTINGS" >"$candidate"
export FAKE_HAPROXY_FAIL=1
if tcppf_apply_transaction "$candidate" >/dev/null 2>&1; then
  fail "invalid HAProxy validation was reported as success"
fi
unset FAKE_HAPROXY_FAIL
cmp -s "$test_root/settings.before" "$DE_GWD_TCPPF_SETTINGS" || fail "failed apply did not restore JSON state"
cmp -s "$test_root/config.before" "$DE_GWD_HAPROXY_CONFIG" || fail "failed apply did not restore HAProxy config"
[[ ! -e $candidate ]] || fail "failed apply candidate was not cleaned up by the test caller"

printf '%s\n' 'PASS: server menu 44 supports multiple persistent TCP forwarding rules'
