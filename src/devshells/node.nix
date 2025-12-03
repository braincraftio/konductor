# src/devshells/node.nix
# Node.js development shell
#
# Package composition defined in: ../packages/

{ baseShell, packages, versions, ... }:

let
  langs = versions.languages;
in

baseShell.overrideAttrs (old: {
  name = "node";

  # packages.nodejsPackages from ./packages.nix (single source of truth)
  buildInputs = old.buildInputs ++ packages.nodejsPackages;

  shellHook = old.shellHook + ''
    export KONDUCTOR_SHELL="node"
    export name="node"

    # pnpm home
    export PNPM_HOME="''${PNPM_HOME:-$HOME/.local/share/pnpm}"
    mkdir -p "$PNPM_HOME"
    export PATH="$PNPM_HOME:$PATH"

    echo "Node.js ${langs.node.display} ready"
  '';

  env = old.env // {
    NODE_ENV = "development";
  };
})
