# src/checks/rust.nix
# Offline, deterministic Rust checks for nix flake check, all on the pinned
# Konductor toolchain (languages.rustToolchain).
#
#   beautiful-rust-skill     upstream scripts/check-skill.py on the pinned source
#   beautiful-rust-examples  upstream scripts/check-examples.py: every Rust block
#                            in the skills and references compiles
#   beautiful-rust-lints     upstream scripts/check-lints.sh: every lint in
#                            lints/lints.toml fires on its fixture line
#   rust-template-*          templates/rust-{library,application}: clippy.toml is
#                            upstream's byte-for-byte; parsed [lints] equals
#                            upstream's (application: minus [lib] keys); fmt,
#                            clippy -D warnings, test, and doc pass on the
#                            template's own target. beautiful-rust-lints proves
#                            upstream's fixture fires under configuration the
#                            library template carries verbatim; it does not
#                            compile the template itself.
#   rust-skill-delivery      each delivered Claude practitioner skill equals its
#                            packaged directory; `claude plugin validate` accepts
#                            the plugin
#
# Outside nix flake check (credentials, network, or nested Nix): harness
# discovery and model sessions, `cargo audit` / `cargo deny check advisories`
# (RustSec database), `claude plugin eval`, and template initialization against
# a Konductor revision. docs/developer_guide/RUST.md lists those commands.

{
  pkgs,
  lib,
  rustToolchain,
  practitionerPlugin,
  claude,
}:

let
  br = pkgs.beautiful-rust;
  inherit (br) src;

  cargoEnv = ''
    export HOME="$TMPDIR" CARGO_HOME="$TMPDIR/cargo-home" CARGO_TERM_COLOR=never
  '';

  vendorConfig = cargoVendor: ''
    mkdir -p .cargo
    cat > .cargo/config.toml <<EOF
    [source.crates-io]
    replace-with = "vendored-sources"
    [source.vendored-sources]
    directory = "${cargoVendor}"
    EOF
  '';

  # libLints = false: the template omits the keys upstream marks "[lib]"
  # ("applications can drop them"); the rest must equal upstream's table.
  templateCheck =
    {
      name,
      template,
      sourceFile,
      libLints,
      cargoVendor ? null,
    }:
    pkgs.runCommand "check-rust-template-${name}"
      {
        nativeBuildInputs = [
          rustToolchain
          pkgs.python3
        ];
      }
      ''
        ${cargoEnv}

        echo "--- clippy.toml is upstream lints/clippy.toml"
        cmp ${template}/clippy.toml ${src}/lints/clippy.toml

        echo "--- [lints] equals upstream lints/lints.toml${
          lib.optionalString (!libLints) " minus [lib] keys"
        }"
        python3 -I - ${template}/Cargo.toml ${src}/lints/lints.toml <<'PY'
        import re, sys, tomllib
        manifest, upstream = sys.argv[1:]
        actual = tomllib.load(open(manifest, "rb"))["lints"]
        text = open(upstream, encoding="utf-8").read()
        expected = tomllib.loads(text)["lints"]
        ${lib.optionalString (!libLints) ''
          # Upstream marks library-only lints with a trailing "# [lib]" comment.
          # Every non-comment line carrying the marker must be a key assignment
          # the pattern captures, and each captured key must exist in the table.
          pattern = re.compile(r"^(\w+)\s*=.*#\s*\[lib\]")
          lib_only = set()
          for line in text.splitlines():
              if "[lib]" not in line or line.lstrip().startswith("#"):
                  continue
              match = pattern.match(line.strip())
              if match is None:
                  sys.exit(f"unrecognized [lib] marker line: {line!r}")
              lib_only.add(match.group(1))
          if not lib_only:
              sys.exit("no [lib]-marked lints found in the pinned table")
          unknown = lib_only - {k for table in expected.values() for k in table}
          if unknown:
              sys.exit(f"[lib] keys absent from the table: {sorted(unknown)}")
          print("[lib] keys omitted:", ", ".join(sorted(lib_only)))
          expected = {group: {k: v for k, v in table.items() if k not in lib_only}
                      for group, table in expected.items()}
        ''}
        if actual != expected:
            sys.exit(f"[lints] differs from the pinned table:\nexpected {expected}\nactual   {actual}")
        PY

        echo "--- template workflow"
        cp -r --no-preserve=mode ${template} crate
        cd crate
        ${lib.optionalString (cargoVendor != null) (vendorConfig cargoVendor)}
        test -f ${sourceFile}
        cargo fmt --check
        cargo clippy --offline --all-targets --all-features -- -D warnings
        cargo test --offline
        RUSTDOCFLAGS="-D warnings" cargo doc --offline --no-deps
        touch $out
      '';
in
{
  beautiful-rust-skill =
    pkgs.runCommand "check-beautiful-rust-skill"
      {
        nativeBuildInputs = [ pkgs.python3 ];
      }
      ''
        python3 -I ${src}/scripts/check-skill.py ${src}
        touch $out
      '';

  beautiful-rust-examples =
    pkgs.runCommand "check-beautiful-rust-examples"
      {
        nativeBuildInputs = [
          rustToolchain
          pkgs.python3
        ];
      }
      ''
        ${cargoEnv}
        python3 -I ${src}/scripts/check-examples.py ${src}
        touch $out
      '';

  # check-lints.sh writes Cargo.lock beside lints/check/Cargo.toml.
  beautiful-rust-lints =
    pkgs.runCommand "check-beautiful-rust-lints"
      {
        nativeBuildInputs = [
          rustToolchain
          pkgs.python3
        ];
      }
      ''
        ${cargoEnv}
        cp -r --no-preserve=mode ${src} source
        bash source/scripts/check-lints.sh
        touch $out
      '';

  rust-template-library = templateCheck {
    name = "library";
    template = ../../templates/rust-library;
    sourceFile = "src/lib.rs";
    libLints = true;
  };

  rust-template-application = templateCheck {
    name = "application";
    template = ../../templates/rust-application;
    sourceFile = "src/main.rs";
    libLints = false;
    cargoVendor = pkgs.rustPlatform.importCargoLock {
      lockFile = ../../templates/rust-application/Cargo.lock;
    };
  };

  rust-skill-delivery =
    pkgs.runCommand "check-rust-skill-delivery"
      {
        nativeBuildInputs = [ claude ];
      }
      ''
        export HOME="$TMPDIR"
        for id in ${lib.escapeShellArgs br.skillIds}; do
          diff -r ${br}/${br.skillsDir}/"$id" ${practitionerPlugin}/skills/"$id"
        done
        claude plugin validate ${practitionerPlugin}
        touch $out
      '';
}
