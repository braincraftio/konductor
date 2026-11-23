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

  # Function of pkgs so claude-code.settings can use the formats.json type
  # (JSON-serializable values only) instead of types.anything.
  mkOptions =
    { pkgs }:
    {
      enable = lib.mkEnableOption "Konductor development environment";
      opencode = {
        package = lib.mkOption {
          type = lib.types.package;
          default = pkgs.opencode;
          defaultText = lib.literalExpression "pkgs.opencode";
          description = "OpenCode executable wrapped with the Konductor harness and runtime dependencies.";
        };
        settings = lib.mkOption {
          inherit (pkgs.formats.json { }) type;
          default = { };
          description = "Native V2 server settings merged recursively over Konductor defaults; lists replace whole.";
        };
        cli = lib.mkOption {
          inherit (pkgs.formats.json { }) type;
          default = { };
          description = "Native V2 CLI/TUI settings merged recursively over Konductor visibility defaults.";
        };
        environment = lib.mkOption {
          type = lib.types.attrsOf lib.types.str;
          default = { };
          description = "Explicit OpenCode wrapper environment overrides. Values enter the Nix store; use runtime credential references in settings instead of secrets here.";
        };
      };
      atuin = {
        package = lib.mkOption {
          type = lib.types.package;
          default = pkgs.atuin;
          defaultText = lib.literalExpression "pkgs.atuin";
          description = "Atuin build used by shells, the daemon, agent hooks, the MCP server, and the OpenCode plugin.";
        };
        settings = lib.mkOption {
          inherit (pkgs.formats.toml { }) type;
          default = { };
          example = lib.literalExpression "{ pty_proxy.enabled = false; output.enabled = false; }";
          description = ''
            Atuin config.toml settings merged recursively over Konductor defaults
            (src/config/shell/atuin.toml); lists replace whole. Defaults run one
            per-user daemon and one pty-proxy per interactive shell. Applied
            after the sync options, so raw keys here win.
          '';
        };
        sync = {
          enable = lib.mkEnableOption ''
            Atuin end-to-end encrypted sync of history and agent threads
            (auto_sync). Requires a one-time `atuin login` or `atuin register`
            per machine; every machine must use the same encryption key
          '';
          address = lib.mkOption {
            type = lib.types.str;
            default = "https://api.atuin.sh";
            description = "Sync server (sync_address): Atuin cloud or a self-hosted atuin-server.";
          };
          frequency = lib.mkOption {
            type = lib.types.str;
            default = "5m";
            description = "Sync interval for shells and the daemon (sync_frequency, daemon.sync_frequency).";
          };
          keyFile = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
            example = "/run/user/1000/secrets/atuin-key";
            description = ''
              Runtime path to the Atuin encryption key (key_path), e.g. a
              sops-nix or agenix secret. A string, never a Nix path, so the key
              is not copied into the store. null keeps Atuin's default location.
            '';
          };
        };
      };
      rtk = {
        enable = lib.mkEnableOption ''
          rtk command rewriting in the Claude Code and OpenCode harnesses
          (agent shell commands run as `rtk <cmd>` and return condensed output;
          Atuin keeps the full output)
        '';
        package = lib.mkOption {
          type = lib.types.package;
          default = pkgs.rtk.overrideAttrs { buildNoDefaultFeatures = true; };
          defaultText = lib.literalExpression "pkgs.rtk.overrideAttrs { buildNoDefaultFeatures = true; }";
          description = "rtk build. The default is the Apache-2.0 edition without the BUSL-1.1 rtk-engine.";
        };
        settings = lib.mkOption {
          inherit (pkgs.formats.toml { }) type;
          default = { };
          description = "rtk config.toml settings merged recursively over Konductor defaults (src/config/shell/rtk.nix); lists replace whole.";
        };
        posthook.enable = lib.mkEnableOption ''
          rtk PostToolUse output compression in Claude Code: writes
          ~/.config/rtk/pipeline.toml extending rtk:posthook and adds a
          PostToolUse `rtk hook claude` group (Bash, Read, Grep, Glob, WebFetch,
          WebSearch) after Atuin's. The model reads condensed tool output; Atuin
          output capture keeps raw Bash output. Requires an rtk-engine build
          (BUSL-1.1), e.g. konductor.rtk.package = pkgs.rtk; evaluation fails on
          the Apache-only default
        '';
      };
      claude-code.settings = lib.mkOption {
        inherit (pkgs.formats.json { }) type;
        default = { };
        description = ''
          Overrides for the wrapped Claude Code settings.json, merged onto the
          konductor defaults (src/harness/claude-code/settings.nix) with
          lib.recursiveUpdate. Attrsets merge per leaf (env keeps unset konductor
          keys); lists replace whole (availableModels is the full roster).
        '';
      };
    };

  # ===========================================================================
  # Atuin settings: typed sync options mapped to config.toml keys, then the
  # raw konductor.atuin.settings on top.
  # ===========================================================================

  mkAtuinSettings =
    atuin:
    lib.recursiveUpdate (
      lib.optionalAttrs atuin.sync.enable {
        auto_sync = true;
        sync_address = atuin.sync.address;
        sync_frequency = atuin.sync.frequency;
        daemon.sync_frequency = atuin.sync.frequency;
      }
      // lib.optionalAttrs (atuin.sync.keyFile != null) { key_path = atuin.sync.keyFile; }
    ) atuin.settings;

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
      claudeCodeSettings ? { },
      opencodeSettings ? { },
      opencodeCliSettings ? { },
      opencodeEnvironment ? { },
      opencodePackage ? pkgs.opencode,
      rtkEnable ? false,
      rtkSettings ? { },
      rtkPackage ? null,
      rtkPosthook ? false,
      atuinSettings ? { },
      atuinPackage ? pkgs.atuin,
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
          claudeCodeSettings
          opencodeSettings
          opencodeCliSettings
          opencodeEnvironment
          opencodePackage
          rtkEnable
          rtkSettings
          rtkPackage
          rtkPosthook
          atuinSettings
          atuinPackage
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
    ++ [ pkgs.nerd-fonts.jetbrains-mono ]
    # Rewritten agent commands invoke bare `rtk`.
    ++ lib.optional rtkEnable config.shell.rtk.package;

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
  # Home Files (config files not managed by programs.bash)
  # ===========================================================================

  mkHomeFiles =
    { config }:
    lib.recursiveUpdate
      {
        ".config/starship.toml".text = config.shell.starship.configContent;
        ".config/atuin/config.toml" = {
          source = "${config.shell.atuin.configFile}/config.toml";
          force = true;
        };
      }
      (
        lib.optionalAttrs config.rtkEnabled {
          ".config/rtk/config.toml" = {
            source = config.shell.rtk.configFile;
            force = true;
          };
        }
        // lib.optionalAttrs (config.rtkEnabled && config.shell.rtk.posthook) {
          ".config/rtk/pipeline.toml" = {
            source = config.shell.rtk.pipelineFile;
            force = true;
          };
        }
      );

  # ===========================================================================
  # programs.bash configuration
  # ===========================================================================
  # home-manager programs.bash generates .bashrc, .bash_profile, .profile.
  # targets.genericLinux sources hm-session-vars.sh in .bashrc for non-login shells.

  mkBashConfig = {
    enable = true;
    bashrcExtra = builtins.readFile ../config/shell/.bashrc_extra;
    initExtra = builtins.readFile ../config/shell/.bashrc;
    profileExtra = builtins.readFile ../config/shell/.bash_profile_extra;
  };

  # ===========================================================================
  # programs.readline replaces home.file .inputrc
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
  # Full Environment Variables
  # ===========================================================================
  # Merges env.nix with tool-specific config paths.
  # BASH_ENV excluded to prevent infinite recursion when tools like starship
  # spawn non-interactive bash subprocesses.

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
      SSL_CERT_FILE = sslCertFile;
      NIX_SSL_CERT_FILE = sslCertFile;
    };

  # ===========================================================================
  # Base Environment Variables
  # ===========================================================================

  mkEnv = import ../lib/env.nix;

  # ===========================================================================
  # Shell Aliases
  # ===========================================================================

  mkAliases = import ../lib/aliases.nix;
}
