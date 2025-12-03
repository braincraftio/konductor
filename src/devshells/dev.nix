# src/devshells/dev.nix
# Human workflow shell with IDE tools
# Adds neovim + tmux for interactive development
#
# Package composition defined in: ../packages/

{ baseShell, packages, programs, ... }:

baseShell.overrideAttrs (old: {
  name = "dev";

  # packages.idePackages from ./packages.nix (single source of truth)
  # plus neovim and tmux from programs
  buildInputs = old.buildInputs
    ++ programs.neovim.packages
    ++ programs.tmux.packages
    ++ packages.idePackages;

  shellHook = old.shellHook + ''
    export KONDUCTOR_SHELL="dev"
    export name="dev"

    ${programs.neovim.shellHook}
    ${programs.tmux.shellHook}

    echo "IDE ready: nvim, tmux"
  '';
})
