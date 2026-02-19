{ pkgs }:
# =============================================================================
# Pulumi Python Environment (NixOS-native with python.withPackages)
# =============================================================================
#
# Provides Pulumi CLI with a properly-linked Python environment for the Python
# language runtime. Solves the native extension library loading issue where
# grpc and other C++ extensions fail to find libstdc++.so.6 in Python venvs.
#
# NixOS-native solution: Build Python packages through Nix instead of pip.
# All native extensions are correctly linked against Nix store library paths.
#
# Components:
# - pulumi CLI (from nixpkgs.pulumi)
# - pulumi-language-python (from nixpkgs.pulumiPackages.pulumi-python)
# - Python 3.13 with packages via python.withPackages:
#   - pulumi Python SDK
#   - pulumi-kubernetes provider
#   - All dependencies with native extensions (grpc, protobuf, etc.)
#
# Usage:
#   In devshells, replace individual pulumi packages with this single package.
#   The wrapper ensures pulumi-language-python uses this Python environment.
#
# References:
# - DeepWiki NixOS/nixpkgs: python.withPackages is the NixOS-native pattern
# - flake/src/devshells/konductor.nix:55 - Previous workaround attempt
# - infrastructure/.envrc - Temporary LD_LIBRARY_PATH workaround
#
let
  # Python 3.13 with Pulumi SDK and all dependencies
  pythonWithPulumi = pkgs.python313.withPackages (ps:
    with ps; [
      # Pulumi core SDK
      pulumi

      # Pulumi providers (Kubernetes is primary for infrastructure/)
      # Note: Add other providers as needed (aws, gcp, azure, etc.)
      # pulumi-aws
      # pulumi-gcp

      # Dependencies with native extensions (ensure proper linking)
      grpcio # C++ extension - primary issue
      grpcio-tools
      protobuf

      # Standard dependencies
      pyyaml
      requests
      semver
      dill
      # parver # If needed by Pulumi SDK
    ]);

  # Wrapper script for pulumi CLI that uses our Python environment
  # Sets PULUMI_PYTHON_CMD to point to our withPackages Python
  pulumiWrapper = pkgs.writeShellScriptBin "pulumi" ''
    export PULUMI_PYTHON_CMD="${pythonWithPulumi}/bin/python"
    exec ${pkgs.pulumi}/bin/pulumi "$@"
  '';

in
pkgs.symlinkJoin {
  name = "pulumi-with-python";
  paths = [
    pulumiWrapper # Wrapped pulumi CLI (uses pythonWithPulumi via PULUMI_PYTHON_CMD)
    pkgs.pulumi # Original pulumi (for other binaries)
    pkgs.pulumictl # Pulumi utilities
    pkgs.pulumiPackages.pulumi-python # Python language plugin
    # Note: pythonWithPulumi is NOT in paths to avoid shadowing system Python
    # The wrapper script sets PULUMI_PYTHON_CMD to use it for pulumi operations only
  ];
  meta = with pkgs.lib; {
    description = "Pulumi IaC with NixOS-native Python environment";
    homepage = "https://pulumi.com";
    license = licenses.asl20;
    platforms = platforms.unix;
  };
}
