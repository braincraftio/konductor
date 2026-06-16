# src/devshells/full.nix
# Full polyglot shell - everything included
# All languages + IDE tools
#
# Package composition defined in: ../packages/
# SSH config from: ../config/shell/ssh.nix
# OpenCode theme from: ../config/opencode/
# Atuin shell history from: ../config/shell/atuin.nix

{ baseShell
, packages
, versions
, programs
, config
, pkgs
, ...
}:

let
  langs = versions.languages;
in

baseShell.overrideAttrs (old: {
  name = "full";

  # Full package set from packages/default.nix (single source of truth)
  # Programs (neovim, tmux) and atuin come from separate inputs
  nativeBuildInputs =
    old.nativeBuildInputs
    ++ packages.fullPackages
    # Programs (neovim, tmux — require flake inputs, not in packages SSOT)
    ++ programs.neovim.packages
    ++ programs.tmux.packages
    # Atuin shell history (includes bash-preexec)
    ++ config.shell.atuin.packages;

  shellHook = old.shellHook + ''
    # SSH identity detection (dynamic, needs $HOME)
    ${config.shell.ssh.shellHook}

    # OpenCode theme (empty hook, config in opencode.json)
    ${config.opencode.shellHook}

    # Atuin data dir creation (dynamic, needs $HOME)
    ${config.shell.atuin.shellHook}

    # Runtime libraries (dynamic: appends to existing LD_LIBRARY_PATH)
    export LD_LIBRARY_PATH="${pkgs.lib.makeLibraryPath [
      pkgs.stdenv.cc.cc.lib
      pkgs.xz
      pkgs.zstd
    ]}"''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}

    # Program hooks
    ${programs.neovim.shellHook}
    ${programs.tmux.shellHook}

    # Go workspace (dynamic, needs $HOME)
    GOPATH="''${GOPATH:-$HOME/go}"
    GOBIN="$GOPATH/bin"
    mkdir -p "$GOPATH/src" "$GOPATH/bin" "$GOPATH/pkg"

    # Node (dynamic, needs $HOME)
    PNPM_HOME="''${PNPM_HOME:-$HOME/.local/share/pnpm}"
    mkdir -p "$PNPM_HOME"

    # Rust (dynamic, needs $HOME)
    CARGO_HOME="''${CARGO_HOME:-$HOME/.cargo}"
    mkdir -p "$CARGO_HOME"

    # Update PATH (depends on dynamic vars above)
    # Python env MUST be first — mkShell puts bare python3 in PATH from
    # withPackages build deps; this ensures the -env wrapper wins.
    export PATH="${packages.pythonEnv}/bin:$GOBIN:$PNPM_HOME:$CARGO_HOME/bin:$PATH"

    if [ -z "''${KONDUCTOR_SKIP_BANNER:-}" ]; then
      echo "Full polyglot ready"
      echo "  Python ${langs.python.display} | Go ${langs.go.display}"
      echo "  Node.js ${langs.node.display} | Rust ${langs.rust.display}"
    fi

    # Clean up shellHook from env output
    unset shellHook
  '';

  # Note: `name` cannot be in env (conflicts with mkShell's name attribute)
  # Cannot use old.env - mkShell's env doesn't become a derivation attribute
  # Import env sources directly instead
  env =
    import ../lib/env.nix
    // packages.env
    // {
      # Shell identity
      KONDUCTOR_SHELL = "full";
      # Python
      UV_SYSTEM_PYTHON = "1";
      PYTHONDONTWRITEBYTECODE = "1";
      # Go
      GO111MODULE = "on";
      CGO_ENABLED = "1";
      # Node
      NODE_ENV = "development";
      # Rust
      RUST_BACKTRACE = "1";
    }
    // config.shell.ssh.env
    // config.opencode.env
    // config.shell.atuin.env
    // programs.tmux.env;
})
