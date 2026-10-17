# src/config/formatters/treefmt.nix
# Single formatting entrypoint: treefmt bound to the konductor-wrapped,
# store-pinned formatters. Consumed by:
#   - flake `formatter` output   → nix fmt [paths], nix fmt -- --ci
#   - flake checks.treefmt       → --ci --walk filesystem on a writable copy
#   - lefthook pre-commit `fmt`  → treefmt --fail-on-change {staged_files}
#
# Ownership (one formatter per file type):
#   *.nix                         nixfmt --verify
#   *.py                          ruff import sorting (priority 1), then ruff format (priority 2)
#   *.js *.jsx *.ts *.tsx *.mjs *.cjs *.json *.jsonc   biome
#   *.md *.yaml *.yml *.html *.css *.scss *.astro       prettier (+ astro plugin)
#   *.mdx                         not formatted (prettier rewraps <pre> content)
#   *.sh *.bash .forgejo/envrc    shfmt (extensionless shell scripts listed explicitly)
#   *.toml                        taplo
#   *.go                          gofumpt
#   *.lua                         stylua

{ pkgs, formatters }:

let
  inherit (pkgs) lib;
  exe = drv: lib.getExe drv;
in
{
  package = pkgs.treefmt.withConfig {
    name = "konductor-treefmt";
    settings = {
      tree-root-file = "flake.nix";
      on-unmatched = "info";
      excludes = [
        "_sources/*"
        "result"
        "result-*"
        ".direnv/*"
        "**/node_modules/*"
        "**/dist/*"
        "flake.lock"
        "**/pnpm-lock.yaml"
        "**/package-lock.json"
        "**/*.package-lock.json"
        "CHANGELOG.md"
        ".secrets.baseline"
      ];

      formatter = {
        nixfmt = {
          command = exe formatters.nixfmt.package;
          options = [ "--verify" ];
          includes = [ "*.nix" ];
        };

        # Same files, explicit order: import sorting must precede formatting.
        ruff-imports = {
          command = exe formatters.ruff.package;
          options = [
            "check"
            "--select"
            "I"
            "--fix"
          ];
          includes = [ "*.py" ];
          priority = 1;
        };
        ruff-format = {
          command = exe formatters.ruff.package;
          options = [ "format" ];
          includes = [ "*.py" ];
          priority = 2;
        };

        biome = {
          command = exe formatters.biome.package;
          options = [
            "format"
            "--write"
            "--no-errors-on-unmatched"
          ];
          includes = [
            "*.js"
            "*.jsx"
            "*.ts"
            "*.tsx"
            "*.mjs"
            "*.cjs"
            "*.json"
            "*.jsonc"
          ];
        };

        prettier = {
          command = exe formatters.prettier.package;
          options = [ "--write" ];
          # *.mdx is not formatted: prettier's MDX handling rewraps
          # <pre><code> blocks, which changes rendered Astro MDX output.
          includes = [
            "*.md"
            "*.yaml"
            "*.yml"
            "*.html"
            "*.css"
            "*.scss"
            "*.astro"
          ];
        };

        shfmt = {
          command = exe formatters.shfmt.package;
          options = [ "-w" ];
          includes = [
            "*.sh"
            "*.bash"
            ".forgejo/envrc"
          ];
        };

        taplo = {
          command = exe formatters.taplo.package;
          options = [ "format" ];
          includes = [ "*.toml" ];
        };

        gofumpt = {
          command = exe pkgs.gofumpt;
          options = [ "-w" ];
          includes = [ "*.go" ];
        };

        stylua = {
          command = exe pkgs.stylua;
          includes = [ "*.lua" ];
        };
      };
    };
  };

  meta = {
    description = "treefmt bound to the konductor formatter set";
    configurable = false;
  };
}
