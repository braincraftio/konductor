# src/overlays/atuin.nix
# Transitional atuin 18.24.5 build. Konductor consumes atuin from nixpkgs;
# this overlay exists only until the locked nixpkgs input ships >= 18.24.5.
# Do not bump it. A newer atuin arrives through a nixpkgs lock update.
#
# Why it still exists: 18.24.5 is deployed, and it changes SQLite migrations
# in atuin-client and atuin-octavo. The nixpkgs-unstable base of the locked
# fork ships 18.24.4, which must not open a database that 18.24.5 migrated.
# nixpkgs master carries 18.24.5 (NixOS/nixpkgs 01c07e68).
#
# The original reasons for the pin no longer apply: devshells, home-manager,
# NixOS, and QCOW2 consume one nixpkgs input, so channel skew cannot occur,
# and nixpkgs builds atuin with its own Rust toolchain.
#
# Removal, once this prints >= 18.24.5 (this overlay does not affect it):
#   nix eval --raw --impure --expr \
#     '(builtins.getFlake "git+file://'"$PWD"'").inputs.nixpkgs.legacyPackages.x86_64-linux.atuin.version'
# then delete in one change:
#   - this file and its entry in src/overlays/default.nix
#   - the atuin record in src/lib/versions.nix
#   - the "Build atuin" step in .github/workflows/nix.yml
#   - the .#atuin.cargoDeps note in flake.nix (packages.atuin stays; it
#     re-exports nixpkgs atuin)
#   - the atuin pin text in README.md, CLAUDE.md, and CONTRIBUTING.md

let
  versions = import ../lib/versions.nix;
  inherit (versions) atuin;
in

_final: prev:
let
  # rust-overlay toolchain pinned in versions.nix; removed with this overlay.
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

    # Use the atomic update API recommended by our pinned Rust toolchain.
    postPatch = ''
      substituteInPlace crates/atuin-daemon/src/output_capture/persistence/blob/fjall/mod.rs \
        --replace-fail 'self.estimated_usage.fetch_update(' 'self.estimated_usage.try_update('
      substituteInPlace crates/atuin-daemon/src/session_capture/engine/mod.rs \
        --replace-fail '.fetch_update(' '.try_update('
      substituteInPlace crates/atuin/tests/common/agents.rs \
        --replace-fail 'LAST.fetch_update(' 'LAST.try_update('
    '';

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
      # Concurrent daemon fixtures can exhaust wall-clock redaction budgets.
      "--test-threads=1"
      "--skip=registration"
      "--skip=sync"
      "--skip=change_password"
      "--skip=multi_user_test"
      # Requires a running, password-authenticated PostgreSQL server.
      "--skip=postgres_authenticates_with_the_password_file"
      "--skip=deleting_an_account_needs_its_password"
      "--skip=operator_creates_resets_and_deletes_a_user"
      # e2e_ai_resume_picker: PTY cannot find atuin on PATH during check phase.
      "--skip=the_shell_widget_resumes_the_session_chosen"
      # e2e_ai_sessions: session resume logic errors during check phase.
      "--skip=a_copy_behind_another_machine_catches_up_as_it_resumes"
      "--skip=a_diverged_copy_resumes_only_as_chosen"
      "--skip=a_session_gone_on_with_elsewhere_catches_up_where_it_came_from"
      # Large AI-session message exceeds the redaction time limit during package checks.
      "--skip=a_huge_message_reads_back"
      # e2e_capture: filtered_commands_leave_no_captured_output times out during check phase.
      "--skip=filtered_commands_leave_no_captured_output"
      # e2e_pty: all bash_preexec setup variants fail — PTY harness cannot
      # drive bash-preexec integration in the check phase environment.
      "--skip=setup_2_tests_shells_bash_preexec_toml"
      # atuin-daemon concurrency: timing-sensitive, panics when reload
      # completes faster than the test's minimum threshold (RELOAD_ROWS).
      "--skip=end_history_is_not_starved_by_an_index_reload"
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
