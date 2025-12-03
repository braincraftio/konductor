# src/lib/aliases.nix
# SSOT for ALL shell aliases across ALL targets
# NO DUPLICATION - this is the ONLY place where aliases are defined

{
  # ===========================================================================
  # Modern CLI Replacements
  # ===========================================================================
  ll = "eza -la --git";
  la = "eza -la";
  l = "eza -l";
  cat = "bat --paging=never";
  grep = "rg";
  find = "fd";
  top = "btm";
  du = "dust";
  tree = "eza --tree";

  # ===========================================================================
  # Editor Shortcuts
  # ===========================================================================
  vi = "nvim";
  vim = "nvim";

  # ===========================================================================
  # Git Shortcuts
  # ===========================================================================
  gs = "git status";
  gd = "git diff";
  gl = "git log --oneline -20";
  lg = "lazygit";

  # ===========================================================================
  # Task Automation
  # ===========================================================================
  mr = "mise run";
}
