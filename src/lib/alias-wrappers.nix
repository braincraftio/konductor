# src/lib/alias-wrappers.nix
# Creates executable wrapper scripts from aliases.nix with proper bash completions
#
# This provides hermetic "aliases" that work with direnv (which can't export shell aliases).
# Uses installShellCompletion from installShellFiles hook for proper completion registration.
#
# For wrappers of commands with completions (kubectl, git, etc.), we:
# 1. Generate completion script from underlying command
# 2. Register our wrapper to use the same completion function

{ pkgs, lib, ... }:

let
  aliases = import ./aliases.nix;
in
pkgs.stdenv.mkDerivation {
  pname = "konductor-alias-wrappers";
  version = "1.0.0";

  # No source - we generate everything
  dontUnpack = true;

  # Setup hook: adds this package's share/ to XDG_DATA_DIRS
  # This enables bash-completion to discover our completion files
  # when this package is used in mkShell
  # $1 = path to this package when setup hook is sourced
  setupHook = pkgs.writeText "alias-wrappers-setup-hook" ''
    addToSearchPath XDG_DATA_DIRS "$1/share"
  '';

  # Build-time dependencies - commands needed to generate completions
  # These are in PATH during installPhase
  nativeBuildInputs = with pkgs; [
    installShellFiles
    unstable.kubectl  # For kubectl completion bash
    unstable.mise     # For mise completion bash
    git               # For git completion (already has completions)
  ];

  installPhase = ''
    runHook preInstall

    mkdir -p $out/bin

    # Create wrapper scripts for each alias
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: command: ''
      command cat > $out/bin/${name} << 'WRAPPER'
    #!/usr/bin/env bash
    exec ${command} "$@"
    WRAPPER
      chmod +x $out/bin/${name}
    '') aliases)}

    # Smart cat wrapper: bat when interactive (TTY), real cat when piped
    # This prevents ANSI escape codes from breaking piped output
    command cat > $out/bin/cat << CATWRAPPER
    #!/usr/bin/env bash
    if [ -t 1 ]; then
      # stdout is a TTY - use bat with decorations
      exec ${pkgs.bat}/bin/bat --paging=never "\$@"
    else
      # stdout is piped - use plain cat
      exec ${pkgs.coreutils}/bin/cat "\$@"
    fi
    CATWRAPPER
    chmod +x $out/bin/cat

    # Generate completions for kubectl wrapper (k)
    # kubectl completion bash generates the full completion script
    kubectl completion bash > k-completion.bash
    # Add completion registration for our 'k' wrapper
    echo 'complete -o default -F __start_kubectl k' >> k-completion.bash
    installShellCompletion --bash --name k.bash k-completion.bash

    # Generate completions for mise wrapper (mr)
    mise completion bash > mr-completion.bash
    echo 'complete -o default -F _mise mr' >> mr-completion.bash
    installShellCompletion --bash --name mr.bash mr-completion.bash

    runHook postInstall
  '';

  meta = {
    description = "Executable wrappers for Konductor shell aliases with bash completions";
    priority = 0;  # Higher priority to override system commands
  };
}
