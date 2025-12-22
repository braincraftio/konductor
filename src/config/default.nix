# src/config/default.nix
# Aggregates all wrapped tools

{ pkgs, lib, versions, ... }:

{
  # ===========================================================================
  # Shell Configuration
  # ===========================================================================
  shell = {
    bash = import ./shell/bash.nix { inherit pkgs lib versions; };
    starship = import ./shell/starship.nix { inherit pkgs; };
    git = import ./shell/git.nix { inherit pkgs lib; };
    ssh = import ./shell/ssh.nix { inherit pkgs; };
  };

  # ===========================================================================
  # Linters
  # ===========================================================================
  linters = {
    shellcheck = import ./linters/shellcheck { inherit pkgs; };
    ruff = import ./linters/ruff { inherit pkgs; };
    yamllint = import ./linters/yamllint { inherit pkgs; };
    hadolint = import ./linters/hadolint { inherit pkgs; };
    eslint = import ./linters/eslint { inherit pkgs; };
    golangci-lint = import ./linters/golangci-lint { inherit pkgs; };
    mypy = import ./linters/mypy { inherit pkgs; };
    bandit = import ./linters/bandit { inherit pkgs versions; };
    markdownlint = import ./linters/markdownlint { inherit pkgs; };
    lychee = import ./linters/lychee { inherit pkgs; };
    commitlint = import ./linters/commitlint { inherit pkgs; };
    stylelint = import ./linters/stylelint { inherit pkgs; };
    htmlhint = import ./linters/htmlhint { inherit pkgs; };
  };

  # ===========================================================================
  # Formatters
  # ===========================================================================
  formatters = {
    prettier = import ./formatters/prettier { inherit pkgs; };
    shfmt = import ./formatters/shfmt.nix { inherit pkgs; };
    taplo = import ./formatters/taplo { inherit pkgs; };
    biome = import ./formatters/biome { inherit pkgs; };
  };
}
