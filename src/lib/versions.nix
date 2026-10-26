# src/lib/versions.nix
# Single Source of Truth for locally maintained releases and their hashes
#
# This file has no pkgs dependency. Pure data.
# Every devshell, container, VM, and module inherits from here.
# Keep each version, source URL, and source/dependency/platform hash together.
# Flake-input revisions and source narHashes remain authoritative in flake.lock.
#
# Schema: each record holds one canonical `version`. Language and k0s versions
# name the runtime series (Rust is an exact toolchain release); the nixpkgs
# attribute for each is derived from it in src/overlays/versions.nix
# (pkgs.konductor.*). Package version fields pin exact releases. Hashes attest
# source/dependency contents, not signatures. Platform hash keys describe
# available upstream artifacts, not necessarily the platforms supported by the
# complete Konductor flake. Banners and the website (.#versions-json) render
# `version` directly; presentation is not stored here.
#
# When changing nixos.channel, also update:
#   - flake.nix: nixpkgs.url and nixvim.url branches
#   - home-manager.url branch (must match nixpkgs)

{
  nixos = {
    channel = "26.05";
    # Compatibility defaults for existing installations; not an upgrade pin.
    stateVersion = "26.05";
  };

  languages = {
    python.version = "3.13";
    go.version = "1.27";
    node.version = "26";
    rust.version = "1.99.1";
  };

  ansible = {
    mitogen = {
      version = "0.3.54";
      hash = "sha256-fDi/XvRdVGb+cPkLyr78J5RUIcMS/2WO7fIROlHr7YI=";
    };
    serverscomCollection = {
      version = "1.4.1";
      hash = "sha256-5wumT5QPI42/JCcNlQN8fiZf80QBGu1h6/uWYTiKgf4=";
    };
  };

  # Kubernetes distribution tooling — tip-of-spear policy.
  # k0s.version selects the series from the k0s-nix overlay (k0s_1_33..k0s_1_36);
  # the embedded Kubernetes version is coupled to k0s upstream (1.36.x ↔ k8s
  # 1.36.x) and is not managed here. k0sctl is pinned via src/overlays/k0s.nix
  # because nixpkgs channels lag upstream releases.
  kubernetes = {
    k0s.version = "1.36";
    k0sctl = {
      version = "0.33.1";
      hash = "sha256-g/8rN0UWbUjiIuWKcBb9sr8PjMx+rcq3Hce64cGziU0=";
      vendorHash = "sha256-3TIQ1VY+52DFCVWiJs5U+5A+mVSU3QPyr5Vzrzs7zF8=";
    };
  };

  image = {
    name = "ghcr.io/braincraftio/konductor";
  };

  # Shell history — tip-of-spear policy to prevent SQLite migration skew
  # between konductor devshells and home-manager consumers on different
  # nixpkgs channels. Built by src/overlays/atuin.nix.
  atuin = {
    version = "18.24.2";
    hash = "sha256-b6Uj3cPAu731lhrN8fOv4d0CpehT3bv7IOBmkbYrqfI=";
    cargoHash = "sha256-HkYI2+Yvjnw9pKeRsteyZeLhHHErTa1mvJL16NQVF3g=";
  };

  # Terminal-embedded Chromium browser via kitty graphics protocol.
  # Packaged by src/overlays/terminal-browser.nix.
  terminal-browser = {
    version = "0.13.4";
    hashes = {
      x86_64-linux = "sha256-YnfaqrqxZxGrPxlhzf+tnvrF5wrFXVB24shkltZJ06Q=";
      aarch64-linux = "sha256-DPVn2CGJlaJPts5LBsB8z1ioxReQYFgIc1Xx4vrRlp8=";
      aarch64-darwin = "sha256-8BcjDHjGCgfvRFGh6wqScn8LlVqPzYeuw1iRDF0MA8c=";
      x86_64-darwin = "sha256-AbxpkbrRIvQuTypRZKGY2DhLlEwDbeESB4/VH1jcZ+0=";
    };
  };

  # FlakeHub release publisher; built by src/overlays/flakehub-push.nix and
  # passed to the flakehub-push action as source-binary, so the action never
  # downloads its binary. rev must equal the DeterminateSystems/flakehub-push
  # SHA pinned in .github/actions/publish-flake/action.yml (wrapper and binary
  # from one commit). Bump rev, hash, and cargoHash together.
  flakehub-push = {
    version = "0.1.0";
    rev = "dceefcb33cba27bde28f8540d8b4537cb925c46b";
    hash = "sha256-HFKSSFc5QKmcCkuIiKJ/wiTU8yAqOUUvXEcgj7R/IVY=";
    cargoHash = "sha256-q3xHXgfXh5zVbjrD7BQmr0tqQaiL6KdM82jWImmIzY4=";
  };

  # Pre-built VS Code in browser (x86_64-linux).
  # Packaged by src/overlays/code-server.nix.
  code-server = {
    version = "4.143.1";
    hash = "sha256-YUh3z3EAXxTqJSvS2bHBIjfPfXNoHvFQ8N/38ThJ/bU=";
  };

  # Terminal file transfer; built by src/packages/trzsz.nix.
  trzsz = {
    version = "1.2.0";
    hash = "sha256-CokZAXT61UKSsKnzE5mPMdAZecGX/8mgDkG4yDSat5M=";
    vendorHash = "sha256-eqQ5PpHNLp2QebC6fZcVYT9hHAeXfM6GLiji4WzGSRQ=";
  };

  # BrainCraft fork, built by src/programs/forgejo/runner.nix; source
  # revision/narHash belong to the forgejo-runner-src input in flake.lock.
  # Update that input alongside this release record.
  forgejo-runner = {
    version = "12.5.3-braincraft";
    vendorHash = "sha256-zowZvsjg9k5XO12pip1SbOz3KXXqxFfnLF+y4cf8WOQ=";
  };

  # CLI and Python SDK share a release. Wheel paths are content-addressed.
  pulumi = {
    version = "3.272.0";
    cliHashes = {
      x86_64-linux = "sha256-WNVF8rmHYQUZIgCOvTgezvlUhNf3pf9/qhXXp4DqhPY=";
      aarch64-linux = "sha256-TwdBkBuJgsQya3Atq/SDxj0s93yIrELddStyVBKEpTQ=";
      aarch64-darwin = "sha256-H7VUvzmtg7pu727LesWhS4FYlBzNl9IBg30T3AmAYBQ=";
    };
    url = "https://files.pythonhosted.org/packages/be/50/ceba43d892bebd64fbbe173b37e568bcee019c1577a11d528c4877e664fb/pulumi-3.272.0-py3-none-any.whl";
    hash = "sha256-5hhLLCE+qhO7t2/pRuDPxBPVPIbqFuHnoU1guIWbQaw=";
    providers = {
      kubernetes = {
        version = "4.34.2";
        pluginHashes = {
          x86_64-linux = "sha256-sqNHGol9jUqlxvDqKTPTY9+nK+6O1lGhYkagnj5yi7Y=";
          aarch64-linux = "sha256-FFbB+WJMTNaMrwOSjUw01oB8vmaP2RfGIg7MCeq3DSY=";
          aarch64-darwin = "sha256-a8IHInEYtrv/ufWh4PUqkX/WwGKW03TcJw5DVDWNqzM=";
        };
        url = "https://files.pythonhosted.org/packages/ca/e2/ce15a82298ada9df70ae39f3156ad4cba3eab32517c839f4b09703a65f6c/pulumi_kubernetes-4.34.2-py3-none-any.whl";
        hash = "sha256-lMlLbOP6zSaTt/jnOttYnDioFX2jKJAJ246JKxTuaMs=";
      };
      tls = {
        version = "5.6.2";
        pluginHashes = {
          x86_64-linux = "sha256-OhqvsdiuCJZVnXyRco2f/5joDgTt4PFtXmZ4G6XmdDg=";
          aarch64-linux = "sha256-t2yrRGcxXm8uf4lRRcF7KUeCejvDLFDHRb/RAOmuqcs=";
          aarch64-darwin = "sha256-eLOsFFXoFm9U3AvXiFxsvNTYtKNkP6pvKmbaQo/fYLQ=";
        };
        url = "https://files.pythonhosted.org/packages/ca/a5/20f31777bf2903c56aee6ff62c63ef5ebc80428941ec0a3187e5a4cd1909/pulumi_tls-5.6.2-py3-none-any.whl";
        hash = "sha256-029RFPM8BxAeYiEWL3ga3Dhn5iYfPY5KLfs9cHszsyk=";
      };
      docker-build = {
        version = "0.0.22";
        pluginHashes = {
          x86_64-linux = "sha256-YlTYqi7R1fHC6p1TWGZjRSUQxMh1rxdzladxnCo8Sus=";
          aarch64-linux = "sha256-uEyFM0HY0Ypju4q+F5J/VfxL5ov24qrElXYo7hnzdrw=";
          aarch64-darwin = "sha256-3mo10TKG5Jo0tm0GfNI3UK5XisSnEbNPlm/XpPG/aVg=";
        };
        url = "https://files.pythonhosted.org/packages/a0/8b/18189686ad8cdfc57d3571bcdbdc8490dad0b3a0e5ec401cb62db784b83f/pulumi_docker_build-0.0.22-py3-none-any.whl";
        hash = "sha256-RuXwiFSyI+ExJylyodooOFMPnHJxyhZStCFrUa2P8a8=";
      };
      cloudflare = {
        version = "6.23.1";
        pluginHashes = {
          x86_64-linux = "sha256-n4b3kNIYucR6V/IGaMDqjwUITeyVW/AEjf2Ji4kXVFU=";
          aarch64-linux = "sha256-hdTuK7tfD9pYEaYfCjKSxdq9juj0oj/dpcr1b2Jdegw=";
          aarch64-darwin = "sha256-wsGBBfhaimjluoCmxd4fAZdAKGTiol1mOdv6mWj4FAg=";
        };
        url = "https://files.pythonhosted.org/packages/6e/54/cbcbe3cb5ba34b530c0d58fadedfcb2507fb3fdc0c0d7ca895b46f3a27ac/pulumi_cloudflare-6.23.1-py3-none-any.whl";
        hash = "sha256-dO2OZoZ0r8+7Hnn38clYQLBLDc/XQ2Gt+D8epDWd584=";
      };
      random = {
        version = "4.21.4";
        pluginHashes = {
          x86_64-linux = "sha256-cpcWmGzzTy5ifJMMQdttyb/uYkN/lXPi2hmLQt+gH/U=";
          aarch64-linux = "sha256-4tTWxILO5eI998OWn6xEzsDKCtXrI2ZQs9aPVYpvQno=";
          aarch64-darwin = "sha256-TME9u1u+l7UufAql33JXc/Y4FVqaEeGZ3cVcZ5jN/Sg=";
        };
        url = "https://files.pythonhosted.org/packages/b8/a1/cca989317c4c1826a10ae9e7d55301d34e0bc67dc8d7e41b0fe72f62ee41/pulumi_random-4.21.4-py3-none-any.whl";
        hash = "sha256-vRvELEiaSewKwJkQ+G8DCFjX6I8x0P+BrkQlpsZc704=";
      };
      aws = {
        version = "7.51.1";
        pluginHashes = {
          x86_64-linux = "sha256-H7nLM2gIXFE45Aa1+VDoko4p1RRFNAcT01frYTJuZzE=";
          aarch64-linux = "sha256-ipBq+RhDw6qoUcoJxT7coHk10i9LA/m4mULm3+IIJKU=";
          aarch64-darwin = "sha256-ADhU/Lckwp3Qw1wchljAFyKUrvIy39NvXn9nV2vAqhU=";
        };
        url = "https://files.pythonhosted.org/packages/7e/78/cb68421d21468c6a8038dc72535f41ef201e35cdb11a0f5d380698f5ecb8/pulumi_aws-7.51.1-py3-none-any.whl";
        hash = "sha256-v/x/ts41LpAZMCSYVxeZp3H3qEI0sZ/4sXEKYlCzECQ=";
      };
    };
  };

  # Prettier Astro plugin; built by src/config/formatters/prettier/astro-plugin.nix.
  # hash = npm tarball, npmDepsHash = fetchNpmDeps over the vendored lockfile.
  # Refresh both with: nix run .#update-prettier-astro-lock [-- VERSION]
  prettier-plugin-astro = {
    version = "1.1.2";
    hash = "sha256-FZniSOPpTjZN+fNfnXSyfVIUDcsknOV08HBoSCikcho=";
    npmDepsHash = "sha256-0j49Flmi/NdaLhrrT6Rx0zP9fL6WDYJ2gzV6VVxCuvY=";
  };

  # Python type checker wheel, consumed by src/packages/pulumi.nix.
  pyright = {
    version = "1.1.414";
    url = "https://files.pythonhosted.org/packages/d7/ba/18b6e682ead424ad24bcc134339ae5d1b931cd9ae260540592a058a91279/pyright-1.1.414-py3-none-any.whl";
    hash = "sha256-KmtLMpjJ7sF0xe2DvTON5u7oLfKZLz4ZMOYZnTgb428=";
  };

  nix = {
    minimum = "2.24.0";
    recommended = "2.35.3";
  };
}
