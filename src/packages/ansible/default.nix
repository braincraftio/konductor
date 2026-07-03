# src/packages/ansible/default.nix
# Ansible toolchain — engine + mitogen acceleration + linter.
#
# ansible-core gains mitogen + httpx via its extraPackages parameter.
# mitogen 0.3.50 is built from source (nixos-25.11 ships 0.3.33, too
# old for Ansible 14). The serverscom.mitogen Galaxy collection exposes
# mitogen_linear as an FQCN strategy name.
#
# The symlinkJoin wrapper bakes ANSIBLE_STRATEGY_PLUGINS,
# ANSIBLE_STRATEGY, and ANSIBLE_COLLECTIONS_PATH into all ansible
# binaries via --set-default (preserving per-run override capability:
# ANSIBLE_STRATEGY=linear ansible-playbook bootstrap.yml).

{
  pkgs,
  lib,
  versions,
}:

let
  python3 = pkgs.python313;
  python3Packages = pkgs.python313Packages;

  # mitogen 0.3.50 — persistent remote Python interpreter + RPC.
  # Zero runtime deps beyond stdlib + setuptools.
  mitogen = python3Packages.buildPythonPackage {
    pname = "mitogen";
    version = versions.ansible.mitogen;
    pyproject = true;

    src = pkgs.fetchFromGitHub {
      owner = "mitogen-hq";
      repo = "mitogen";
      tag = "v${versions.ansible.mitogen}";
      hash = "sha256-f6N9eGwhxa/Ls9NqTSqMh+zbLNBeFEUJXd9Km5aBGI8=";
    };

    build-system = [ python3Packages.setuptools ];
    doCheck = false;
    pythonImportsCheck = [ "mitogen" ];
  };

  # ansible-core with mitogen + httpx in its Python closure.
  ansibleCore = python3Packages.ansible-core.override {
    extraPackages = _ps: [
      mitogen
      python3Packages.httpx
    ];
  };

  ansibleApp = python3Packages.toPythonApplication ansibleCore;

  # Strategy plugin path.
  strategyPluginsPath = "${mitogen}/${python3.sitePackages}/ansible_mitogen/plugins/strategy";

  # serverscom.mitogen Galaxy collection v1.4.1.
  serverscomMitogenCollection = pkgs.stdenvNoCC.mkDerivation {
    pname = "serverscom-mitogen-collection";
    version = versions.ansible.serverscomCollection;

    src = pkgs.fetchFromGitHub {
      owner = "serverscom";
      repo = "ansible-collection-mitogen";
      rev = versions.ansible.serverscomCollection;
      hash = "sha256-5wumT5QPI42/JCcNlQN8fiZf80QBGu1h6/uWYTiKgf4=";
    };

    dontBuild = true;

    installPhase = ''
      runHook preInstall
      mkdir -p $out/ansible_collections/serverscom/mitogen
      cp -r . $out/ansible_collections/serverscom/mitogen/
      runHook postInstall
    '';
  };

  # Wrapped ansible with mitogen strategy baked in.
  ansibleWithMitogen = pkgs.symlinkJoin {
    name = "ansible-with-mitogen-${ansibleCore.version}";
    paths = [ ansibleApp ];
    nativeBuildInputs = [ pkgs.makeBinaryWrapper ];
    postBuild = ''
      for bin in ansible ansible-playbook ansible-galaxy ansible-vault \
                  ansible-doc ansible-config ansible-inventory ansible-console; do
        [ -f $out/bin/$bin ] || continue
        wrapProgram $out/bin/$bin \
          --set-default ANSIBLE_STRATEGY_PLUGINS "${strategyPluginsPath}" \
          --set-default ANSIBLE_STRATEGY         "serverscom.mitogen.mitogen_linear" \
          --prefix      ANSIBLE_COLLECTIONS_PATH : "${serverscomMitogenCollection}"
      done
    '';
  };

  # Hermetic ansible-lint wrapper.
  ansibleLint = import ../../config/linters/ansible-lint {
    inherit pkgs;
    ansibleEngine = ansibleWithMitogen;
  };
in
{
  packages = [
    ansibleWithMitogen
    ansibleLint.package
  ];

  package = ansibleWithMitogen;
  lint = ansibleLint.package;
  unwrapped = python3Packages.ansible-core;

  # Exposed for a-la-carte consumers (e.g., ansible repo's flake.nix).
  inherit mitogen serverscomMitogenCollection strategyPluginsPath;

  shellHook = "";
  env = { };

  meta = {
    description = "ansible-core (with mitogen ${versions.ansible.mitogen} + httpx) plus the hermetic ansible-lint wrapper";
  };
}
