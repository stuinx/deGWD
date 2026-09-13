#!/bin/bash

set -u

scriptDir=$(cd "$(dirname "$0")/.." && pwd)
testRoot=$(mktemp -d "${TMPDIR:-/tmp}/de_GWD-server-test.XXXXXX")
trap 'rm -rf -- "$testRoot"' EXIT

dataDir="$testRoot/opt/de_GWD"
xrayDir="$dataDir/vtrui"
tmpDir="$testRoot/tmp"
lockFile="$testRoot/run/de_GWD.lock"
nginxDir="$testRoot/etc/nginx/conf.d"
mkdir -p "$xrayDir" "$tmpDir" "$nginxDir"

export DE_GWD_TEST_MODE=1
export DE_GWD_DATA_DIR="$dataDir"
export DE_GWD_XRAY_DIR="$xrayDir"
export DE_GWD_NGINX_CONF_DIR="$nginxDir"
export DE_GWD_CONFIG_LOCK="$lockFile"
export DE_GWD_TXN_TMPDIR="$tmpDir"
export DE_GWD_XRAY_BIN="$xrayDir/vtrui"

source "$scriptDir/server" >/dev/null 2>&1

serviceLog="$testRoot/service.log"
restartFailOnce=0
validateFail=0
nginxTestFail=0

systemctl(){
  printf '%s\n' "$*" >>"$serviceLog"
  if [[ $1 = "restart" && ${2:-} = "vtrui" ]]; then
    if (( restartFailOnce == 1 )); then
      restartFailOnce=0
      return 1
    fi
    return 0
  fi
  if [[ $1 = "is-active" && ${2:-} = "--quiet" && ${3:-} = "vtrui" ]]; then
    return 0
  fi
  return 0
}

syncMainNodeState(){
  return 0
}

XrayInbound(){
  printf '%s\n' '{"generated":"inbound"}' >"$DE_GWD_XRAY_DIR/config.json"
}

XrayOutboundDirect(){
  printf '%s\n' '{"generated":"outbound"}' >"$DE_GWD_XRAY_DIR/config.json"
}

xrayValidateConfig(){
  (( validateFail == 0 ))
}

nginx(){
  [[ ${1:-} = "-t" ]] && (( nginxTestFail == 0 ))
}

nginxWebConf(){
  printf '%s\n' 'server_name new.example;' >"$DE_GWD_NGINX_CONF_DIR/default.conf"
  printf '%s\n' 'listen 80;' >"$DE_GWD_NGINX_CONF_DIR/80.conf"
  printf '%s\n' 'new-hsts' >"$DE_GWD_NGINX_CONF_DIR/.HSTS"
  printf '%s\n' 'new-certs' >"$DE_GWD_NGINX_CONF_DIR/.ssl_certs"
}

writeState(){
  local value=$1
  printf '%s\n' "{\"state\":\"$value\"}" >"$xrayDir/config.json"
  printf '%s\n' "{\"state\":\"$value-reality\"}" >"$dataDir/reality.json"
  printf '%s\n' "{\"state\":\"$value-vless\"}" >"$dataDir/vless.json"
  printf '%s\n' "{\"state\":\"$value-socks5\"}" >"$dataDir/socks5.json"
  printf '%s\n' "{\"state\":\"$value-dokodemo\"}" >"$dataDir/dokodemo.json"
}

saveSidecars(){
  local suffix=$1 sidecar
  for sidecar in vless reality socks5 dokodemo; do
    cp "$dataDir/$sidecar.json" "$testRoot/$sidecar.$suffix.old"
  done
}

assertSidecars(){
  local suffix=$1 sidecar
  for sidecar in vless reality socks5 dokodemo; do
    assert_file_equals "$testRoot/$sidecar.$suffix.old" "$dataDir/$sidecar.json" "$suffix rollback changed $sidecar sidecar"
  done
}

