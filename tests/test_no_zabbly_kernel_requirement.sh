#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

for script in client server; do
    if rg -n 'ensureZabblyKernel|installZabblyKernel|checkKernel' "$repo_dir/$script"; then
        echo "$script still contains a mandatory kernel reboot/install check" >&2
        exit 1
    fi
    bash -n "$repo_dir/$script"
done

# The explicit kernel menu remains available as an optional post-install action.
rg -q 'installkernel' "$repo_dir/server"

# Pi-hole download failures must have a verified registry fallback and stop the install.
rg -q 'mps\.rxm\.xyz/pihole/pihole:latest' "$repo_dir/client"
rg -q 'docker image inspect pihole/pihole:latest' "$repo_dir/client"
rg -q 'pullpihole \|\| exit 1' "$repo_dir/client"
rg -q 'installPihole \|\| exit 1' "$repo_dir/client"
rg -q 'piholeSet \|\| exit 1' "$repo_dir/client"

# APT's systemd timers may briefly hold the package-manager lock during install.
rg -q '^waitAPT\(\)' "$repo_dir/client"
rg -q 'waitAPT \|\| return 1' "$repo_dir/client"
rg -q '^verifyRuntimeResources\(\)' "$repo_dir/client"
rg -q 'verifyRuntimeResources \|\| return 1' "$repo_dir/client"
rg -q 'du -sk /opt/de_GWD/\.repo/IPchnroute.*-ge 100' "$repo_dir/client"
rg -q 'systemctl is-active --quiet "\$service"' "$repo_dir/client"
rg -q 'docker inspect -f '\''\{\{\.State\.Running\}\}'\'' pihole' "$repo_dir/client"

echo "PASS: install entrypoints do not require Zabbly; runtime and service gates remain enabled"
