{ pkgs, pythonEnv ? null }:
# =============================================================================
# Pulumi Python Environment (NixOS-native with python.withPackages)
# =============================================================================
#
# Provides Pulumi CLI and the list of Python packages needed by
# infrastructure/pulumi/src/. The Python packages are merged into the single
# python.withPackages call in languages.nix to avoid PATH collisions between
# multiple Python environments.
#
# pythonEnv parameter: when provided (by languages.nix), the Pulumi wrapper and
# env use this single derivation instead of building separate copies. This
# eliminates duplicate store paths for identical withPackages environments.
#
# All native extensions (grpc, protobuf, bcrypt, etc.) are correctly linked
# against Nix store library paths -- no LD_LIBRARY_PATH workarounds needed.
#
# Provider SDKs available from nixpkgs (nixos-25.11): pulumi, pulumi-random
# Provider SDKs built from PyPI wheels: pulumi-kubernetes, pulumi-tls,
#   pulumi-docker-build, pulumi-cloudflare
#   (all four are pure Python wheels: py3-none-any)
#
let
  inherit (pkgs) lib;

  # =========================================================================
  # Provider SDKs not in nixpkgs -- built from PyPI wheels
  # =========================================================================
  # All four are pure Python (py3-none-any) with identical deps: parver, pulumi, semver
  # These are already satisfied by nixpkgs python313Packages.

  # fetchPypi format="wheel" constructs incorrect URLs (py2.py3 prefix path).
  # Use fetchurl with exact PyPI content-addressed URLs instead.
  mkPulumiPypiPackage = { pname, version, url, hash, meta ? {} }:
    pkgs.python313Packages.buildPythonPackage {
      inherit pname version;
      format = "wheel";

      src = pkgs.fetchurl {
        inherit url hash;
      };

      propagatedBuildInputs = with pkgs.python313Packages; [
        parver
        pulumi
        semver
      ];

      # No tests in provider SDK wheels
      doCheck = false;

      pythonImportsCheck = [ pname ];

      meta = with lib; {
        license = licenses.asl20;
      } // meta;
    };

  pulumiKubernetes = mkPulumiPypiPackage {
    pname = "pulumi_kubernetes";
    version = "4.29.0";
    url = "https://files.pythonhosted.org/packages/bd/71/596f4b03c340cda2439bf49770ddb17a9656fe3471b4a9b67b33295526ae/pulumi_kubernetes-4.29.0-py3-none-any.whl";
    hash = "sha256-QjvULbwbtSHVGKvRbnsdAjQQR/CIUsZcX34K/dijKEY=";
    meta.description = "Pulumi Kubernetes provider SDK";
  };

  pulumiTls = mkPulumiPypiPackage {
    pname = "pulumi_tls";
    version = "5.2.1";
    url = "https://files.pythonhosted.org/packages/3c/12/f5035bbfe624279a4838ec824ec8a6d34e9351f6780def8c2ab0ce965a0c/pulumi_tls-5.2.1-py3-none-any.whl";
    hash = "sha256-AhdSNH7gOBvjGDlpGV09vqOWltPWutHBn3kLl24ttiI=";
    meta.description = "Pulumi TLS provider SDK";
  };

  pulumiDockerBuild = mkPulumiPypiPackage {
    pname = "pulumi_docker_build";
    version = "0.0.14";
    url = "https://files.pythonhosted.org/packages/72/a0/7f8b89aed8ef77aa16dde4d3bff9254035a77e597d21c450f8c32d3db6c8/pulumi_docker_build-0.0.14-py3-none-any.whl";
    hash = "sha256-GDHh6gydMw3uHa322aJt15yroJPKfJauiCGrXZJTvy8=";
    meta.description = "Pulumi Docker Build provider SDK";
  };

  pulumiCloudflare = mkPulumiPypiPackage {
    pname = "pulumi_cloudflare";
    version = "6.14.0";
    url = "https://files.pythonhosted.org/packages/68/97/e6f11adbd919ad41ab920b137b7a711e3eb1e8130602a4c29d0ae86d329f/pulumi_cloudflare-6.14.0-py3-none-any.whl";
    hash = "sha256-zddaTkE+3ajpn5hK31fL1szM7Krs4bWHdt7YbMpDgUo=";
    meta.description = "Pulumi Cloudflare provider SDK";
  };

  # =========================================================================
  # pyright — required as a Python package for two consumers:
  # 1. Pulumi's language plugin (Pulumi.yaml typechecker: pyright) runs
  #    pyright as a subprocess and expects it in pythonEnv/bin/
  # 2. The hermetic CLI wrapper (config/linters/pyright/) provides
  #    --pythonpath injection for direct terminal/CI invocations
  # =========================================================================
  pyrightPkg = pkgs.python313Packages.buildPythonPackage {
    pname = "pyright";
    version = "1.1.407";
    format = "wheel";

    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/dc/93/b69052907d032b00c40cb656d21438ec00b3a471733de137a3f65a49a0a0/pyright-1.1.407-py3-none-any.whl";
      hash = "sha256-bdQZ9U/ME/A7UihXltZeY5eGNz9DPiQ/i5TPk6dETSE=";
    };

    propagatedBuildInputs = with pkgs.python313Packages; [
      nodeenv
      typing-extensions
    ];

    doCheck = false;

    meta = with lib; {
      description = "Python command line wrapper for pyright";
      license = licenses.mit;
    };
  };

  # =========================================================================
  # Python packages for python.withPackages (merged in languages.nix)
  # =========================================================================
  # This is a function that takes the python package set (ps) and returns
  # the list of packages to include. languages.nix calls this to merge
  # Pulumi deps into the single python.withPackages environment.
  # Defined in `let` so `package` and `env` can reference it without self-import.
  pythonDeps = ps: [
    # Pulumi core SDK (nixpkgs: 3.192.0)
    ps.pulumi

    # Pulumi provider SDKs -- from nixpkgs (nixos-25.11)
    ps."pulumi-random"      # nixpkgs: 4.14.0

    # Pulumi provider SDKs -- from PyPI wheels (not in nixos-25.11 python313Packages)
    pulumiKubernetes      # 4.29.0
    pulumiTls             # 5.2.1
    pulumiDockerBuild     # 0.0.14
    pulumiCloudflare      # 6.14.0

    # Dependencies with native extensions (ensure proper linking)
    ps.grpcio       # C++ extension -- the original motivation for this approach
    ps."grpcio-tools"
    ps.protobuf

    # Runtime dependencies from infrastructure/pulumi/pyproject.toml
    ps.bcrypt       # Password hashing for Docker registry htpasswd
    ps.pydantic     # Data validation using Python type annotations
    ps.semver       # Semantic version parsing for git tags
    ps.gitpython    # Git operations without subprocess calls
    ps.kubernetes   # Kubernetes Python client for cluster metadata discovery
    ps.pyyaml       # YAML parsing for kubeconfig
    ps.packaging    # Version parsing for Helm chart resolution

    # Transitive deps (explicitly listed for clarity)
    ps.requests
    ps.dill
    ps.parver
    ps.setuptools   # Required by some provider SDKs at runtime

    # DO NOT REMOVE: Pulumi.yaml sets typechecker: pyright which causes
    # pulumi-language-python to run pyright as a subprocess from
    # pythonEnv/bin/. Removing pyrightPkg from this list breaks
    # pulumi preview/up with:
    #   "The typechecker option is set to pyright, but pyright is
    #    not installed"
    # The hermetic CLI wrapper (config/linters/pyright/) serves a
    # different purpose: direct terminal/CI invocations with
    # --pythonpath for nix site-packages resolution.
    pyrightPkg
  ];

