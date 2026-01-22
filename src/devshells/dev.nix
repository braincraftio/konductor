# src/devshells/dev.nix
# Human workflow shell with IDE tools
# Adds neovim + tmux + forgejo-cli for interactive development
#
# Package composition defined in: ../packages/
# SSH config from: ../config/shell/ssh.nix
# OpenCode theme from: ../config/opencode/

{ baseShell, packages, programs, config, ... }:

baseShell.overrideAttrs (old: {
  name = "dev";

  # packages.idePackages from ./packages.nix (single source of truth)
  # plus neovim, tmux, and forgejo-cli from programs
  # Using nativeBuildInputs (where mkShell's `packages` attribute is merged)
  nativeBuildInputs = old.nativeBuildInputs
    ++ programs.neovim.packages
    ++ programs.tmux.packages
    ++ programs.forgejo.cliPackages
    ++ packages.idePackages;

  shellHook = old.shellHook + ''
    # SSH identity detection (dynamic, needs $HOME)
    ${config.shell.ssh.shellHook}

    # OpenCode theme (empty hook, config in opencode.json)
    ${config.opencode.shellHook}

    # Program hooks (neovim and tmux are empty now)
    ${programs.neovim.shellHook}
    ${programs.tmux.shellHook}

    echo "IDE ready: nvim, tmux, forgejo-cli"

    # Clean up shellHook from env output
    unset shellHook
  '';

  # Note: `name` cannot be in env (conflicts with mkShell's name attribute)
  env = old.env // {
    KONDUCTOR_SHELL = "dev";
  } // config.shell.ssh.env // config.opencode.env // programs.tmux.env;
})
