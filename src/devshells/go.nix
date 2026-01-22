# src/devshells/go.nix
# Go development shell
#
# Package composition defined in: ../packages/

{ baseShell, packages, versions, ... }:

let
  langs = versions.languages;
in

baseShell.overrideAttrs (old: {
  name = "go";

  # packages.goPackages from ./packages.nix (single source of truth)
  # Using nativeBuildInputs (where mkShell's `packages` attribute is merged)
  nativeBuildInputs = old.nativeBuildInputs ++ packages.goPackages;

  shellHook = old.shellHook + ''
    # Go workspace (dynamic, needs $HOME)
    GOPATH="''${GOPATH:-$HOME/go}"
    GOBIN="$GOPATH/bin"
    mkdir -p "$GOPATH/src" "$GOPATH/bin" "$GOPATH/pkg"
    export PATH="$GOBIN:$PATH"

    echo "Go ${langs.go.display} ready"

    # Clean up shellHook from env output
    unset shellHook
  '';

  # Note: `name` cannot be in env (conflicts with mkShell's name attribute)
  env = old.env // {
    KONDUCTOR_SHELL = "go";
    GO111MODULE = "on";
    CGO_ENABLED = "1";
  };
})
