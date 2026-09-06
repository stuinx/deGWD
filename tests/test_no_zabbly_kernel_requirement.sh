#!/usr/bin/env bash
set -euo pipefail

repo_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

for script in client server; do
    if rg -n 'ensureZabblyKernel|installZabblyKernel' "$repo_dir/$script"; then
        echo "$script still contains a mandatory Zabbly kernel path" >&2
        exit 1
    fi
    bash -n "$repo_dir/$script"
done

# The explicit kernel menu remains available as an optional post-install action.
rg -q 'installkernel' "$repo_dir/server"

echo "PASS: install entrypoints do not require Zabbly; optional kernel action remains"
