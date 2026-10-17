# Implementation Spec: Maximal Nix Packaging for OpenAI Codex & Anomaly OpenCode

## Scope

Three upstream repos receive PRs. One consumer repo (home-manager) is updated to consume them. One
nixpkgs fork receives version-bump PRs.

| Repo                    | Fork remote          | Branch                 | PR target                      |
| ----------------------- | -------------------- | ---------------------- | ------------------------------ |
| `anomalyco/opencode`    | `usrbinkat/opencode` | `fix/nix-v2-packaging` | `anomalyco/opencode` v2 branch |
| `openai/codex`          | `usrbinkat/codex`    | `fix/nix-packaging`    | `openai/codex` main branch     |
| `NixOS/nixpkgs`         | `usrbinkat/nixpkgs`  | `codex-opencode-bump`  | `NixOS/nixpkgs` nixos-unstable |
| Home-manager (consumer) | N/A                  | main                   | N/A (local only)               |

Disk paths:

```text
/workspace/usrbinkat/github.com/anomalyco/opencode   # checked out on v2
/workspace/usrbinkat/github.com/openai/codex          # checked out on main
/workspace/usrbinkat/github.com/nixos/nixpkgs         # gssproxy-package-and-module branch
/home/usrbinkat/.config/home-manager                  # home-manager flake
```

---

## Part 1: Reference — How nixpkgs packages these tools today

### 1.1 nixpkgs codex (`pkgs/by-name/co/codex/`)

**Files:**

