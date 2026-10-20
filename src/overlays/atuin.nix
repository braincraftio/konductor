# src/overlays/atuin.nix
# Atuin pinned ahead of nixos-26.05, independent of nixpkgs channel drift.
#
# nixos-26.05 ships atuin 18.15.2. Migration skew between konductor
# devshells and home-manager consumers on different nixpkgs channels
# caused SQLite migration conflicts. This overlay asserts a single
# version across all surfaces — devshells, home-manager, NixOS, QCOW2.
#
# atuin >= 18.17.0 requires rustc >= 1.96.1; nixos-26.05 ships 1.95.0.
# Build uses rust-overlay toolchain pinned in versions.nix.
#
# Version bump procedure:
#   Update atuin.version, hash, and cargoHash together in src/lib/versions.nix.

let
  versions = import ../lib/versions.nix;
  inherit (versions) atuin;
in

_final: prev:
let
  # nixos-26.05 ships rustc 1.95.0; atuin >= 18.17.0 requires rustc >= 1.96.1.
  # Build with the rust-overlay toolchain pinned in versions.nix.
  rustToolchain = prev.rust-bin.stable.${versions.languages.rust.version}.minimal;
  rustPlatform = prev.makeRustPlatform {
    cargo = rustToolchain;
    rustc = rustToolchain;
  };
in
{
  atuin = rustPlatform.buildRustPackage {
    pname = "atuin";
    inherit (atuin) version;

    src = prev.fetchFromGitHub {
      owner = "atuinsh";
      repo = "atuin";
      tag = "v${atuin.version}";
      inherit (atuin) hash;
    };

    inherit (atuin) cargoHash;

    # atuin's default features include 'check-update', which does not make sense
    # for distribution builds. List all other default features.
    buildNoDefaultFeatures = true;
    buildFeatures = [
      "ai"
      "client"
      "clipboard"
      "daemon"
      "pty-proxy"
      "sync"
    ];

    nativeBuildInputs = [
      prev.installShellFiles
      prev.pkg-config
    ];

    buildInputs = [
      prev.openssl
    ];

    # PTY tests clear the terminal and create Git repositories for workspace filters.
    nativeCheckInputs = [
      prev.ncurses
      prev.git
    ];

    postInstall = prev.lib.optionalString (prev.stdenv.buildPlatform.canExecute prev.stdenv.hostPlatform) ''
      installShellCompletion --cmd atuin \
        --bash <($out/bin/atuin gen-completions -s bash) \
        --fish <($out/bin/atuin gen-completions -s fish) \
        --zsh <($out/bin/atuin gen-completions -s zsh)
    '';

    checkFlags = [
      "--skip=registration"
      "--skip=sync"
      "--skip=change_password"
      "--skip=multi_user_test"
      # Requires a running, password-authenticated PostgreSQL server.
      "--skip=postgres_authenticates_with_the_password_file"
      # e2e_ai_resume_picker: PTY cannot find atuin on PATH during check phase.
      "--skip=the_shell_widget_resumes_the_session_chosen"
      # e2e_ai_sessions: session resume logic errors during check phase.
      "--skip=a_copy_behind_another_machine_catches_up_as_it_resumes"
      "--skip=a_diverged_copy_resumes_only_as_chosen"
      "--skip=a_session_gone_on_with_elsewhere_catches_up_where_it_came_from"
    ];

    preCheck = ''
      export HOME=$(mktemp -d)
      # The stdenv Bash lacks readline; PTY tests need an interactive editor.
      export ATUIN_E2E_BASH=${prev.bashInteractive}/bin/bash
    '';

    meta = with prev.lib; {
      description = "Replacement for a shell history which records additional commands context with optional encrypted synchronization between machines";
      homepage = "https://github.com/atuinsh/atuin";
      changelog = "https://github.com/atuinsh/atuin/releases/tag/v${atuin.version}";
      license = licenses.mit;
      mainProgram = "atuin";
    };
  };
}
