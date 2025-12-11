# GitHub Authentication for Nix Flakes

GitHub API rate limits can cause 403 errors when running `nix flake update`, `nix flake check`, or similar commands. This is common on shared networks or CI environments.

## Configure GitHub Access Token

1. Create a GitHub Personal Access Token at https://github.com/settings/tokens
   - No special permissions required (public repo access only)
   - Fine-grained tokens work

2. Add to `~/.config/nix/nix.conf`:
   ```
   access-tokens = github.com=ghp_xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
   ```

3. Alternatively, set via environment variable:
   ```bash
   export NIX_CONFIG="access-tokens = github.com=ghp_xxxx"
   ```

4. Or pass directly to nix commands:
   ```bash
   nix --extra-access-tokens github.com=ghp_xxxx flake update
   ```

## FlakeHub Alternative

This flake uses FlakeHub URLs for nixpkgs to avoid GitHub API calls entirely:
```nix
nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0.2511.*";
```

FlakeHub serves tarballs directly without hitting GitHub's API rate limits.

## References

- https://discourse.nixos.org/t/flakes-provide-github-api-token-for-rate-limiting/18609
- https://docs.determinate.systems/flakehub/
