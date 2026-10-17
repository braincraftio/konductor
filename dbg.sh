#!/usr/bin/env bash
# Report the 20 store paths with the most files in the konductor NixOS
# toplevel closure (diagnoses image size and copy time).
set -euo pipefail

echo "Building toplevel..."
TOPLEVEL=$(nix build .#nixosConfigurations.konductor.config.system.build.toplevel --no-link --print-out-paths)
echo "TOPLEVEL: ${TOPLEVEL}"

echo ""
echo "Counting files per store path (top 20)..."
closure=$(nix path-info -r "${TOPLEVEL}")
mapfile -t paths <<< "${closure}"

for path in "${paths[@]}"; do
    # A store path is either a directory tree or a single file.
    if [[ -d "${path}" ]]; then
        count=$(fd -t f . "${path}" | wc -l)
    else
        count=1
    fi
    printf "%s\t%s\n" "${count}" "${path}"
done | sort -rn | awk 'NR <= 20' # awk consumes all input: no SIGPIPE under pipefail
