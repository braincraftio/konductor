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
# Pulumi CLI + Python language host: pkgs.unstable.pulumi-bin (3.244.0, a single
# Go binary bundle). The Python SDK and provider SDKs are built from PyPI wheels
# pinned to the versions in infrastructure/pulumi/pyproject.toml, against the
# stable python313Packages set. nixpkgs python313Packages.pulumi (3.192) is too
# old for the provider SDKs (>=3.231), and stable pulumi-bin (3.207) is too old
# to match the wheeled SDK; both come from unstable/wheels to reach 3.244.
#
let
  inherit (pkgs) lib;

  # =========================================================================
  # Pulumi Python SDK -- PyPI wheel (nixpkgs python313Packages.pulumi is too old
  # for the provider SDKs, which require a newer pulumi core).
  # =========================================================================
  # fetchPypi format="wheel" constructs incorrect URLs (py2.py3 prefix path).
  # Use fetchurl with exact PyPI content-addressed URLs instead.
  pulumiCore = pkgs.python313Packages.buildPythonPackage {
    pname = "pulumi";
    version = "3.244.0";
    format = "wheel";

    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/37/54/f6b4ab6ffba2cfbb70f7e1188c81f5805ce740ee34d2ce3d325a0d043ab3/pulumi-3.244.0-py3-none-any.whl";
      hash = "sha256-ujZcEzkUBDt4SJBtt6xGsfuStjLHfwnIOOyiclAfnww=";
    };

    # Runtime deps per the wheel's Requires-Dist (pulumi 3.244.0). Sourced from
    # the same python313Packages set as the shared withPackages env so the
    # single-interpreter invariant holds (languages.nix builds the env from
    # the stable python313).
    propagatedBuildInputs = with pkgs.python313Packages; [
      debugpy
      dill
      grpcio
      packaging
      protobuf
      pyyaml
      semver
      pkgs.python313Packages."opentelemetry-api"
      pkgs.python313Packages."opentelemetry-sdk"
      pkgs.python313Packages."opentelemetry-exporter-otlp-proto-grpc"
      pkgs.python313Packages."opentelemetry-instrumentation-grpc"
    ];

    doCheck = false;
    pythonImportsCheck = [ "pulumi" ];

    meta = with lib; {
      description = "Pulumi Python SDK";
      license = licenses.asl20;
    };
  };

  # =========================================================================
  # Provider SDKs -- PyPI wheels (pure Python: py3-none-any)
  # =========================================================================
  # Each depends on the wheeled pulumiCore above (not nixpkgs pulumi) so the
  # provider/SDK versions stay mutually compatible.
  mkPulumiPypiPackage = { pname, version, url, hash, meta ? {} }:
    pkgs.python313Packages.buildPythonPackage {
      inherit pname version;
      format = "wheel";

      src = pkgs.fetchurl {
        inherit url hash;
      };

      propagatedBuildInputs = [
        pulumiCore
        pkgs.python313Packages.parver
        pkgs.python313Packages.semver
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
    version = "4.32.0";
    url = "https://files.pythonhosted.org/packages/3a/12/8e2cb7dd2f6dbd24c4bb3225e161c7a04675a81a9a335b66f3a3430850a8/pulumi_kubernetes-4.32.0-py3-none-any.whl";
    hash = "sha256-duL5aBlLrRdnR8PKn539P8hWOVKJsBTaJo1V2AXvhm0=";
    meta.description = "Pulumi Kubernetes provider SDK";
  };

  pulumiTls = mkPulumiPypiPackage {
    pname = "pulumi_tls";
    version = "5.5.0";
    url = "https://files.pythonhosted.org/packages/b9/4f/e3ec5f28ea46733ba58fa244e5e7d011038e57c27ac02bf6b93efebe17f4/pulumi_tls-5.5.0-py3-none-any.whl";
    hash = "sha256-p78na09SWw61eM3KfBnobWqNHZRIEixKmj5LUZF0YKE=";
    meta.description = "Pulumi TLS provider SDK";
  };

  pulumiDockerBuild = mkPulumiPypiPackage {
    pname = "pulumi_docker_build";
    version = "0.0.19";
    url = "https://files.pythonhosted.org/packages/eb/dd/b065b43d67a6c0134ea4dae90828eb5b595f704a3fe2e5bb4b4efd0d4450/pulumi_docker_build-0.0.19-py3-none-any.whl";
    hash = "sha256-lfFBTYBRjyUxa44rSZI0FsETEJ9RRHqEflhXwh7+YhE=";
    meta.description = "Pulumi Docker Build provider SDK";
  };

  pulumiCloudflare = mkPulumiPypiPackage {
    pname = "pulumi_cloudflare";
    version = "6.17.0";
    url = "https://files.pythonhosted.org/packages/b6/11/d82a291b33486227e58f2b01f2908001609757f1abb29a7c1335ecd4a2bc/pulumi_cloudflare-6.17.0-py3-none-any.whl";
    hash = "sha256-64JWLWl+Bu4JQFqdd2dae/hlLDnmb2qb3pm3OyFZZpA=";
    meta.description = "Pulumi Cloudflare provider SDK";
  };

  pulumiRandom = mkPulumiPypiPackage {
    pname = "pulumi_random";
    version = "4.21.0";
    url = "https://files.pythonhosted.org/packages/d0/bc/168881eeb54804c1506a5349c3aaf0933bc09f54081c50343ed485fa4c16/pulumi_random-4.21.0-py3-none-any.whl";
    hash = "sha256-0masuKUIUfBXa86lqlgsroltNPc/vmPVNt+uDNEkWYE=";
    meta.description = "Pulumi Random provider SDK";
  };

  pulumiAws = mkPulumiPypiPackage {
    pname = "pulumi_aws";
    version = "7.34.0";
    url = "https://files.pythonhosted.org/packages/3b/1c/198d10e93ab2cc597a5628be5dc82a81014d3b81f17e1e4d3d3bf7041624/pulumi_aws-7.34.0-py3-none-any.whl";
    hash = "sha256-ae385aMbqMULENtR8Ip6t8MT0q9xKcdLIQW9+vxTaP4=";
    meta.description = "Pulumi AWS provider SDK";
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
    version = "1.1.410";
    format = "wheel";

    src = pkgs.fetchurl {
      url = "https://files.pythonhosted.org/packages/d7/33/288b5868fa00846dacf249633719d747893e54aebd196b9968ac1878a5d3/pyright-1.1.410-py3-none-any.whl";
      hash = "sha256-XpYb7TfKz5az9817HaObNQqSOaouaRONDoj3KM+vKWw=";
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
    # Pulumi core SDK -- PyPI wheel
    pulumiCore            # 3.244.0

    # Pulumi provider SDKs -- PyPI wheels
    pulumiKubernetes      # 4.32.0
    pulumiTls             # 5.5.0
    pulumiDockerBuild     # 0.0.19
    pulumiCloudflare      # 6.17.0
    pulumiRandom          # 4.21.0
    pulumiAws             # 7.34.0

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
  # The symlinkJoin containing pulumi CLI, wrapper, and language host.
  # pulumi-bin (from unstable: 3.244.0) bundles the CLI and
  # pulumi-language-python(-exec). Its version must match the wheeled Python SDK
  # (pythonDeps, 3.244.0): the language host and SDK resolve pulumi.Output via
  # is-identity, so a version split breaks Input[T] serialization. pulumi-bin is
  # a standalone Go binary, so sourcing it from unstable does not affect the
  # stable-python withPackages env.
  # Uses pythonEnv from languages.nix (single derivation for all consumers).
  package = let
    resolvedPythonEnv = assert pythonEnv != null; pythonEnv;
    pulumiWrapper = pkgs.writeShellScriptBin "pulumi" ''
      export PULUMI_PYTHON_CMD="${resolvedPythonEnv}/bin/python"
      exec ${pkgs.unstable.pulumi-bin}/bin/pulumi "$@"
    '';
  in pkgs.symlinkJoin {
    name = "pulumi-with-python";
    paths = [
      pkgs.unstable.pulumi-bin               # CLI + bundled language hosts (3.244.0)
      pkgs.pulumictl                         # Pulumi utilities
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
