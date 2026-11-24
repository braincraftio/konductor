# src/config/formatters/shfmt.nix
# Hermetic wrapper for shfmt
#
# Konductor enforces the printer settings below through flags. shfmt ignores
# EditorConfig formatting keys whenever a printer or parser flag is given, but
# still applies EditorConfig `ignore = true` rules; --apply-ignore extends that
# to explicitly named files (treefmt, hooks). Consuming repositories therefore
# supply only ignore rules; formatting is not overridable.
#
# `editorconfig` renders the same settings as an EditorConfig [[shell]]
# section (shebang-matched, so extensionless scripts are covered) for editors.
# checks.editorconfig fails when the repository .editorconfig drifts from it.

{ pkgs }:

let
  inherit (pkgs) lib;

  settings = {
    indent = 4;
    caseIndent = true;
    spaceRedirects = true;
    binaryNextLine = true;
  };

  flags = [
    "-i"
    (toString settings.indent)
  ]
  ++ lib.optional settings.caseIndent "-ci"
  ++ lib.optional settings.spaceRedirects "-sr"
  ++ lib.optional settings.binaryNextLine "-bn";

  editorconfig = ''
    [[shell]]
    indent_style = space
    indent_size = ${toString settings.indent}
    switch_case_indent = ${lib.boolToString settings.caseIndent}
    space_redirects = ${lib.boolToString settings.spaceRedirects}
    binary_next_line = ${lib.boolToString settings.binaryNextLine}
  '';
in
{
  package = pkgs.writeShellApplication {
    name = "shfmt";
    runtimeInputs = [ pkgs.shfmt ];
    text = ''
      exec shfmt ${lib.escapeShellArgs flags} --apply-ignore "$@"
    '';
  };

  unwrapped = pkgs.shfmt;
  configFile = null; # settings are flags; see `editorconfig`
  inherit settings flags editorconfig;

  meta = {
    description = "Shell script formatter with Konductor printer settings";
    configurable = false;
  };
}
