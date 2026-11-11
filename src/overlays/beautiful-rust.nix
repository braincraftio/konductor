# src/overlays/beautiful-rust.nix
# BeautifulRust: Rust skills, reference digests, and clippy/lint presets.
#
# Output layout:
#   share/beautiful-rust/skills/<id>/   runtime skill: SKILL.md, references/,
#                                       LICENSE, PROVENANCE.json; no evals/
#   share/beautiful-rust/lints/         clippy.toml and lints.toml presets
#   share/beautiful-rust/evals/<id>/    upstream eval cases (claude plugin eval)
#   share/doc/beautiful-rust/           LICENSE, README.md, PROVENANCE.json
#
# Upstream checks run against passthru.src in src/checks/rust.nix with the
# Konductor Rust toolchain.
#
# Version bump procedure:
#   Update beautiful-rust.rev, hash, and version together in
#   src/lib/versions.nix; then nix flake check (beautiful-rust-* checks).

let
  versions = import ../lib/versions.nix;
  record = versions.beautiful-rust;
in

_final: prev:
let
  skillIds = [
    "rust-best-practices"
    "rust-review"
    "rust-port"
  ];

  upstreamSrc = prev.fetchFromGitHub {
    owner = "morganlinton";
    repo = "BeautifulRust";
    inherit (record) rev hash;
  };

  contextPatch = ./patches/beautiful-rust-project-context.patch;
  # Packaging and upstream checks consume the same adapted source.
  src = prev.applyPatches {
    name = "beautiful-rust-${record.version}-source";
    src = upstreamSrc;
    patches = [ contextPatch ];
  };

  provenance = (prev.formats.json { }).generate "beautiful-rust-provenance.json" {
    name = "beautiful-rust";
    inherit (record) version rev;
    repository = "https://github.com/morganlinton/BeautifulRust";
    source = "https://github.com/morganlinton/BeautifulRust/tree/${record.rev}";
    narHash = record.hash;
    license = "MIT";
    adaptations = [
      {
        patch = "beautiful-rust-project-context.patch";
        sha256 = builtins.hashFile "sha256" contextPatch;
        source = "https://github.com/google/styleguide/blob/72372684427af9861212ee7f1cdbb48b6f497857/rustguide.md";
        license = "CC-BY-3.0";
        licenseUrl = "https://creativecommons.org/licenses/by/3.0/";
        description = "Contextual guidance for independent projects; adapted from Google Rust Style Guide.";
      }
    ];
  };
in
{
  beautiful-rust = prev.stdenvNoCC.mkDerivation {
    pname = "beautiful-rust";
    version = "${record.version}-unstable-${builtins.substring 0 7 record.rev}";
    inherit src;

    dontConfigure = true;
    dontBuild = true;

    installPhase = ''
      runHook preInstall

      share=$out/share/beautiful-rust
      mkdir -p "$share/skills" "$share/evals" "$share/lints" "$out/share/doc/beautiful-rust"

      for id in ${prev.lib.escapeShellArgs skillIds}; do
        # Runtime skill: the upstream directory minus evals/, which holds
        # deliberately defective fixtures rather than instructions.
        cp -r skills/"$id" "$share/skills/$id"
        rm -rf "$share/skills/$id/evals"
        install -Dm644 LICENSE "$share/skills/$id/LICENSE"
        install -Dm644 ${provenance} "$share/skills/$id/PROVENANCE.json"
        install -Dm644 ${contextPatch} "$share/skills/$id/beautiful-rust-project-context.patch"
        if [ -d skills/"$id"/evals ]; then
          cp -r skills/"$id"/evals "$share/evals/$id"
        fi
      done

      # Payloads the delivered instructions name. rust-review and rust-port
      # point at rust-best-practices and its Bevy digest by skill name.
      for required in \
        skills/rust-best-practices/SKILL.md \
        skills/rust-best-practices/references/bevy.md \
        skills/rust-best-practices/references/rust-api-guidelines.md \
        skills/rust-best-practices/references/effective-rust.md \
        skills/rust-best-practices/references/rust-design-patterns.md \
        skills/rust-best-practices/references/microsoft-rust-guidelines.md \
        skills/rust-best-practices/references/google-rust-style-guide.md \
        skills/rust-review/SKILL.md \
        skills/rust-port/SKILL.md; do
        if [ ! -f "$share/$required" ]; then
          echo "beautiful-rust: missing runtime payload $required" >&2
          exit 1
        fi
      done

      install -Dm644 -t "$share/lints" lints/clippy.toml lints/lints.toml
      install -Dm644 -t "$out/share/doc/beautiful-rust" LICENSE README.md
      install -Dm644 ${provenance} "$out/share/doc/beautiful-rust/PROVENANCE.json"

      runHook postInstall
    '';

    passthru = {
      inherit src upstreamSrc skillIds;
      skillsDir = "share/beautiful-rust/skills";
      lintsDir = "share/beautiful-rust/lints";
      evalsDir = "share/beautiful-rust/evals";
    };

    meta = {
      description = "Rust writing, review, and porting skills with clippy lint presets";
      homepage = "https://github.com/morganlinton/BeautifulRust";
      license = [
        prev.lib.licenses.mit
        prev.lib.licenses.cc-by-30
      ];
      sourceProvenance = [ prev.lib.sourceTypes.fromSource ];
      platforms = prev.lib.platforms.all;
    };
  };
}
