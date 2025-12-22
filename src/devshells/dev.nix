# src/devshells/dev.nix
# Human workflow shell with IDE tools
# Adds neovim + tmux + forgejo-cli for interactive development
#
# Package composition defined in: ../packages/
# SSH config from: ../config/shell/ssh.nix

{ baseShell, packages, programs, config, ... }:

baseShell.overrideAttrs (old: {
  name = "dev";

  # packages.idePackages from ./packages.nix (single source of truth)
  # plus neovim, tmux, and forgejo-cli from programs
  buildInputs = old.buildInputs
    ++ programs.neovim.packages
    ++ programs.tmux.packages
    ++ programs.forgejo.cliPackages
    ++ packages.idePackages;

  shellHook = old.shellHook + ''
    export KONDUCTOR_SHELL="dev"
    export name="dev"

    # SSH config generation from centralized src/config/shell/ssh.nix
    ${config.shell.ssh.shellHook}

    ${programs.neovim.shellHook}
    ${programs.tmux.shellHook}

    echo "IDE ready: nvim, tmux, forgejo-cli"
  '';

  env = old.env // config.shell.ssh.env;
})
