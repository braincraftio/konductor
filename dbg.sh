#!/usr/bin/env bash
set -euo pipefail

echo "Building toplevel..."
TOPLEVEL=$(nix build .#nixosConfigurations.konductor.config.system.build.toplevel --no-link --print-out-paths)
echo "TOPLEVEL: $TOPLEVEL"

echo ""
echo "Counting files per store path (top 20)..."
for path in $(nix path-info -r $TOPLEVEL); do
  printf "%s\t%s\n" "$(fd -t f . "$path" 2>/dev/null | wc -l)" "$path"
done | sort -rn | head -20
