# src/config/default.nix
# Aggregates all wrapped tools

{
  pkgs,
  lib,
  versions,
  catppuccinSources ? null,
  # Consumer settings.json overrides (module option konductor.claude-code.settings).
  # recursiveUpdate onto settings.nix: attrsets merge per leaf, lists replace whole.
  claudeCodeSettings ? { },
  ...
}:

let
  # Import languages to get pythonEnv for pyright wrapper.
  # languages.nix depends only on pkgs and versions (no circular dependency).
  languages = import ../packages/languages.nix { inherit pkgs versions lib; };

  # ===========================================================================
  # Linters
  # ===========================================================================
  linters = rec {
    shellcheck = import ./linters/shellcheck { inherit pkgs; };
    ruff = import ./linters/ruff { inherit pkgs; };
    yamllint = import ./linters/yamllint { inherit pkgs; };
    hadolint = import ./linters/hadolint { inherit pkgs; };
    eslint = import ./linters/eslint { inherit pkgs; };
    golangci-lint = import ./linters/golangci-lint { inherit pkgs; };
    mypy = import ./linters/mypy {
      inherit pkgs versions;
      inherit (languages) pythonEnv;
    };
    bandit = import ./linters/bandit { inherit pkgs versions; };
    markdownlint = import ./linters/markdownlint { inherit pkgs; };
    lychee = import ./linters/lychee { inherit pkgs; };
    commitlint = import ./linters/commitlint { inherit pkgs; };
    stylelint = import ./linters/stylelint { inherit pkgs; };
    htmlhint = import ./linters/htmlhint { inherit pkgs; };
    deadnix = import ./linters/deadnix { inherit pkgs; };
    statix = import ./linters/statix { inherit pkgs; };
    cspell = import ./linters/cspell { inherit pkgs; };
    actionlint = import ./linters/actionlint {
      inherit pkgs versions;
      shellcheck = shellcheck.package;
    };
    pyright = import ./linters/pyright {
      inherit pkgs;
      inherit (languages) pythonEnv;
    };
  };

  # ===========================================================================
  # Formatters
  # ===========================================================================
  formatters = rec {
    prettier = import ./formatters/prettier { inherit pkgs versions; };
    shfmt = import ./formatters/shfmt.nix { inherit pkgs; };
    taplo = import ./formatters/taplo { inherit pkgs; };
    biome = import ./formatters/biome { inherit pkgs; };
    nixfmt = import ./formatters/nixfmt.nix { inherit pkgs; };
    # Single formatting entrypoint (flake `formatter`, checks.treefmt, hooks)
    treefmt = import ./formatters/treefmt.nix {
      inherit pkgs;
      formatters = {
        inherit
          prettier
          shfmt
          taplo
          biome
          nixfmt
          ;
        inherit (linters) ruff;
      };
    };
  };
in
{
  # ===========================================================================
  # Shell Configuration
  # ===========================================================================
  shell = {
    bash = import ./shell/bash.nix { inherit pkgs lib versions; };
    starship = import ./shell/starship.nix { inherit pkgs; };
    git = import ./shell/git.nix { inherit pkgs lib; };
    ssh = import ./shell/ssh.nix { inherit pkgs; };
    atuin = import ./shell/atuin.nix { inherit pkgs; };
  };

  # ===========================================================================
  # CLI Tools Configuration
  # ===========================================================================
  tree = import ./tree { inherit pkgs; };

  # ===========================================================================
  # AI Tools Configuration
  # ===========================================================================
  opencode = import ./opencode { inherit pkgs lib; };

  # Claude Code harness — wrapped CLI + user-tier config + two plugins.
  # Exposes .package (the wrapped `claude`), .configDirDrv, .devshellHook,
  # .konductorPlugin, .practitionerPlugin, and .extend (lib.makeExtensible).
  # settingsDrv, configDirDrv and wrappedClaude read final.settings, so they
  # rebuild from the merged value.
  claude-code = (import ./claude-code { inherit pkgs lib; }).extend (
    _final: prev: { settings = lib.recursiveUpdate prev.settings claudeCodeSettings; }
  );

  # ===========================================================================
  # System Info Tools
  # ===========================================================================
  fastfetch = import ./fastfetch { inherit pkgs; };

  # ===========================================================================
  # Linters
  # ===========================================================================
  inherit linters formatters;
}
# k9s with Catppuccin Frappe theme (requires catppuccin/nix flake)
// lib.optionalAttrs (catppuccinSources != null) {
  k9s = import ./k9s { inherit pkgs catppuccinSources; };
  btop = import ./btop { inherit pkgs catppuccinSources; };
}
