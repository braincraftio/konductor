# src/apps/sync-versions.nix
# Maintenance app: rewrite the version blocks that documentation and crate
# manifests carry from src/lib/versions.nix.
#
#   nix run .#sync-versions             rewrite managed blocks in place
#   nix run .#sync-versions -- --check  report drift, write nothing (exit 1)
#
# checks.versions-sync runs the same `run` program with --check over the
# flake source. Managed regions (blocks between sync-versions markers, or
# single lines by prefix) are listed in `spec` below; sync_versions.py fails
# on a missing, duplicated, out-of-order, or unlisted marker.
#
# Generated Markdown is fenced code or single unbreakable lines, so prettier
# (proseWrap: always) leaves it byte-identical.

{ pkgs, versions }:

let
  inherit (pkgs) lib;
  langs = versions.languages;
  attrs = import ../lib/version-attrs.nix versions;
  channel = versions.nixos.channel;
  k0s = versions.kubernetes.k0s.version;

  html = name: content: {
    inherit name content;
    style = "html";
  };
  # Prettier's canonical Markdown puts a blank line after an HTML comment and
  # around a fenced block; generated content carries those lines so the
  # formatter and this check agree.
  markdownLine = name: line: html name "\n${line}";
  fenced = name: body: html name "\n${body}\n";
  hash = name: content: {
    inherit name content;
    style = "hash";
  };

  badge = markdownLine "badge" ''
    [![NixOS ${channel}](https://img.shields.io/badge/NixOS-${channel}-5277C3?logo=nixos&logoColor=white)](https://nixos.org)
  '';

  shellHierarchy = fenced "shell-hierarchy" ''
    ```text
    base (default)
      ├── python    base + Python ${langs.python.version} + uv + ruff + mypy
      ├── go        base + Go ${langs.go.version} + gopls + delve
      ├── node      base + Node ${langs.node.version} + pnpm + biome
      ├── rust      base + Rust ${langs.rust.version} + cargo + clippy
      ├── dev       base + neovim + tmux + IDE tools
      ├── full      all languages + dev
      ├── konductor full + docker + qemu + libvirt, x86_64-linux
      └── frontend  konductor + Playwright + Tauri, x86_64-linux
    ```
  '';

  # Format of the konductor shell banner (src/devshells/konductor.nix).
  banner = fenced "banner" ''
    ```text
    konductor-ab21b11: py${langs.python.version} go${langs.go.version} node${langs.node.version} rust${langs.rust.version} k0s${k0s}
    ```
  '';

  languagesBody = ''
    python.version = "${langs.python.version}";
    go.version = "${langs.go.version}";
    node.version = "${langs.node.version}";
    rust.version = "${langs.rust.version}";
  '';
  indent =
    prefix: text:
    lib.concatMapStrings (line: "${prefix}${line}\n") (
      lib.splitString "\n" (lib.removeSuffix "\n" text)
    );

  versionsExcerpt = fenced "versions-excerpt" ''
    ```nix
    {
      nixos = { channel = "${channel}"; stateVersion = "${versions.nixos.stateVersion}"; };
      languages = {
    ${indent "    " languagesBody}  };
      atuin = { version = "${versions.atuin.version}"; hash = "sha256-..."; cargoHash = "sha256-..."; };
      kubernetes.k0s.version = "${k0s}";
    }
    ```
  '';

  languagesExcerpt = fenced "languages-excerpt" ''
    ```nix
    languages = {
    ${indent "  " languagesBody}};
    ```
  '';

  attrsTable = ''
    python "${langs.python.version}" -> ${attrs.python}       go "${langs.go.version}" -> ${attrs.go}
    node   "${langs.node.version}"   -> ${attrs.nodejs}       k0s "${k0s}" -> ${attrs.k0s}
    rust   "${langs.rust.version}" -> rust-bin.stable."${attrs.rust}"
  '';

  overlayAttrsMarkdown = fenced "overlay-attrs" ''
    ```text
    ${attrsTable}```
  '';
  overlayAttrsComment = hash "overlay-attrs" (indent "#   " attrsTable);

  rustVersion = {
    prefix = "rust-version = ";
    content = ''rust-version = "${langs.rust.version}"'';
  };

  file = path: blocks: lines: { inherit path blocks lines; };

  spec = (pkgs.formats.json { }).generate "sync-versions.json" [
    (file "README.md"
      [
        badge
        shellHierarchy
        banner
        versionsExcerpt
        languagesExcerpt
        overlayAttrsMarkdown
      ]
      [ ]
    )
    (file "CLAUDE.md" [ shellHierarchy ] [ ])
    (file "CONTRIBUTING.md" [ versionsExcerpt ] [ ])
    (file "src/overlays/versions.nix" [ overlayAttrsComment ] [ ])
    (file "src/config/tree/Cargo.toml" [ ] [ rustVersion ])
    (file "templates/rust-application/Cargo.toml" [ ] [ rustVersion ])
    (file "templates/rust-library/Cargo.toml" [ ] [ rustVersion ])
  ];

  python = pkgs.konductor.pythonPackages.python;

  # Shared by the app and checks.versions-sync: --root and --check are the
  # caller's.
  run = pkgs.writeShellApplication {
    name = "sync-versions-run";
    runtimeInputs = [ python ];
    text = ''
      exec python ${./sync_versions.py} --spec ${spec} "$@"
    '';
  };
in
pkgs.writeShellApplication {
  name = "sync-versions";
  runtimeInputs = [
    pkgs.git
    run
  ];
  text = ''
    root=$(git rev-parse --show-toplevel)
    exec sync-versions-run --root "$root" "$@"
  '';
  passthru = { inherit run spec; };
  meta.description = "Rewrite version blocks in docs and crate manifests from src/lib/versions.nix";
}
