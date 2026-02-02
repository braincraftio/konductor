# src/lib/aliases.nix
# SSOT for ALL shell aliases across ALL targets
# NO DUPLICATION - this is the ONLY place where aliases are defined

{
  # ===========================================================================
  # Modern CLI Replacements
  # ===========================================================================
  k = "kubecolor";
  ll = "eza -la --git";
  la = "eza -la";
  l = "eza -l";
  # cat - handled specially in alias-wrappers.nix (uses bat when interactive, real cat when piped)
  find = "fd";
  top = "btm";
  du = "dust";
  # tree: ignore dev noise but show ops data (cache, logs, configs)
  # Patterns: bytecode, venvs, node_modules, tool caches, build outputs, IDE dirs
  tree = "eza --tree --group-directories-first --icons -I '__pycache__|.git|node_modules|.venv|venv|.pytest_cache|.mypy_cache|.ruff_cache|.direnv|.DS_Store|*.pyc|.coverage|.tox|.nox|target|.cargo|.go|dist|build|.astro|.playwright|*.egg-info|.eggs|htmlcov|.hypothesis|__pypackages__|.pixi|.lycheecache|.idea|result|result-*|.nix-profile|.nix-gcroots'";

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
  rr = "runme run";
  rl = "runme beta list";
}