fail(){
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

assert_file_equals(){
  local expected=$1 actual=$2 message=$3
  cmp -s "$expected" "$actual" || fail "$message"
}

assert_contains(){
  local needle=$1 file=$2 message=$3
  /usr/bin/grep -F -- "$needle" "$file" >/dev/null 2>&1 || fail "$message"
}

hasRealFlock=0
if ! command -v flock >/dev/null 2>&1; then
  flock(){
    return 0
  }
  printf 'SKIP: cross-process lock test (flock is unavailable on this host)\n'
else
  hasRealFlock=1
fi

writeState old
saveSidecars invalid
cp "$dataDir/reality.json" "$testRoot/reality.old"
cp "$dataDir/vless.json" "$testRoot/vless.old"
cp "$xrayDir/config.json" "$testRoot/config.old"
candidate="$testRoot/reality.candidate.json"
printf '%s\n' '{"state":"new-reality"}' >"$candidate"
: >"$serviceLog"
validateFail=0
restartFailOnce=0
xrayConfigTransaction xrayApplyCandidate "$dataDir/reality.json" "$candidate" || fail "successful candidate application returned failure"
jq -e '.state == "new-reality"' "$dataDir/reality.json" >/dev/null || fail "successful application did not persist the candidate sidecar"
jq -e '.generated == "outbound"' "$xrayDir/config.json" >/dev/null || fail "successful application did not leave the generated Xray config"
[[ ! -e $candidate ]] || fail "candidate file was not consumed after a successful application"
assert_file_equals "$testRoot/vless.old" "$dataDir/vless.json" "$dataDir/vless.json changed during an unrelated node update"

writeState old
cp "$dataDir/reality.json" "$testRoot/reality.old"
cp "$xrayDir/config.json" "$testRoot/config.old"
candidate="$testRoot/reality.invalid.json"
printf '%s\n' '{"state":"invalid-reality"}' >"$candidate"
: >"$serviceLog"
validateFail=1
restartFailOnce=0
if xrayConfigTransaction xrayApplyCandidate "$dataDir/reality.json" "$candidate"; then
  fail "invalid Xray configuration was reported as success"
fi
assert_file_equals "$testRoot/reality.old" "$dataDir/reality.json" "invalid configuration did not restore the old sidecar"
assert_file_equals "$testRoot/config.old" "$xrayDir/config.json" "invalid configuration did not restore the old generated config"
assertSidecars invalid
assert_contains "restart vtrui" "$serviceLog" "invalid configuration did not attempt to restore the service"

writeState old
rm -f "$dataDir/reality.json"
cp "$xrayDir/config.json" "$testRoot/config.old"
candidate="$testRoot/reality.absent.json"
printf '%s\n' '{"state":"new-reality"}' >"$candidate"
: >"$serviceLog"
validateFail=1
if xrayConfigTransaction xrayApplyCandidate "$dataDir/reality.json" "$candidate"; then
  fail "a failed creation of an absent sidecar was reported as success"
fi
[[ ! -e $dataDir/reality.json ]] || fail "failed creation of an absent sidecar did not restore its absence"
assert_file_equals "$testRoot/config.old" "$xrayDir/config.json" "failed creation of an absent sidecar did not restore Xray config"

writeState old
saveSidecars restart
cp "$dataDir/reality.json" "$testRoot/reality.old"
cp "$xrayDir/config.json" "$testRoot/config.old"
candidate="$testRoot/reality.restart-failure.json"
printf '%s\n' '{"state":"restart-failure"}' >"$candidate"
: >"$serviceLog"
validateFail=0
restartFailOnce=1
if xrayConfigTransaction xrayApplyCandidate "$dataDir/reality.json" "$candidate"; then
  fail "service restart failure was reported as success"
fi
assert_file_equals "$testRoot/reality.old" "$dataDir/reality.json" "restart failure did not restore the old sidecar"
assert_file_equals "$testRoot/config.old" "$xrayDir/config.json" "restart failure did not restore the old generated config"
assertSidecars restart
restartCount=$(/usr/bin/grep -c '^restart vtrui$' "$serviceLog" || true)
(( restartCount == 2 )) || fail "restart failure did not perform the failed apply and recovery restart"

writeState old
for nginxState in default.conf 80.conf .HSTS .ssl_certs; do
  printf '%s\n' "old-$nginxState" >"$nginxDir/$nginxState"
  cp "$nginxDir/$nginxState" "$testRoot/$nginxState.old"
done
cp "$dataDir/vless.json" "$testRoot/vless.old"
cp "$xrayDir/config.json" "$testRoot/config.old"
candidate="$testRoot/vless.nginx-invalid.json"
printf '%s\n' '{"state":"new-vless"}' >"$candidate"
: >"$serviceLog"
validateFail=0
nginxTestFail=1
if configTransaction "nginx vtrui" vlessApplyCandidate \
    "$dataDir/vless.json" \
    "$xrayDir/config.json" \
    "$nginxDir/default.conf" \
    "$nginxDir/80.conf" \
    "$nginxDir/.HSTS" \
    "$nginxDir/.ssl_certs" \
    -- "$dataDir/vless.json" "$candidate"; then
  fail "invalid NGINX configuration was reported as success"
fi
assert_file_equals "$testRoot/vless.old" "$dataDir/vless.json" "invalid NGINX configuration did not restore VLESS settings"
assert_file_equals "$testRoot/config.old" "$xrayDir/config.json" "invalid NGINX configuration did not restore Xray config"
for nginxState in default.conf 80.conf .HSTS .ssl_certs; do
  assert_file_equals "$testRoot/$nginxState.old" "$nginxDir/$nginxState" "invalid NGINX configuration did not restore $nginxState"
done
assert_contains "restart nginx" "$serviceLog" "invalid NGINX configuration did not recover NGINX"
assert_contains "restart vtrui" "$serviceLog" "invalid NGINX configuration did not recover Xray"

writeState old
jq -n '{port:1081}' >"$dataDir/socks5.json"
jq -n '{port:1082}' >"$dataDir/dokodemo.json"
port=443
if xrayPortAvailable 1081 "$dataDir/vless.json"; then
  fail "a port used by another sidecar was reported as available"
fi
if xrayPortAvailable 443 "$dataDir/vless.json"; then
  fail "the main HTTPS port was reported as available"
fi

printf '%s\n' '#!/bin/sh' 'exit 0' >"$DE_GWD_XRAY_BIN"
chmod +x "$DE_GWD_XRAY_BIN"
nginxTestFail=0
getServerDomain(){
  printf '%s\n' 'node.example'
}
xrayPortAvailable(){
  return 0
}

writeState old
jq -n \
  '{enabled:true,domain:"old.example",port:8443,uuid:"00000000-0000-4000-8000-000000000001",dest:"old-target.example:443",serverName:"old-target.example",privateKey:"private",publicKey:"public",shortId:"abcdef12"}' \
  >"$dataDir/reality.json"
: >"$serviceLog"
validateFail=0
printf '1new.example:9443\n\n\n' | changeVLESSReality >/dev/null 2>&1 || fail "REALITY node switch returned failure"
jq -e '.domain == "new.example" and .port == 9443' "$dataDir/reality.json" >/dev/null || fail "REALITY node switch did not persist the new sidecar"
assert_contains "restart vtrui" "$serviceLog" "REALITY node switch did not restart Xray"
cp "$dataDir/reality.json" "$testRoot/reality.enabled"
cp "$xrayDir/config.json" "$testRoot/config.enabled"
: >"$serviceLog"
validateFail=1
if printf '2' | changeVLESSReality >/dev/null 2>&1; then
  fail "REALITY disable validation failure was reported as success"
fi
assert_file_equals "$testRoot/reality.enabled" "$dataDir/reality.json" "REALITY disable failure did not restore the sidecar"
assert_file_equals "$testRoot/config.enabled" "$xrayDir/config.json" "REALITY disable failure did not restore Xray config"
validateFail=0

writeState old
: >"$serviceLog"
printf '11081\nuser\npass\n' | changeSocks5 >/dev/null 2>&1 || fail "SOCKS5 node switch returned failure"
jq -e '.domain == "node.example" and .port == 1081 and .user == "user" and .password == "pass"' "$dataDir/socks5.json" >/dev/null || fail "SOCKS5 node switch did not persist the new sidecar"
cp "$dataDir/socks5.json" "$testRoot/socks5.enabled"
cp "$xrayDir/config.json" "$testRoot/config.enabled"
validateFail=1
if printf '2' | changeSocks5 >/dev/null 2>&1; then
  fail "SOCKS5 disable validation failure was reported as success"
fi
assert_file_equals "$testRoot/socks5.enabled" "$dataDir/socks5.json" "SOCKS5 disable failure did not restore the sidecar"
assert_file_equals "$testRoot/config.enabled" "$xrayDir/config.json" "SOCKS5 disable failure did not restore Xray config"
validateFail=0

writeState old
: >"$serviceLog"
printf '110087\ntarget.example:443\ntcp\n' | changeDokodemo >/dev/null 2>&1 || fail "dokodemo-door node switch returned failure"
jq -e '.domain == "node.example" and .port == 10087 and .target == "target.example" and .targetPort == 443 and .network == "tcp"' "$dataDir/dokodemo.json" >/dev/null || fail "dokodemo-door node switch did not persist the new sidecar"
cp "$dataDir/dokodemo.json" "$testRoot/dokodemo.enabled"
cp "$xrayDir/config.json" "$testRoot/config.enabled"
validateFail=1
if printf '2' | changeDokodemo >/dev/null 2>&1; then
  fail "dokodemo-door disable validation failure was reported as success"
fi
assert_file_equals "$testRoot/dokodemo.enabled" "$dataDir/dokodemo.json" "dokodemo-door disable failure did not restore the sidecar"
assert_file_equals "$testRoot/config.enabled" "$xrayDir/config.json" "dokodemo-door disable failure did not restore Xray config"
validateFail=0

if (( hasRealFlock == 1 )); then
  writeState old
  holdTransaction(){
    : >"$testRoot/holder.started"
    sleep 1
  }
  configTransaction vtrui holdTransaction "$xrayDir/config.json" -- &
  holderPID=$!
  for attempt in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20; do
    [[ -e $testRoot/holder.started ]] && break
    sleep 0.05
  done
  [[ -e $testRoot/holder.started ]] || fail "transaction holder did not start"
  [[ -e $lockFile ]] || fail "transaction lock file was not created"
  if configTransaction vtrui true "$xrayDir/config.json" --; then
    fail "concurrent configuration change was not rejected"
  fi
  wait "$holderPID" || fail "lock holder transaction failed"
fi

printf 'PASS: configuration transaction success, validation rollback, restart rollback, and lock boundary\n'
