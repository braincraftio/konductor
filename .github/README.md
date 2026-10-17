# GitHub automation

## Build and cache

`ci.yml` calls `nix.yml` on pushes and pull requests to `main`. The reusable workflow builds on
native x86_64 Linux, ARM Linux, and ARM macOS runners. It runs flake checks, builds the maintained
package outputs and k0sctl version test, and builds the default package and full devshell.
Linux-only targets are selected explicitly; the konductor and frontend shells run on x86_64 Linux.

`.github/actions/setup-nix` installs Determinate Nix and configures Cachix and optionally FlakeHub
Cache. Cachix always pulls (including the nix-community, scopecreep-zip, and usrbinkat caches) and
pushes through its daemon only when a credential is present and the caller does not set
`cachix-skip-push`. Push and release builds enable both remote caches. FlakeHub Cache authenticates
through GitHub OIDC; both the reusable workflow and its callers grant `id-token: write`. PR builds
leave FlakeHub Cache disabled. GitHub's Nix-store cache is disabled because this project's closure
exceeds its quota. The default Cachix cache is `braincraftio`; set the `CACHIX_NAME` repository
variable for a fork's build cache.

`BCIO_CACHIX_PRIVATE_KEY` retains the existing Cachix **API token** mapping. The secret name alone
does not establish its format. If its value is a private signing key, pass it through
`cachix-signing-key` instead. PR builds use the public cache without upload credentials; push and
release builds upload when the credential is available.

## Hash repair

After a failed PR build, `determinate-nixd fix hashes --auto-apply` attempts to repair hash
mismatches recorded by Determinate Nix. Each platform uploads a `hash-repairs-<system>` patch
containing changes to `src/lib/versions.nix`. The original build remains failed. Download and
inspect the patches, apply non-conflicting changes with `git apply`, then rebuild the affected
targets.

This keeps versions and hashes together and avoids concurrent matrix jobs pushing to the same
branch. Repairs depend on observed mismatches: a build failure unrelated to hashes can produce an
empty patch, and a source-hash repair may need another build before a dependency-hash mismatch is
exposed. Input revisions and `narHash` remain managed through `flake.lock`.

## Releases and website

Release automation runs after successful push CI and verifies that `main` still matches the tested
revision before invoking semantic-release. Release jobs are serialized. The follow-up cache build
uses the resulting release tag, including the generated changelog commit. Once all release cache
builds pass, `publish-flake` publishes that tag as a public FlakeHub release and registers its
output paths with `include-output-paths: true`. This is called directly from the release workflow
because tags created with `GITHUB_TOKEN` do not trigger a separate push workflow. The GitHub
organization must be authorized on FlakeHub for cache uploads and flake publication; no additional
long-lived FlakeHub secret is used.

### Shared actions

| Action                  | Responsibility                                            |
| ----------------------- | --------------------------------------------------------- |
| `setup-nix`             | Determinate installation, Cachix, optional FlakeHub Cache |
| `setup-devshell`        | `setup-nix`, then `nix profile install .#ci` onto `PATH`  |
| `upload-artifact`       | Single pinned `actions/upload-artifact`                   |
| `upload-pages-artifact` | Single pinned `actions/upload-pages-artifact`             |
| `deploy-pages`          | Single pinned `actions/deploy-pages`                      |
| `fix-nix-hashes`        | Hash repair and platform patch artifact                   |
| `semantic-release`      | Locked tool installation and structured release outputs   |
| `publish-flake`         | Verify release checkout and publish its tag to FlakeHub   |

Workflows own event triggers, permissions, platform matrices, and job ordering. Composite actions
own shared setup and publishing mechanics, and each third-party action is pinned by commit SHA in
exactly one place. Semantic release uses its JavaScript API for version/tag outputs rather than
parsing log text.

Runner tools come from the flake, not marketplace setup actions: `packages.<system>.ci` bundles node
(the `src/lib/versions.nix` pin), pnpm, git, jq, cachix, and actionlint. Pages and release jobs
consume it through `setup-devshell`. `nix.yml` builds `.#ci` and installs `.#default` with
`nix profile install` to exercise the consumer install path. Pages installs frontend dependencies
with the frozen lockfile and generates website release data through `.#versions-json`. Only the
deployment job gets Pages and OIDC write permissions.

Validate workflow edits locally with `actionlint` and `git diff --check`. Hosted runs are required
to verify runner installation, cache authentication, artifact uploads, and publishing.
