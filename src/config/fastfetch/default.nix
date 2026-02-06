# src/config/fastfetch/default.nix
# Fastfetch system info wrapper - exhaustive VM state enumeration
#
# The wrapper forces config via --config flag.
# Config is SSOT in fastfetch.jsonc alongside this file.
#
# Usage:
#   ff          # Run with Konductor config (comprehensive, no logo)
#   ff --help   # Show fastfetch help
#
# The config is optimized for:
# - Build logs (text-only, no ANSI art)
# - Serial console output (cloud-init, kubernetes logging)
# - Interactive terminal use

{ pkgs }:

let
  # Slurp the config file
  configContent = builtins.readFile ./fastfetch.jsonc;

  # Config file - written to nix store
  configFile = pkgs.writeTextFile {
    name = "konductor-fastfetch-config";
    destination = "/fastfetch.jsonc";
    text = configContent;
  };

in
{
  # Wrapped fastfetch that forces hermetic config
  package = pkgs.writeShellApplication {
    name = "ff";
    runtimeInputs = [ pkgs.fastfetch ];
    text = ''
      exec fastfetch --config "${configFile}/fastfetch.jsonc" "$@"
    '';
  };

  # Unwrapped fastfetch for direct access
  unwrapped = pkgs.fastfetch;

  # Config file and content (for consumers like qcow2, oci)
  inherit configFile;
  inherit configContent;

  # Metadata
  meta = {
    description = "Fastfetch system info with comprehensive Konductor config";
    configurable = true;
  };
}
