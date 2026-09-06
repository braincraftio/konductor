# src/modules/common.nix
# Shared module options and package logic
#
# Pattern: mirrors src/devshells/default.nix and src/qcow2/default.nix
# catppuccinSources flows from flake inputs → module → mkPackages → config → packages
#
# Exports:
#   mkOptions    - NixOS/HM/darwin option definitions
#   mkPackages   - Full devshell packages (SSOT: packages/default.nix fullPackages)
#   mkPrograms   - IDE program packages: neovim, tmux, ttyd (for home.packages)
#   mkHomeFiles  - Config files for home.file (bashrc, starship, atuin, etc.)
#   mkFullEnv    - All environment variables including tool config paths
#   mkEnv        - Base environment variables (EDITOR, PAGER, etc.)
#   mkAliases    - Shell aliases

{ lib }:

{
  # ===========================================================================
  # Shared Option Definitions
  # ===========================================================================

  mkOptions = {
    enable = lib.mkEnableOption "Konductor development environment";
  };

  # ===========================================================================
  # Package Builder (called by platform modules)
  # ===========================================================================
  # Mirrors the package composition in src/devshells/default.nix:
  #   catppuccinSources → config → packages → composed list

  mkPackages =
    {
      pkgs,
      lib,
      versions,
      catppuccinSources,
    }:
    let
      # Config provides wrapped linters/formatters with hermetic configuration
      # catppuccinSources enables k9s Catppuccin theme (same as devshells + qcow2)
      config = import ../config {
        inherit
          pkgs
          lib
          versions
          catppuccinSources
          ;
      };

      # Single source of truth for package composition
      packages = import ../packages {
        inherit
          pkgs
          lib
          config
          versions
          ;
      };
    in
    # fullPackages = base + IDE + all languages + container tooling (SSOT with full.nix)
    packages.fullPackages
    ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux packages.konductor.packages
    ++ [ pkgs.nerd-fonts.jetbrains-mono ];

  # ===========================================================================
  # Program Packages (IDE tools: neovim, tmux, ttyd)
  # ===========================================================================
  # Same composition as src/devshells/konductor.nix nativeBuildInputs
  # Requires programs and packages from the caller (needs flake inputs for nixvim)

  mkPrograms =
    { programs, packages }:
    programs.neovim.packages
    ++ programs.tmux.packages
    ++ programs.ttyd.packages
    ++ packages.idePackages;

  # ===========================================================================
  # Home Files (config files NOT managed by programs.bash)
  # ===========================================================================

  mkHomeFiles =
    { config }:
    {
      ".config/starship.toml".text = config.shell.starship.configContent;
      ".config/atuin/config.toml" = {
        text = config.shell.atuin.configContent;
        force = true;
      };
    };

  # ===========================================================================
  # programs.bash configuration (replaces home.file .bashrc/.bash_profile/.inputrc)
  # ===========================================================================
  # home-manager's programs.bash generates .bashrc, .bash_profile, .profile.
  # targets.genericLinux sources hm-session-vars.sh in .bashrc for non-login shells.
  # Starship/atuin/direnv hooks in initExtra — packages from fullPackages, not programs.*.

  mkBashConfig = {
    enable = true;

    historyControl = [ "ignoreboth" ];
    shellOptions = [
      "histappend"
      "checkwinsize"
      "globstar"
      "cdspell"
    ];

    # Non-interactive content (runs before the [[ $- == *i* ]] guard)
    bashrcExtra = ''
      # Source *.sh from ~/.bashrc.d/ for host-specific configuration
      if [ -d "$HOME/.bashrc.d" ] && [[ $- == *i* ]]; then
        for f in "$HOME/.bashrc.d"/*.sh; do
          [ -f "$f" ] && source "$f"
        done
      fi

      # Clear aliases that conflict with wrapper scripts in PATH
      unalias cat 2>/dev/null || true
      unalias grep 2>/dev/null || true
    '';

    # Interactive content (after history, options, aliases)
    initExtra = ''
      alias rm='rm -i'
      alias cp='cp -i'
      alias mv='mv -i'
      alias gs='git status'
      alias gd='git diff'
      alias gl='git log --oneline -20'

      # Starship prompt (skip dumb terminals)
      [[ "''${TERM:-dumb}" != "dumb" ]] && [ -t 0 ] && eval "$(starship init bash)"

      # Atuin shell history (requires bash-preexec)
      if [[ "''${TERM:-dumb}" != "dumb" ]] && [ -t 0 ]; then
        [ -n "$KONDUCTOR_PREEXEC_PATH" ] && [ -f "$KONDUCTOR_PREEXEC_PATH" ] && source "$KONDUCTOR_PREEXEC_PATH"
        eval "$(atuin init bash)"
      fi

      # Direnv
      export DIRENV_LOG_FORMAT="''${DIRENV_LOG_FORMAT:-}"
      eval "$(direnv hook bash)"
    '';

    # Login shell content (.bash_profile / .profile)
    profileExtra = ''
      # Nix PATH guard — prevent nix-daemon.sh from re-prepending nix paths
      if [[ ":$PATH:" == *"/.nix-profile/bin:"* ]]; then
        __ETC_PROFILE_NIX_SOURCED=1
      fi

      if [ -f /etc/profile ] && [ "$(uname)" != "Darwin" ]; then
        source /etc/profile
      fi

      export __ETC_PROFILE_NIX_SOURCED=1

      # Deduplicate XDG_DATA_DIRS
      if [ -n "''${XDG_DATA_DIRS:-}" ]; then
        XDG_DATA_DIRS="$(printf '%s' "$XDG_DATA_DIRS" | awk -v RS=: -v ORS=: '!seen[$0]++')"
        XDG_DATA_DIRS="''${XDG_DATA_DIRS%:}"
        export XDG_DATA_DIRS
      fi
    '';
  };

  # ===========================================================================
  # programs.readline (replaces home.file .inputrc)
  # ===========================================================================

  mkReadlineConfig = {
    variables = {
      enable-keypad = true;
      input-meta = true;
      output-meta = true;
      convert-meta = false;
      completion-ignore-case = true;
      show-all-if-ambiguous = true;
      colored-stats = true;
    };
    bindings = {
      "\\e[A" = "previous-history";
      "\\e[B" = "next-history";
      "\\e[C" = "forward-char";
      "\\e[D" = "backward-char";
      "\\e[H" = "beginning-of-line";
      "\\e[F" = "end-of-line";
      "\\e[3~" = "delete-char";
    };
  };

  # ===========================================================================
  # Full Environment Variables (base + tool config paths)
  # ===========================================================================
  # Merges env.nix (EDITOR, PAGER, etc.) with tool-specific config paths
  # (KONDUCTOR_BASHRC, ATUIN_CONFIG_DIR, KONDUCTOR_PREEXEC_PATH, etc.)
  #
  # BASH_ENV is excluded: it points to the konductor bashrc which causes
  # infinite recursion when tools like starship spawn non-interactive bash
  # subprocesses (BASH_ENV → bashrc → starship init → bash → BASH_ENV → ...).
  # QCOW2 sets BASH_ENV="/etc/set-environment" (NixOS-specific) instead.
  # For home-manager, .bash_profile → .bashrc handles interactive shells.

  mkFullEnv =
    {
      config,
      sslCertFile ? "/etc/ssl/certs/ca-certificates.crt",
    }:
    import ../lib/env.nix
    // (builtins.removeAttrs config.shell.bash.env [ "BASH_ENV" ])
    // config.shell.atuin.env
    // {
      KONDUCTOR = "true";
      # Override NixOS-specific ca-bundle.crt path from env.nix
      # Non-NixOS distros (Ubuntu, Pop!_OS, Debian) use ca-certificates.crt
      SSL_CERT_FILE = sslCertFile;
      NIX_SSL_CERT_FILE = sslCertFile;
    };

  # ===========================================================================
  # Base Environment Variables (imported from SSOT)
  # ===========================================================================

  mkEnv = import ../lib/env.nix;

  # ===========================================================================
  # Shell Aliases (imported from SSOT)
  # ===========================================================================

  mkAliases = import ../lib/aliases.nix;
}
