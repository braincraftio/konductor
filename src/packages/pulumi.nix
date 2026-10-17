{
  pkgs,
  pythonEnv ? null,
}:
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
# Pulumi CLI, language hosts, provider binaries, and Python wheels are pinned
# together in src/lib/versions.nix. Reuse nixpkgs' binary packaging with locally
# maintained source metadata. Python wheels use the shared Python package set.
#
let
  inherit (pkgs) lib;
  versions = import ../lib/versions.nix;
  pythonPackages = pkgs.konductor.pythonPackages;

  # Reuse nixpkgs' unpack/install/fixup/completion phases. Replace the SDK
  # archive and our six provider archives; additional nixpkgs providers retain
  # the source attestation supplied by the locked nixpkgs input.
  pulumiCli = pkgs.unstable.pulumi-bin.overrideAttrs (old: {
    inherit (versions.pulumi) version;
    srcs =
      let
        system = pkgs.stdenv.hostPlatform.system;
        platform =
          {
            x86_64-linux = {
              os = "linux";
              cliArch = "x64";
              pluginArch = "amd64";
            };
            aarch64-linux = {
              os = "linux";
              cliArch = "arm64";
              pluginArch = "arm64";
            };
            aarch64-darwin = {
              os = "darwin";
              cliArch = "arm64";
              pluginArch = "arm64";
            };
          }
          .${system};
        providers = versions.pulumi.providers;
        replaced =
          src:
          lib.hasInfix "/releases/sdk/pulumi-v" src.url
          || lib.any (name: lib.hasInfix "/pulumi-resource-${name}-v" src.url) (builtins.attrNames providers);
      in
      [
        (pkgs.fetchurl {
          url = "https://github.com/pulumi/pulumi/releases/download/v${versions.pulumi.version}/pulumi-v${versions.pulumi.version}-${platform.os}-${platform.cliArch}.tar.gz";
          hash = versions.pulumi.cliHashes.${system};
        })
      ]
      ++ lib.mapAttrsToList (
        name: release:
        pkgs.fetchurl {
          url = "https://github.com/pulumi/pulumi-${name}/releases/download/v${release.version}/pulumi-resource-${name}-v${release.version}-${platform.os}-${platform.pluginArch}.tar.gz";
          hash = release.pluginHashes.${system};
        }
      ) providers
      ++ builtins.filter (src: !(replaced src)) old.srcs;
  });

  # =========================================================================
  # Pulumi Python SDK -- PyPI wheel (nixpkgs' Pulumi SDK can lag
  # for the provider SDKs, which require a newer pulumi core).
  # =========================================================================
  # fetchPypi format="wheel" constructs incorrect URLs (py2.py3 prefix path).
  # Use fetchurl with exact PyPI content-addressed URLs instead.
  # Wheel URLs and hashes live alongside their versions in versions.nix.
  pulumiCore = pythonPackages.buildPythonPackage {
    pname = "pulumi";
    inherit (versions.pulumi) version;
    format = "wheel";

    src = pkgs.fetchurl {
      inherit (versions.pulumi) url hash;
    };

    # Runtime deps per the pinned wheel's Requires-Dist. Sourced from
    # same pinned Python package set as the shared withPackages environment.
    propagatedBuildInputs = with pythonPackages; [
      debugpy
      dill
      grpcio
      packaging
      protobuf
      pyyaml
      semver
      typing-extensions
      pythonPackages."opentelemetry-api"
      pythonPackages."opentelemetry-sdk"
      pythonPackages."opentelemetry-exporter-otlp-proto-grpc"
      pythonPackages."opentelemetry-instrumentation-grpc"
    ];

    doCheck = false;
    pythonRelaxDeps = [ "protobuf" ];
    nativeBuildInputs = [ pythonPackages.pythonRelaxDepsHook ];
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
  mkPulumiPypiPackage =
    {
      pname,
      version,
      url,
      hash,
      meta ? { },
    }:
    pythonPackages.buildPythonPackage {
      inherit pname version;
      format = "wheel";

      src = pkgs.fetchurl {
        inherit url hash;
      };

      pythonRelaxDeps = true;
      nativeBuildInputs = [ pythonPackages.pythonRelaxDepsHook ];

      propagatedBuildInputs = [
        pulumiCore
        pythonPackages.parver
        pythonPackages.packaging
        pythonPackages.requests
        pythonPackages.semver
      ];

      # No tests in provider SDK wheels
      doCheck = false;

      pythonImportsCheck = [ pname ];

      meta =
        with lib;
        {
          license = licenses.asl20;
        }
        // meta;
    };

  pulumiKubernetes = mkPulumiPypiPackage {
    pname = "pulumi_kubernetes";
    inherit (versions.pulumi.providers.kubernetes) version url hash;
    meta.description = "Pulumi Kubernetes provider SDK";
  };

  pulumiTls = mkPulumiPypiPackage {
    pname = "pulumi_tls";
    inherit (versions.pulumi.providers.tls) version url hash;
    meta.description = "Pulumi TLS provider SDK";
  };

  pulumiDockerBuild = mkPulumiPypiPackage {
    pname = "pulumi_docker_build";
    inherit (versions.pulumi.providers.docker-build) version url hash;
    meta.description = "Pulumi Docker Build provider SDK";
  };

  pulumiCloudflare = mkPulumiPypiPackage {
    pname = "pulumi_cloudflare";
    inherit (versions.pulumi.providers.cloudflare) version url hash;
    meta.description = "Pulumi Cloudflare provider SDK";
  };

  pulumiRandom = mkPulumiPypiPackage {
    pname = "pulumi_random";
    inherit (versions.pulumi.providers.random) version url hash;
    meta.description = "Pulumi Random provider SDK";
  };

  pulumiAws = mkPulumiPypiPackage {
    pname = "pulumi_aws";
    inherit (versions.pulumi.providers.aws) version url hash;
    meta.description = "Pulumi AWS provider SDK";
  };

  # =========================================================================
  # pyright — required as a Python package for two consumers:
  # 1. Pulumi's language plugin (Pulumi.yaml typechecker: pyright) runs
  #    pyright as a subprocess and expects it in pythonEnv/bin/
  # 2. The hermetic CLI wrapper (config/linters/pyright/) provides
  #    --pythonpath injection for direct terminal/CI invocations
  # =========================================================================
  pyrightPkg = pythonPackages.buildPythonPackage {
    pname = "pyright";
    inherit (versions.pyright) version;
    format = "wheel";

    src = pkgs.fetchurl {
      inherit (versions.pyright) url hash;
    };

    propagatedBuildInputs = with pythonPackages; [
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
    pulumiCore

    # Pulumi provider SDKs -- PyPI wheels
    pulumiKubernetes
    pulumiTls
    pulumiDockerBuild
    pulumiCloudflare
    pulumiRandom
    pulumiAws

    # Dependencies with native extensions (ensure proper linking)
    ps.grpcio # C++ extension -- the original motivation for this approach
    ps."grpcio-tools"
    ps.protobuf

    # Runtime dependencies from infrastructure/pulumi/pyproject.toml
    ps.bcrypt # Password hashing for Docker registry htpasswd
    ps.pydantic # Data validation using Python type annotations
    ps.semver # Semantic version parsing for git tags
    ps.gitpython # Git operations without subprocess calls
    ps.kubernetes # Kubernetes Python client for cluster metadata discovery
    ps.pyyaml # YAML parsing for kubeconfig
    ps.packaging # Version parsing for Helm chart resolution

    # Transitive deps (explicitly listed for clarity)
    ps.requests
    ps.dill
    ps.parver
    ps.setuptools # Required by some provider SDKs at runtime

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
  cli = pulumiCli;

  # =========================================================================
  # Pulumi CLI package (for cli.nix)
  # =========================================================================
  # The symlinkJoin containing pulumi CLI, wrapper, and language host.
  # The locally pinned pulumi-bin bundles the CLI and
  # pulumi-language-python(-exec). Its version must match the wheeled Python SDK
  # (versions.pulumi.version): the language host and SDK resolve pulumi.Output via
  # is-identity, so a version split breaks Input[T] serialization. pulumi-bin is
  # a standalone Go binary, so sourcing it from unstable does not affect the
  # stable-python withPackages env.
  # Uses pythonEnv from languages.nix (single derivation for all consumers).
  package =
    let
      resolvedPythonEnv =
        assert pythonEnv != null;
        pythonEnv;
      pulumiWrapper = pkgs.writeShellScriptBin "pulumi" ''
        export PULUMI_PYTHON_CMD="${resolvedPythonEnv}/bin/python"
        exec ${pulumiCli}/bin/pulumi "$@"
      '';
    in
    pkgs.symlinkJoin {
      name = "pulumi-with-python";
      paths = [
        pulumiCli # CLI + bundled language hosts and providers
        pkgs.pulumictl # Pulumi utilities
        pulumiWrapper # Last: wrapper wins symlinkJoin conflict (sets PULUMI_PYTHON_CMD)
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
  env =
    let
      resolvedPythonEnv =
        assert pythonEnv != null;
        pythonEnv;
    in
    {
      PULUMI_PYTHON_CMD = "${resolvedPythonEnv}/bin/python";
    };
}