- `package.nix` — main derivation (version 0.146.0, pinned to `rust-v0.146.0` tag)
- `fetchers.nix` — `fetchLibrustyV8` helper (copy-paste sanctioned by `windmill/fetchers.nix`
  comment: "not a stable interface, do not reference outside the <pkg> package but make a copy if
  you need")
- `librusty_v8.nix` — per-platform v8 static lib hashes (auto-generated, DO NOT EDIT comment)

**Key patterns used by nixpkgs that the repo's own `default.nix` does NOT use:**

1. **`cargoHash`** instead of `cargoLock.outputHashes`

   nixpkgs uses a single `cargoHash` for the entire vendor directory:

   ```nix
   cargoHash = "sha256-N9jbH/cgAyu2QxneSnpkdaF0MgV3ZtDmN9q6rr9u+hE=";
   ```

   This is a fixed-output hash over the full vendored crate tree. It eliminates per-git-dependency
   hash maintenance entirely. When ANY dependency changes (git or registry), ONE hash updates.
   Compare to the repo's `default.nix` which has 7 separate `outputHashes` entries that each go
   stale independently.

   Trade-off: `cargoHash` requires network access during the vendor phase (to download crates and
   compute the hash), but the vendor derivation itself is a fixed-output derivation so it's cached
   after first build. `cargoLock.lockFile` with `outputHashes` does not require network during eval
   but requires manual hash maintenance for every git dependency.

   For a repo's own flake (not nixpkgs), `cargoHash` is strictly better because there is no
   gatekeeper review cycle — the maintainer computes the hash once via `nix build` with
   `cargoHash = lib.fakeHash` and pastes the result.

   For downstream `.overrideAttrs` consumers who need to bump `cargoHash` independently without
   triggering a full re-vendor, the documented escape hatch is to expose `cargoDeps` explicitly (per
   `lldap/package.nix`):

   ```nix
   cargoDeps = rustPlatform.fetchCargoVendor {
     name = "${finalAttrs.pname}-cargo-deps";
     inherit (finalAttrs) src patches;
     hash = finalAttrs.cargoHash;
   };
   ```

2. **`cargoBuildFlags`** to build only specific packages

   ```nix
   cargoBuildFlags = [
     "--package" "codex-cli"
     "--package" "codex-code-mode-host"
   ];
   cargoCheckFlags = [
     "--package" "codex-cli"
     "--package" "codex-code-mode-host"
   ];
   ```

   The codex workspace has 100+ crates. Building all of them pulls in:
   - `voice-host` → requires `glib`, `gstreamer`, `gst-plugins-base`, `alsa-lib`
   - `v8-poc` → requires pre-fetched `librusty_v8` static archive
   - `windows-sandbox-rs` → Windows-only crates that fail on Linux
   - `mxc-sandbox` → requires `appcontainer_common` from `microsoft/mxc`

   By building only `codex-cli` and `codex-code-mode-host`, nixpkgs avoids ALL of these dependencies
   except `librusty_v8` (needed by `codex-code-mode-host` for V8 execution).

   Maturity signal from nixpkgs: `cargoCheckFlags` should mirror `cargoBuildFlags` (as in
   `spacetimedb`, `stalwart`). Asymmetric build/test package sets is a common source of "works to
   build, fails cargoCheckHook" bugs.

   Alternative syntaxes proven in nixpkgs:
   - `--workspace --exclude=<crate>` (used by `cxx-rs`, `pipeweaver`)
   - `--bin <name>` for a single binary (used by `jujutsu`)
   - Platform-conditional exclusion:
     `lib.optionals stdenv.hostPlatform.isDarwin ["--exclude=<crate>"]` (used by `spade`)

3. **Pre-fetched `librusty_v8`**

   The `v8` crate's `build.rs` tries to download a pre-compiled static library from GitHub at build
   time. Inside the nix sandbox, there is no network access. nixpkgs solves this with three files.

   This pattern is reused verbatim across at least five unrelated nixpkgs packages (`deno`,
   `brioche`, `spacetimedb`, `windmill`, `codex`), confirming it is the canonical idiom for any Rust
   crate whose `build.rs` downloads a prebuilt static lib. The `windmill/fetchers.nix` explicitly
   comments "not a stable interface, do not reference outside the windmill package but make a copy
   if you need" — copy-and-inline is the sanctioned approach.

   `fetchers.nix`:

   ```nix
   {
     fetchLibrustyV8 = args: fetchurl {
       name = "librusty_v8-${args.version}";
       url = "https://github.com/denoland/rusty_v8/releases/download/v${args.version}/librusty_v8_release_${stdenv.hostPlatform.rust.rustcTarget}.a.gz";
       sha256 = args.shas.${stdenv.hostPlatform.system};
       meta = {
         inherit (args) version;
         sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
       };
     };
   }
   ```

   `librusty_v8.nix`:

   ```nix
   { fetchLibrustyV8 }:
   fetchLibrustyV8 {
     version = "146.4.0";
     shas = {
       x86_64-linux = "sha256-...";
       aarch64-linux = "sha256-...";
       x86_64-darwin = "sha256-...";
       aarch64-darwin = "sha256-...";
     };
   };
   ```

   `package.nix`:

   ```nix
   env = {
     RUSTY_V8_ARCHIVE = librusty_v8;
   };
   ```

   The `v8` crate's `build.rs` checks `RUSTY_V8_ARCHIVE` before attempting any download. If the env
   var points to an existing `.a.gz` file, it uses it directly.

   **Simpler alternative for standalone flakes:** `kopuz/package.nix` skips the three-file
   indirection entirely and defines `librustyV8 = fetchurl { ... }` directly in a `let` block with a
   hash-lookup-or-throw guard:

   ```nix
   rustyV8Hashes.${rustyV8Target}
     or (throw "no prebuilt librusty_v8 hash for target ${rustyV8Target}")
   ```

   This is equally mature and simpler when you don't need `nix-update`'s `--subpackage` machinery.
   For the codex repo flake (not nixpkgs), consider this inline variant.

4. **`__structuredAttrs = true`**

   Modern nixpkgs convention for new derivations. Passes derivation attributes as a JSON file to the
   builder instead of environment variables. Improves reproducibility and avoids shell escaping
   issues with complex values.

5. **`postPatch` to disable LTO and codegen-units**

   ```nix
   postPatch = ''
     substituteInPlace Cargo.toml \
       --replace-fail 'lto = "thin"' "" \
       --replace-fail 'codegen-units = 4' ""
   '';
   ```

   LTO and restricted codegen-units are release optimizations that dramatically increase build time
   and memory usage. nixpkgs disables them because the build happens in a constrained sandbox and
   the binary is already optimized enough without LTO for distribution purposes.

6. **Runtime PATH wrapper with `bubblewrap` + `socat`**

   ```nix
   postFixup = ''
     wrapProgram $out/bin/codex --prefix PATH : ${
       lib.makeBinPath ([ ripgrep ] ++ lib.optionals stdenv.hostPlatform.isLinux [ bubblewrap ])
     }
   '';
   ```

   The most directly relevant precedent is `claude-code/package.nix` — same problem domain (AI
   terminal coding agent), same runtime dependencies:

   ```nix
   wrapProgram $out/bin/claude \
     --set DISABLE_AUTOUPDATER 1 \
     --set-default FORCE_AUTOUPDATE_PLUGINS 1 \
     --set DISABLE_INSTALLATION_CHECKS 1 \
     --set USE_BUILTIN_RIPGREP 0 \
     --prefix PATH : ${lib.makeBinPath (
       [ procps ripgrep ]
       ++ lib.optionals stdenv.hostPlatform.isLinux [ bubblewrap socat ]
     )}
   ```

   Note `socat` alongside `bubblewrap` (used by sandboxed subprocess IPC) and
   `--set DISABLE_AUTOUPDATER 1` env-var pattern for neutralizing self-update logic without patching
   source. `sandbox-runtime/package.nix` (Anthropic) confirms the same
   `ripgrep + which + [bubblewrap socat]-if-Linux` set as the modal dependency list for this class
   of tool.

   **Ceiling recommendation for codex**: add `socat` if `codex-rs/exec-server` uses socket-based IPC
   for sandboxed subprocesses. Prefer `--set`/`--set-default` env-var toggles for
   autoupdate/telemetry over `postPatch` source edits where upstream already exposes env-var
   controls — it's strictly less fragile against upstream refactors.

7. **Source filtering with `lib.fileset.toSource`**

   For a repo's own flake, the idiomatic equivalent of nixpkgs' `fetchFromGitHub` is
   `lib.fileset.toSource` to filter the source tree to only the files that matter, avoiding `.git`,
   build artifacts, editor configs in the store:

   ```nix
   src = lib.fileset.toSource {
     root = ./.;
     fileset = lib.fileset.unions [ ./codex-rs ];
   };
   ```

8. **Dual version-check pattern**

   nixpkgs uses two complementary mechanisms:
   - `versionCheckHook` via `nativeInstallCheckInputs` + `doInstallCheck = true` —
     **build-blocking**, fails the derivation if version string is wrong
   - `passthru.tests.version = testers.testVersion { package = finalAttrs.finalPackage; }` —
     **out-of-band**, used by OfBorg and `nix flake check`, does not block build

   The ceiling pattern uses both (see `restate`, `veilid`, `cxx-rs`):

   ```nix
   doInstallCheck = true;
   nativeInstallCheckInputs = [ versionCheckHook ];

   passthru.tests.version = testers.testVersion {
     package = finalAttrs.finalPackage;
     command = "codex --version";
   };
   ```

9. **`_experimental-update-script-combinators.sequence`**

   This combinator is a real, exported nixpkgs library function at
   `pkgs/common-updater/combinators.nix`. It chains multiple update scripts with compatible
   `supportedFeatures` into a single `sh -ec` invocation. Used by `brioche` (chain
   `nix-update-script` + `update-librusty.sh`), `spade` (chain custom `git ls-remote`
   version-finder + `nix-update-script`), `ashpd-demo`/`libglycin` (chain `gitUpdater` + cargo
   vendored-hash refresh).

   For the codex repo flake, this enables:

   ```nix
   passthru.updateScript = _experimental-update-script-combinators.sequence [
     (nix-update-script { })
     ./update-librusty.sh
   ];
   ```

### 1.2 nixpkgs opencode (`pkgs/by-name/op/opencode/`)

**Files:**

- `package.nix` — main derivation (version 1.15.10, includes inline `node_modules` FOD)

**Key patterns:**

1. **Two-derivation FOD Bun pattern**

   The `node_modules` derivation is a fixed-output derivation (FOD):

   ```nix
   node_modules = stdenvNoCC.mkDerivation {
     pname = "${finalAttrs.pname}-node_modules";
     inherit (finalAttrs) version src;
     nativeBuildInputs = [ bun writableTmpDirAsHomeHook ];
     buildPhase = ''
       export BUN_INSTALL_CACHE_DIR=$(mktemp -d)
       bun install \
         --cpu="*" --frozen-lockfile \
         --filter ./ --filter ./packages/app \
         --filter ./packages/desktop --filter ./packages/opencode \
         --filter ./packages/shared \
         --ignore-scripts --no-progress --os="*"
       bun --bun ./nix/scripts/canonicalize-node-modules.ts
       bun --bun ./nix/scripts/normalize-bun-binaries.ts
     '';
     installPhase = ''
       mkdir -p $out
       find . -type d -name node_modules -exec cp -R --parents {} $out \;
     '';
     dontFixup = true;
     outputHash = "sha256-...";
     outputHashAlgo = "sha256";
     outputHashMode = "recursive";
   };
   ```

   The main derivation copies this vendored tree in during `configurePhase`:

   ```nix
   configurePhase = ''
     cp -R ${finalAttrs.node_modules}/. .
     patchShebangs node_modules
     patchShebangs packages/*/node_modules
   '';
   ```

   This pattern exists because `bun install` requires network access, which is not available in the
   nix sandbox. The FOD has network access (it's fetching external content) but its output is
   content-addressed by the `outputHash`.

   This same two-derivation pattern is used by `kilo` (an opencode fork), confirming it generalizes
   across the opencode family of forks.

2. **`models-dev` integration**

   ```nix
   env.MODELS_DEV_API_JSON = "${models-dev}/dist/_api.json";
   env.OPENCODE_DISABLE_MODELS_FETCH = true;
   ```

   OpenCode fetches a model catalog from the network at runtime. In the nix build, this is disabled
   and a pre-built catalog from the `models-dev` nixpkgs package is injected instead.

3. **`postPatch` to relax Bun version check**

   ```nix
   postPatch = ''
     substituteInPlace packages/script/src/index.ts \
       --replace-fail 'throw new Error(`This script requires bun@...' \
                      'console.warn(`Warning: This script requires bun@...'
   '';
   ```

   nixpkgs ships a specific Bun version that may not match the exact version the project expects.
   The postPatch converts the hard error to a warning.

4. **Single unambiguous install line**

   ```nix
   install -Dm755 dist/opencode-*/bin/opencode $out/bin/opencode
   ```

   The glob `dist/opencode-*/bin/opencode` matches exactly one file per platform. The build script
   (`packages/opencode/script/build.ts`) constructs the directory name from `pkg.name`
   ("opencode") + platform + arch, producing `dist/opencode-linux-x64/bin/opencode`.

5. **Schema generation and distribution**

   ```nix
   bun --bun ./script/schema.ts config.json tui.json
   install -Dm644 config.json $out/share/opencode/config.json
   install -Dm644 tui.json $out/share/opencode/tui.json
   ```

   Config schemas are generated at build time and installed to `$out/share/`. The
   `passthru.jsonschema` attrset provides paths for consumers:

   ```nix
   passthru.jsonschema = {
     config = "${placeholder "out"}/share/opencode/config.json";
     tui = "${placeholder "out"}/share/opencode/tui.json";
   };
   ```

6. **`nix-update-script` with `--subpackage`**

   ```nix
   passthru.updateScript = nix-update-script {
     extraArgs = [ "--subpackage" "node_modules" ];
   };
   ```

   This tells `nix-update` to also update the `node_modules` FOD hash when bumping the version.
   Without `--subpackage`, only `src.hash` would update.

### 1.3 nixpkgs opencode-desktop (`pkgs/by-name/op/opencode-desktop/`)

This is a real, existing nixpkgs package — not something to construct by analogy. It already
implements every fix proposed for `anomalyco/opencode`'s `nix/desktop.nix`. The v2 branch's
`nix/desktop.nix` should be diffed against this file directly.

**Key patterns:**

1. **No `getCurrentCli()` / baseline variant issue**

   nixpkgs does NOT copy a pre-built CLI binary into the desktop bundle via `getCurrentCli()`.
   Instead, it builds the node bundle directly:

   ```nix
   cd packages/opencode
   bun --bun ./script/build-node.ts --skip-install
   cd ../..
   ```

   This produces a Node.js-compatible bundle (not a Bun-compiled binary), which the desktop app uses
   as its embedded server. No CLI binary name resolution, no baseline variant mismatch, no
   `copyBuiltCliToResources`.

2. **`electron-vite` + `electron-builder` with version guard**

   ```nix
   node_modules/.bin/electron-vite build
   node_modules/.bin/electron-builder --dir \
     --config=electron-builder.config.ts \
     --config.electronDist="$HOME/.electron-dist" \
     --config.electronVersion=${electron.version} \
     --config.asarUnpack='**/*.node'
   ```

   The `equibop` and `vesktop` nixpkgs packages add a `preBuild` version guard that asserts
   `electron.version`'s major matches `package.json`'s `devDependencies.electron` before building,
   failing loudly instead of producing a subtly-broken build:

   ```nix
   preBuild = ''
     expectedMajor="$(jq -r '.devDependencies.electron | ltrimstr("^") | split(".") | .[0]' < package.json)"
     actualMajor="${lib.versions.major electron.version}"
     if [ "$actualMajor" != "$expectedMajor" ]; then
       echo "ERROR: electron version mismatch"
       exit 1
     fi
   '';
   ```

   This should be adopted in the opencode desktop rewrite.

3. **Disables auto-updater at source**

   ```nix
   substituteInPlace packages/desktop/src/main/constants.ts \
     --replace-fail 'app.isPackaged && CHANNEL !== "dev"' 'false'
   ```

   The auto-updater would download and run an unpatched upstream binary, breaking the nix-managed
   installation.

4. **macOS codesigning bypass via JS patch**

   ```nix
   preBuild = lib.optionalString stdenvNoCC.hostPlatform.isDarwin ''
     for f in $(find node_modules -path "*/app-builder-lib/out/codeSign/macCodeSign.js" -type f 2>/dev/null); do
       substituteInPlace "$f" \
         --replace-fail "async function getValidIdentities" \
         "async function getValidIdentities() { return []; }; async function getValidIdentities_DISABLED"
     done
   '';
   ```

   The sandbox can't spawn `security find-identity`. Simpler `-c.mac.identity=null` alone is
   insufficient because electron-builder still tries to invoke the system security binary to check
   if signing is even possible.

5. **Modern derivation conventions**

   ```nix
   __structuredAttrs = true;
   strictDeps = true;
   autoPatchelfIgnoreMissingDeps = [ "libc.musl-*.so.*" ];
   ```

   The musl prebuilts ship `libc.musl-*.so.1` SONAMEs that `autoPatchelfHook` can't resolve on glibc
   systems. They aren't loaded at runtime anyway.

6. **Icon installation with all sizes**

   Installs icons at 32, 64, 128, plus Windows-style Square sizes (30, 44, 71, 89, 107, 142, 150,
   284, 310).

7. **Writable electron dist copy**

   ```nix
   cp -r "${electron.dist}" $HOME/.electron-dist
   chmod -R u+w $HOME/.electron-dist
   ```

   `electron-builder` tries to `chmod`/mutate the dist directory in place. This is required, not
   optional boilerplate — universal across every Electron package in nixpkgs.

---

## Part 2: Defects found in each repo's flake packaging

### 2.1 `openai/codex` — `codex-rs/default.nix` + `flake.nix`

| #   | Defect                                                       | Root cause                                                            | Fix                                                             |
| --- | ------------------------------------------------------------ | --------------------------------------------------------------------- | --------------------------------------------------------------- |
| 1   | `cargoLock.outputHashes` missing `appcontainer_common-0.8.0` | `Cargo.lock` added `microsoft/mxc` git dep, `default.nix` not updated | Switch to `cargoHash`                                           |
| 2   | `crossterm-0.29.0` hash stale                                | Hash computed against old nixpkgs fetcher                             | Switch to `cargoHash`                                           |
| 3   | `tungstenite-0.27.0` hash stale                              | Same                                                                  | Switch to `cargoHash`                                           |
| 4   | `tokio-tungstenite-0.28.0` hash stale                        | Same                                                                  | Switch to `cargoHash`                                           |
| 5   | `stdenv.isLinux` (2 sites)                                   | Deprecated API                                                        | `stdenv.hostPlatform.isLinux`                                   |
| 6   | Missing `glib` build input                                   | `voice-host` → `gstreamer` → `glib-sys`                               | Exclude `voice-host` via `cargoBuildFlags`                      |
| 7   | Missing `gstreamer` + `gst-plugins-base`                     | Same chain                                                            | Same                                                            |
| 8   | Missing `alsa-lib`                                           | `voice-host` → `cpal` → `alsa-sys`                                    | Same                                                            |
| 9   | Missing `librusty_v8` prefetch                               | `v8` crate's `build.rs` downloads in sandbox                          | Add `fetchers.nix` + `librusty_v8.nix` + `RUSTY_V8_ARCHIVE` env |
| 10  | `src = ./.` includes entire repo                             | Unnecessary files in store, dirty-tree warnings                       | `lib.fileset.toSource`                                          |
| 11  | `flake.lock` nixpkgs 8 months stale                          | CA cert bundle expired, SSL failures                                  | `nix flake update`                                              |
| 12  | No `cargoBuildFlags`                                         | Builds entire 100+ crate workspace                                    | `--package codex-cli --package codex-code-mode-host`            |
| 13  | No `overlays.default` output                                 | Consumers can't use as overlay                                        | Add                                                             |
| 14  | No `checks` output                                           | No `nix flake check` validation                                       | Add `testers.testVersion`                                       |
| 15  | No `formatter` output                                        | No `nix fmt`                                                          | Add `pkgs.nixfmt-tree`                                          |
| 16  | No `bubblewrap`/`socat` in PATH wrapper                      | Sandboxing broken on Linux                                            | Add `postFixup` wrapper                                         |
| 17  | No `ripgrep` in PATH wrapper                                 | Search broken                                                         | Add to wrapper                                                  |
| 18  | No shell completions                                         | No bash/fish/zsh completions installed                                | Add `installShellFiles` + `installShellCompletion`              |
| 19  | No `__structuredAttrs`                                       | Not using modern convention                                           | Add                                                             |
| 20  | No LTO/codegen-units disable                                 | Slow builds                                                           | Add `postPatch`                                                 |
| 21  | No `LIBCLANG_PATH` env                                       | `bindgen` can't find `libclang`                                       | Add env var                                                     |
| 22  | No Darwin lld linkage                                        | ARM64 branch thunk failures on macOS                                  | Add `NIX_CFLAGS_LINK` with `ld64.lld`                           |
| 23  | No `cargoDeps` override escape hatch                         | Downstream can't override `cargoHash` cleanly                         | Add explicit `cargoDeps`                                        |

### 2.2 `anomalyco/opencode` v2 — `nix/opencode.nix` + `nix/desktop.nix` + `flake.nix`

| #   | Defect                                                 | Root cause                                                                         | Fix                                                                                  |
| --- | ------------------------------------------------------ | ---------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------ |
| 1   | `nix/opencode.nix` line 65: `dist/cli-*/bin/opencode2` | Build outputs `dist/cli-*/bin/opencode`                                            | Change `opencode2` to `opencode` in source path                                      |
| 2   | `nix/desktop.nix` line 69: `stdenv.isLinux`            | Deprecated                                                                         | `stdenv.hostPlatform.isLinux`                                                        |
| 3   | `nix/desktop.nix` baseline variant mismatch            | `getCurrentCli()` resolves to `cli-linux-x64-baseline`, nix builds `cli-linux-x64` | Rewrite to use `build-node.ts` (diff against nixpkgs `opencode-desktop/package.nix`) |
| 4   | No `checks` output in `flake.nix`                      | Missing                                                                            | Add `testers.testVersion`                                                            |
| 5   | No `formatter` output in `flake.nix`                   | Missing                                                                            | Add `pkgs.nixfmt-tree`                                                               |
| 6   | `nix/desktop.nix` auto-updater not disabled            | Would download unpatched binary                                                    | Add `substituteInPlace` for `constants.ts`                                           |
| 7   | No `__structuredAttrs`/`strictDeps` in desktop         | Not using modern convention                                                        | Add                                                                                  |
| 8   | No electron version guard in desktop                   | Silent breakage on electron major mismatch                                         | Add `preBuild` assertion (per `equibop`/`vesktop`)                                   |
| 9   | No macOS codesigning bypass in desktop                 | Build fails in sandbox on Darwin                                                   | Add JS patch for `getValidIdentities`                                                |
| 10  | No `autoPatchelfIgnoreMissingDeps` for musl            | `autoPatchelfHook` errors on musl SONAMEs                                          | Add `[ "libc.musl-*.so.*" ]`                                                         |

### 2.3 `NixOS/nixpkgs` — version staleness

| Package            | nixpkgs version    | Current upstream | Gap                 |
| ------------------ | ------------------ | ---------------- | ------------------- |
| `codex`            | 0.146.0            | 0.154.0          | 8 releases behind   |
| `opencode`         | 1.15.10            | 1.18.30          | ~20 releases behind |
| `opencode-desktop` | (matches opencode) | 1.18.30          | Same                |

---

## Part 3: Implementation — `openai/codex` flake rewrite

### 3.1 New file: `codex-rs/fetchers.nix`

Copied from nixpkgs' `pkgs/by-name/co/codex/fetchers.nix`. The `windmill` package's identical file
explicitly sanctions this copy-paste approach.

```nix
# not a stable interface — copied from nixpkgs pkgs/by-name/co/codex/fetchers.nix
{
  lib,
  stdenv,
  fetchurl,
}:

{
  fetchLibrustyV8 =
    args:
    fetchurl {
      name = "librusty_v8-${args.version}";
      url = "https://github.com/denoland/rusty_v8/releases/download/v${args.version}/librusty_v8_release_${stdenv.hostPlatform.rust.rustcTarget}.a.gz";
      sha256 = args.shas.${stdenv.hostPlatform.system};
      meta = {
        inherit (args) version;
        sourceProvenance = with lib.sourceTypes; [ binaryNativeCode ];
      };
    };
}
```

### 3.2 New file: `codex-rs/librusty_v8.nix`

The `version` must match the `v8` crate version in `Cargo.lock`. The hashes are obtained by running
`nix-prefetch-url` for each platform's `.a.gz` URL.

To find the correct v8 version:

```bash
grep 'name = "v8"' codex-rs/Cargo.lock -A 2
```

To compute hashes:

```bash
for target in x86_64-unknown-linux-gnu aarch64-unknown-linux-gnu x86_64-apple-darwin aarch64-apple-darwin; do
  echo "$target: $(nix-prefetch-url https://github.com/denoland/rusty_v8/releases/download/v${VERSION}/librusty_v8_release_${target}.a.gz)"
done
```

```nix
# auto-generated file — update hashes when bumping the v8 crate version
{ fetchLibrustyV8 }:

fetchLibrustyV8 {
  version = "150.4.0";  # must match Cargo.lock v8 crate version
  shas = {
    x86_64-linux = "sha256-PLACEHOLDER";
    aarch64-linux = "sha256-PLACEHOLDER";
    x86_64-darwin = "sha256-PLACEHOLDER";
    aarch64-darwin = "sha256-PLACEHOLDER";
  };
}
```

### 3.3 Rewritten file: `codex-rs/default.nix`

```nix
{
  lib,
  stdenv,
  callPackage,
  rustPlatform,
  bubblewrap,
  clang,
  cmake,
  gitMinimal,
  installShellFiles,
  libcap,
  libclang,
  librusty_v8 ? callPackage ./librusty_v8.nix {
    inherit (callPackage ./fetchers.nix { }) fetchLibrustyV8;
  },
  lld,
  makeBinaryWrapper,
  openssl,
  pkg-config,
  ripgrep,
  socat,
  testers,
  versionCheckHook,
  version ? "0.0.0",
  installShellCompletions ? stdenv.buildPlatform.canExecute stdenv.hostPlatform,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "codex";
  inherit version;

  __structuredAttrs = true;

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.gitTracked ./.;
  };

  cargoHash = "sha256-PLACEHOLDER";  # nix build with lib.fakeHash, paste result

  # Build only the two packages that matter. This excludes voice-host (gstreamer/alsa),
  # v8-poc, windows-sandbox-rs, mxc-sandbox, and 90+ other workspace crates.
  cargoBuildFlags = [
    "--package" "codex-cli"
    "--package" "codex-code-mode-host"
  ];
  cargoCheckFlags = finalAttrs.cargoBuildFlags;

  doCheck = false;

  postPatch = ''
    # Disable LTO and restricted codegen-units for faster nix builds
    substituteInPlace Cargo.toml \
      --replace-fail 'lto = "thin"' "" \
      --replace-fail 'codegen-units = 4' ""

    # Patch workspace version for CARGO_PKG_VERSION embedding
    sed -i 's/^version = "0\.0\.0"$/version = "${version}"/' Cargo.toml
  '';

  nativeBuildInputs = [
    clang
    cmake
    gitMinimal
    installShellFiles
    makeBinaryWrapper
    pkg-config
  ];

  buildInputs = [
    libclang
    openssl
  ] ++ lib.optionals stdenv.hostPlatform.isLinux [
    libcap
  ];

  env = {
    LIBCLANG_PATH = "${lib.getLib libclang}/lib";
    RUSTY_V8_ARCHIVE = librusty_v8;
    NIX_CFLAGS_COMPILE = toString (
      lib.optionals stdenv.cc.isGNU [ "-Wno-error=stringop-overflow" ]
      ++ lib.optionals stdenv.cc.isClang [ "-Wno-error=character-conversion" ]
    );
  } // lib.optionalAttrs stdenv.hostPlatform.isDarwin {
    NIX_CFLAGS_LINK = "-fuse-ld=${lib.getExe' lld "ld64.lld"}";
  };

  postInstall = lib.optionalString installShellCompletions ''
    installShellCompletion --cmd codex \
      --bash <($out/bin/codex completion bash) \
      --fish <($out/bin/codex completion fish) \
      --zsh <($out/bin/codex completion zsh)
  '';

  postFixup = ''
    wrapProgram $out/bin/codex --prefix PATH : ${
      lib.makeBinPath (
        [ ripgrep ]
        ++ lib.optionals stdenv.hostPlatform.isLinux [ bubblewrap socat ]
      )
    }
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHook ];

  passthru = {
    tests.version = testers.testVersion {
      package = finalAttrs.finalPackage;
      command = "codex --version";
    };
  };

  meta = {
    description = "Lightweight coding agent that runs in your terminal";
    homepage = "https://github.com/openai/codex";
    license = lib.licenses.asl20;
    mainProgram = "codex";
    platforms = lib.platforms.unix;
  };
})
```

### 3.4 Rewritten file: `flake.nix`

```nix
{
  description = "OpenAI Codex CLI — lightweight coding agent";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, rust-overlay, ... }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
        "x86_64-darwin"
        "aarch64-darwin"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems f;

      cargoToml = builtins.fromTOML (builtins.readFile ./codex-rs/Cargo.toml);
      cargoVersion = cargoToml.workspace.package.version;
      version =
        if cargoVersion != "0.0.0"
        then cargoVersion
        else "0.0.0-dev+${self.shortRev or "dirty"}";
    in
    {
      packages = forAllSystems (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ rust-overlay.overlays.default ];
          };
          codex = pkgs.callPackage ./codex-rs {
            inherit version;
            rustPlatform = pkgs.makeRustPlatform {
              cargo = pkgs.rust-bin.stable.latest.minimal;
              rustc = pkgs.rust-bin.stable.latest.minimal;
            };
          };
        in
        {
          inherit codex;
          default = codex;
        }
      );

      overlays.default = final: _prev: {
        codex = final.callPackage ./codex-rs {
          inherit version;
          rustPlatform = final.makeRustPlatform {
            cargo = final.rust-bin.stable.latest.minimal;
            rustc = final.rust-bin.stable.latest.minimal;
          };
        };
      };

      checks = forAllSystems (system: {
        version = self.packages.${system}.default.passthru.tests.version;
      });

      formatter = forAllSystems (system:
        (import nixpkgs { inherit system; }).nixfmt-tree
      );

      devShells = forAllSystems (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            overlays = [ rust-overlay.overlays.default ];
          };
          rust = pkgs.rust-bin.stable.latest.default.override {
            extensions = [ "rust-src" "rust-analyzer" ];
          };
        in
        {
          default = pkgs.mkShell {
            buildInputs = [
              rust
              pkgs.pkg-config
              pkgs.openssl
              pkgs.cmake
              pkgs.llvmPackages.clang
              pkgs.llvmPackages.libclang.lib
            ];
            PKG_CONFIG_PATH = "${pkgs.openssl.dev}/lib/pkgconfig";
            LIBCLANG_PATH = "${pkgs.llvmPackages.libclang.lib}/lib";
            shellHook = ''
              export CC=clang
              export CXX=clang++
            '';
          };
        }
      );
    };
}
```

---

## Part 4: Implementation — `anomalyco/opencode` v2 flake fixes

### 4.1 File: `nix/opencode.nix` — line 65 fix

**Before:**

```nix
install -Dm755 dist/cli-*/bin/opencode2 $out/bin/opencode2
```

**After:**

```nix
install -Dm755 dist/cli-*/bin/opencode $out/bin/opencode2
```

Rationale: `packages/cli/script/build.ts` line 15 sets `const binary = "opencode"`. Line 121
constructs the directory name as `target.replace(binary, "cli")` → `cli-linux-x64`. Line 141 outputs
to `path.join(outdir, name, "bin", binary)` → `dist/cli-linux-x64/bin/opencode`. The destination
`$out/bin/opencode2` is intentional — upstream wants the v2 CLI installed as `opencode2` so it
coexists with v1 `opencode`. The Dockerfile confirms this:
`RUN ln -s opencode /usr/local/bin/opencode2`.

### 4.2 File: `nix/desktop.nix` — rewrite

The existing `nix/desktop.nix` should be rewritten by diffing against nixpkgs'
`pkgs/by-name/op/opencode-desktop/package.nix` directly. The nixpkgs file is the reference — it
already solves every defect identified in §2.2.

Key changes from current v2 `desktop.nix`:

1. **Replace `getCurrentCli()` binary copy with `build-node.ts`:**

   ```nix
   # BEFORE (broken):
   export OPENCODE_CLI_DIST="$TMPDIR/desktop-cli"
   cli_package=$(bun -e 'import { getCurrentCli } from "./scripts/utils.ts"; ...')
   mkdir -p "$OPENCODE_CLI_DIST/$cli_package/bin"
   cp ${lib.getExe opencode} "$OPENCODE_CLI_DIST/$cli_package/bin/opencode2"

   # AFTER (nixpkgs pattern):
   cd packages/opencode
   bun --bun ./script/build-node.ts --skip-install
   cd ../..
   cd packages/desktop
   ```

   This eliminates the entire `getCurrentCli()` → baseline variant resolution chain. The desktop app
   uses the node bundle directly, not a compiled CLI binary. No CLI binary name resolution, no
   baseline variant mismatch, no `copyBuiltCliToResources`.

2. **Add auto-updater disable:**

   ```nix
   substituteInPlace packages/desktop/src/main/constants.ts \
     --replace-fail 'app.isPackaged && CHANNEL !== "dev"' 'false'
   ```

3. **Add macOS codesigning bypass:**

   ```nix
   preBuild = lib.optionalString stdenvNoCC.hostPlatform.isDarwin ''
     for f in $(find node_modules -path "*/app-builder-lib/out/codeSign/macCodeSign.js" -type f 2>/dev/null); do
       substituteInPlace "$f" \
         --replace-fail "async function getValidIdentities" \
         "async function getValidIdentities() { return []; }; async function getValidIdentities_DISABLED"
     done
   '';
   ```

4. **Add electron version guard (per `equibop`/`vesktop`):**

   ```nix
   preBuild = ''
     expectedMajor="$(jq -r '.devDependencies.electron | ltrimstr("^") | split(".") | .[0]' < package.json)"
     actualMajor="${lib.versions.major electron.version}"
     if [ "$actualMajor" != "$expectedMajor" ]; then
       echo "ERROR: electron version mismatch between package.json (major $expectedMajor) and nixpkgs (major $actualMajor)"
       exit 1
     fi
   '' + ...codesigning bypass...
   ```

5. **Fix `stdenv.isLinux`** → `stdenv.hostPlatform.isLinux` on all sites.

6. **Add modern conventions:**

   ```nix
   __structuredAttrs = true;
   strictDeps = true;
   autoPatchelfIgnoreMissingDeps = [ "libc.musl-*.so.*" ];
   ```

7. **Use `electron-vite` + `electron-builder --dir`:**
   ```nix
   node_modules/.bin/electron-vite build
   node_modules/.bin/electron-builder --dir \
     --config=electron-builder.config.ts \
     --config.electronDist="$HOME/.electron-dist" \
     --config.electronVersion=${electron.version} \
     --config.asarUnpack='**/*.node' \
     ${lib.optionalString stdenvNoCC.hostPlatform.isDarwin "--config.mac.identity=null"}
   ```

### 4.3 File: `flake.nix` — add missing outputs

```nix
checks = forEachSystem (pkgs:
  let
    node_modules = pkgs.callPackage ./nix/node_modules.nix { inherit rev; };
    opencode = pkgs.callPackage ./nix/opencode.nix { inherit node_modules; };
  in
  {
    opencode-version = opencode.passthru.tests.version or opencode;
  }
);

formatter = forEachSystem (pkgs: pkgs.nixfmt-tree);
```

---

## Part 5: Implementation — nixpkgs version bumps

### 5.1 `pkgs/by-name/co/codex/package.nix`

Changes needed:

1. `version = "0.146.0"` → `version = "0.154.0"` (or latest `rust-v*` tag)
2. `src.hash` → recompute via `nix-prefetch-github openai codex --rev rust-v0.154.0`
3. `cargoHash` → recompute via `nix build` with `cargoHash = lib.fakeHash`
4. `librusty_v8.nix` version → check `Cargo.lock` for `v8` crate version, update shas
5. Any new `buildInputs` required by the version bump
6. Any new `cargoBuildFlags` packages if release includes new binaries

### 5.2 `pkgs/by-name/op/opencode/package.nix`

Changes needed:

1. `version = "1.15.10"` → `version = "1.18.30"` (or latest `v*` tag)
2. `src.hash` → recompute
3. `node_modules.outputHash` → recompute via `nix build` with `outputHash = lib.fakeHash`
4. Review `postPatch` — check if `packages/script/src/index.ts` still has the same Bun version check
5. Review `installPhase` — verify `dist/opencode-*/bin/opencode` still matches
6. Review `bun install --filter` list — check if workspace packages changed

### 5.3 `pkgs/by-name/op/opencode-desktop/package.nix`

Changes needed:

1. Inherits version from `opencode` — bumps automatically
2. `electron_41` → check if desktop's `package.json` `devDependencies.electron` version matches;
   update to `electron_42` if needed (the preBuild version guard will fail loudly if not)
3. Review `postPatch` — `constants.ts` substitution may have changed
4. Review `buildPhase` — `electron-vite build` and `electron-builder` invocations

---

## Part 6: Implementation — home-manager consumer

### 6.1 Interim state (local forks)

```nix
# flake.nix inputs
opencode2 = {
  url = "git+file:///workspace/usrbinkat/github.com/anomalyco/opencode?ref=v2";
};
codex = {
  url = "git+file:///workspace/usrbinkat/github.com/openai/codex";
};
```

### 6.2 Final state (after PRs merge)

```nix
# flake.nix inputs
opencode2 = {
  url = "github:anomalyco/opencode/v2";
};
codex = {
  url = "github:openai/codex";
};
```

### 6.3 `hosts/mithril.nix` packages

```nix
home.packages = [
  opencode2.packages.${system}.opencode
  opencode2.packages.${system}.opencode-desktop
  codex.packages.${system}.default
];
```

---

## Part 7: All consumption paths and what they exercise

Every flake output is a consumption path. A maximally complete flake supports all of these:

| #   | Path                  | Command / mechanism                                   | Required flake output                                     |
| --- | --------------------- | ----------------------------------------------------- | --------------------------------------------------------- |
| 1   | `nix run`             | `nix run github:openai/codex`                         | `packages.${system}.default` + `meta.mainProgram`         |
| 2   | `nix build`           | `nix build github:openai/codex`                       | `packages.${system}.default`                              |
| 3   | `nix profile install` | `nix profile install github:openai/codex`             | `packages.${system}.default`                              |
| 4   | `nix shell`           | `nix shell github:openai/codex`                       | `packages.${system}.default`                              |
| 5   | `nix develop`         | `nix develop github:openai/codex`                     | `devShells.${system}.default`                             |
| 6   | Overlay               | Consumer applies `overlays.default` to their pkgs     | `overlays.default`                                        |
| 7   | Direct ref            | `codex.packages.${system}.default` in `home.packages` | `packages.${system}.default`                              |
| 8   | `nix flake check`     | CI / local validation                                 | `checks.${system}.*`                                      |
| 9   | `nix fmt`             | Developer formatting                                  | `formatter.${system}`                                     |
| 10  | Cachix                | Pre-built substitution                                | Deterministic derivation + `nixConfig.extra-substituters` |

All 10 paths apply identically to both `openai/codex` and `anomalyco/opencode`, with opencode
additionally providing `opencode-desktop` as a second named package.

### 7.1 Overlay consumption example

```nix
# Consumer's flake.nix
{
  inputs.codex.url = "github:openai/codex";
  outputs = { nixpkgs, codex, ... }: {
    # Apply overlay to get pkgs.codex
    pkgs = import nixpkgs {
      system = "x86_64-linux";
      overlays = [ codex.overlays.default ];
    };
    # Now pkgs.codex is available anywhere pkgs is used
  };
}
```

### 7.2 Direct package reference in home-manager

```nix
# hosts/mithril.nix
home.packages = [
  codex.packages.${system}.default
  opencode2.packages.${system}.opencode
  opencode2.packages.${system}.opencode-desktop
];
```

---

## Part 8: Execution order

1. **Compute hashes** — `librusty_v8` shas for codex, `cargoHash` for codex,
   `node_modules.outputHash` for opencode nixpkgs bump
2. **Write codex files** — `fetchers.nix`, `librusty_v8.nix`, rewrite `default.nix`, rewrite
   `flake.nix`
3. **Verify codex build** — `nix build` from local clone
4. **Write opencode fixes** — `nix/opencode.nix` line 65, `nix/desktop.nix` rewrite, `flake.nix`
   additions
5. **Verify opencode build** — `nix build` for CLI and desktop
6. **Push to forks** — `usrbinkat/codex`, `usrbinkat/opencode`
7. **Open upstream PRs** — codex main, opencode v2
8. **nixpkgs bumps** — branch off `usrbinkat/nixpkgs`, bump both packages, open PRs
9. **Update home-manager** — point inputs at fork branches, verify `home-manager switch`
10. **After merge** — switch inputs to upstream URLs

---

## Part 9: Files touched — complete manifest

### `openai/codex` fork branch

| File                       | Action                        |
| -------------------------- | ----------------------------- |
| `codex-rs/default.nix`     | Rewrite                       |
| `codex-rs/fetchers.nix`    | Create                        |
| `codex-rs/librusty_v8.nix` | Create                        |
| `flake.nix`                | Rewrite                       |
| `flake.lock`               | Update via `nix flake update` |

### `anomalyco/opencode` fork branch (v2)

| File               | Action                                                        |
| ------------------ | ------------------------------------------------------------- |
| `nix/opencode.nix` | Fix line 65 (install source path)                             |
| `nix/desktop.nix`  | Rewrite (diff against nixpkgs `opencode-desktop/package.nix`) |
| `flake.nix`        | Add `checks`, `formatter` outputs                             |

### `NixOS/nixpkgs` fork branch

| File                                           | Action                               |
| ---------------------------------------------- | ------------------------------------ |
| `pkgs/by-name/co/codex/package.nix`            | Version bump + hash updates          |
| `pkgs/by-name/co/codex/librusty_v8.nix`        | Version + hash updates               |
| `pkgs/by-name/op/opencode/package.nix`         | Version bump + hash updates          |
| `pkgs/by-name/op/opencode-desktop/package.nix` | Version bump, electron version check |

### `home-manager` (local)

| File                | Action                                |
| ------------------- | ------------------------------------- |
| `flake.nix`         | Update `codex` and `opencode2` inputs |
| `flake.lock`        | Update via `nix flake update`         |
| `hosts/mithril.nix` | Enable all three packages             |
