# GitHub Authentication for Nix Flakes

GitHub API rate limits can cause 403 errors when running `nix flake update`, `nix flake check`, or
similar commands. This is common on shared networks or CI environments.

Every `github:` input in `flake.nix` (the nixpkgs fork, home-manager, nixvim, rust-overlay, and the
others) is resolved through the GitHub API, so unauthenticated evaluation shares the anonymous rate
limit.

## Configure GitHub Access Token

1. Create a GitHub Personal Access Token at <https://github.com/settings/tokens>
   - No special permissions required (public repo access only)
   - Fine-grained tokens work

2. Add to `~/.config/nix/nix.conf`:

   ```ini
   access-tokens = github.com=ghp_<your-token>
   ```

3. Alternatively, set via environment variable:

   ```bash
   export NIX_CONFIG="access-tokens = github.com=ghp_<your-token>"
   ```

4. Or pass directly to nix commands:

   ```bash
   nix --extra-access-tokens github.com=ghp_<your-token> flake update
   ```

## References

- <https://discourse.nixos.org/t/flakes-provide-github-api-token-for-rate-limiting/18609>
