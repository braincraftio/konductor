# src/devshells/full.nix
# Full polyglot shell - everything included
# All languages + IDE tools
#
# Package composition defined in: ../packages/
# SSH config from: ../config/shell/ssh.nix
# OpenCode theme from: ../config/opencode/
# Atuin shell history from: ../config/shell/atuin.nix

{
  baseShell,
  packages,
  versions,
  programs,
  config,
  pkgs,
  ...
}:

let
  langs = versions.languages;
in

baseShell.overrideAttrs (old: {
  name = "full";

  # All packages from ./packages.nix (single source of truth)
  # Using nativeBuildInputs (where mkShell's `packages` attribute is merged)
  nativeBuildInputs =
    old.nativeBuildInputs
    # IDE tools (neovim + tmux from programs, rest from packages.nix)
    ++ programs.neovim.packages
    ++ programs.tmux.packages
    ++ packages.idePackages
    # All languages from packages.nix
    ++ packages.pythonPackages
    ++ packages.goPackages
    ++ packages.nodejsPackages
    ++ packages.rustPackages
    # Atuin shell history (includes bash-preexec)
    ++ config.shell.atuin.packages
    # Container tooling (docker with compose v2 plugin)
    ++ (with pkgs; [ docker docker-compose docker-buildx ]);

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

    # Python: auto-activate venv if present (dynamic)
    if [ -d .venv ]; then
      source .venv/bin/activate 2>/dev/null || true
    fi

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
    export PATH="$GOBIN:$PNPM_HOME:$CARGO_HOME/bin:$PATH"

    echo "Full polyglot ready"
    echo "  Python ${langs.python.display} | Go ${langs.go.display}"
    echo "  Node.js ${langs.node.display} | Rust ${langs.rust.display}"

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