in
{
  # Re-export pythonDeps for languages.nix to merge into python.withPackages
  inherit pythonDeps;

  # =========================================================================
  # Pulumi CLI package (for cli.nix)
  # =========================================================================
  # The symlinkJoin containing pulumi CLI, wrapper, and language plugin.
  # Uses pythonEnv from languages.nix (single derivation for all consumers).
  package = let
    resolvedPythonEnv = assert pythonEnv != null; pythonEnv;
    pulumiWrapper = pkgs.writeShellScriptBin "pulumi" ''
      export PULUMI_PYTHON_CMD="${resolvedPythonEnv}/bin/python"
      exec ${pkgs.pulumi}/bin/pulumi "$@"
    '';
  in pkgs.symlinkJoin {
    name = "pulumi-with-python";
    paths = [
      pkgs.pulumi                            # Original pulumi (for other binaries)
      pkgs.pulumictl                         # Pulumi utilities
      pkgs.pulumiPackages.pulumi-python      # Python language plugin
      pulumiWrapper                          # Last: wrapper wins symlinkJoin conflict (sets PULUMI_PYTHON_CMD)
    ];
    meta = with pkgs.lib; {
      description = "Pulumi IaC with NixOS-native Python environment";
      homepage = "https://pulumi.com";
      license = licenses.asl20;
      platforms = platforms.unix;
    };
  };

  # =========================================================================
  # Environment variables for devshells
  # =========================================================================
  env = let
    resolvedPythonEnv = assert pythonEnv != null; pythonEnv;
  in {
    PULUMI_PYTHON_CMD = "${resolvedPythonEnv}/bin/python";
  };
}
