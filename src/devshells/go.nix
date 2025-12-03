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
  buildInputs = old.buildInputs ++ packages.goPackages;

  shellHook = old.shellHook + ''
    export KONDUCTOR_SHELL="go"
    export name="go"

    # Go workspace
    export GOPATH="''${GOPATH:-$HOME/go}"
    export GOBIN="$GOPATH/bin"
    mkdir -p "$GOPATH/src" "$GOPATH/bin" "$GOPATH/pkg"
    export PATH="$GOBIN:$PATH"

    echo "Go ${langs.go.display} ready"
  '';

  env = old.env // {
    GO111MODULE = "on";
    CGO_ENABLED = "1";
  };
})
