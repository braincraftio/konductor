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
  # Using nativeBuildInputs (where mkShell's `packages` attribute is merged)
  nativeBuildInputs = old.nativeBuildInputs ++ packages.nodejsPackages;

  shellHook = old.shellHook + ''
    # pnpm home (dynamic, needs $HOME)
    PNPM_HOME="''${PNPM_HOME:-$HOME/.local/share/pnpm}"
    mkdir -p "$PNPM_HOME"
    export PATH="$PNPM_HOME:$PATH"

    echo "Node.js ${langs.node.display} ready"

    # Clean up shellHook from env output
    unset shellHook
  '';

  # Note: `name` cannot be in env (conflicts with mkShell's name attribute)
  env = old.env // {
    KONDUCTOR_SHELL = "node";
    NODE_ENV = "development";
  };
})
