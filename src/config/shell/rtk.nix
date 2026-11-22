# src/config/shell/rtk.nix
# rtk (Rust Token Killer): rewrites agent shell commands to `rtk <cmd>` so the
# agent reads condensed output. Opt-in; Atuin remains the system of record for
# commands and full output.
#
# Edition: Apache-2.0 only (no BUSL rtk-engine): command rewriting and built-in
# filters; no pipelines, PostToolUse compression, proxy, or model routing.
#
# Delivery:
#   configFile    → ~/.config/rtk/config.toml via home-manager (mkHomeFiles).
#     rtk reads config only from dirs::config_dir()/rtk/config.toml; there is
#     no path override variable.
#   env           → kill switches for surfaces without a managed home
#     (devshells, CI, harness wrappers). These match the config defaults.
#
# Defaults (distributable, Atuin-first):
#   retriever.mode = "disabled"  Atuin output capture holds the full output
#   telemetry.enabled = false    no network calls
#   display.pro_hint = false     no upsell line in `rtk gain`
#   hooks.suppress_hook_warning  hooks are rendered by konductor, not `rtk init`
#   tracking kept on             `rtk gain` still reports savings

{
  pkgs,
  lib,
  settings ? { },
  package ? null,
}:

let
  tomlFmt = pkgs.formats.toml { };

  # buildNoDefaultFeatures drops the default `engine` feature. Applied through
  # overrideAttrs so it holds for every nixpkgs rtk revision the lock can carry.
  defaultPackage = pkgs.rtk.overrideAttrs { buildNoDefaultFeatures = true; };

  baseSettings = {
    tracking.enabled = true;
    retriever.mode = "disabled";
    telemetry.enabled = false;
    display.pro_hint = false;
    hooks.suppress_hook_warning = true;
  };

  finalSettings = lib.recursiveUpdate baseSettings settings;
  configFile = tomlFmt.generate "rtk-config.toml" finalSettings;
in
{
  package = if package == null then defaultPackage else package;
  settings = finalSettings;
  inherit configFile;

  env = {
    RTK_RECALL = "0";
    RTK_TELEMETRY_DISABLED = "1";
    RTK_SUPPRESS_HOOK_WARNING = "1";
  };
}
