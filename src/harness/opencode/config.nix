# src/harness/opencode/config.nix
# opencode.json content — hermetic MCP servers, permissions, formatters, LSP.
#
# Every external binary path uses lib.getExe for store-path hermeticity.
# Consumed by default.nix via pkgs.formats.json.

{
  pkgs,
  lib,
  formatters,
  linters,
  languages,
}:

{
  "$schema" = "https://opencode.ai/config.json";

  shell = lib.getExe pkgs.bash;
  update = "disable";
  snapshots = true;
  warming = false;
  compaction = {
    auto = true;
    keep.tokens = 15000;
    # Explicit percentage; unlike the implicit default, no 16k minimum reserve.
    buffer = "15%";
  };
  tool_output = {
    max_lines = 4000;
    max_bytes = 102400;
  };
  experimental = {
    todo = false;
    background_compaction = false;
    media_blob = false;
    image_generate = true;
    schedules = false;
    artifacts = false;
    subagent_depth = 1;
    location_idle_timeout = "60 minutes";
  };

  # =========================================================================
  # Native V2 slash commands
  # =========================================================================
  commands = {
    commit = {
      description = "Stage and commit changes using conventional commits ceremony";
      template = "Load the git-commit skill and execute all steps of the commit ceremony. NEVER truncate output: no | head, no | tail, no > file, no --stat alone, no --oneline. $ARGUMENTS";
    };
  };

  # =========================================================================
  # MCP servers — hermetic store-path commands
  # =========================================================================
  mcp = {
    timeout = {
      startup = 30000;
      catalog = 30000;
      execution = 43200000;
    };
    servers =
      lib.mapAttrs
        (
          _: server:
          lib.recursiveUpdate {
            disabled = false;
            codemode = true;
            # V2's default MCP handshake, not a V1 configuration compatibility key.
            protocol = "legacy";
          } server
        )
        {
          deepwiki = {
            type = "remote";
            url = "https://mcp.deepwiki.com/mcp";
          };
          nixos = {
            type = "local";
            command = [ (lib.getExe pkgs.mcp-nixos) ];
          };
          github = {
            type = "local";
            command = [
              (lib.getExe pkgs.github-mcp-server)
              "stdio"
            ];
            environment = {
              GITHUB_PERSONAL_ACCESS_TOKEN = "{env:GITHUB_PERSONAL_ACCESS_TOKEN}";
            };
          };
          gitea = {
            type = "local";
            command = [
              (lib.getExe pkgs.gitea-mcp-server)
              "-host"
              "{env:GITEA_URL}"
              "-token"
              "{env:GITEA_TOKEN}"
            ];
          };
          kubernetes = {
            type = "local";
            command = [ (lib.getExe pkgs.mcp-k8s-go) ];
          };
        };
  };

  # =========================================================================
  # Native V2 ordered rules: last matching rule wins.
  # =========================================================================
  permissions = [
    {
      action = "*";
      resource = "*";
      effect = "ask";
    }
  ]
  ++
    map
      (action: {
        inherit action;
        resource = "*";
        effect = "allow";
      })
      [
        "read"
        "glob"
        "grep"
        "skill"
      ]
  ++
    map
      (resource: {
        action = "read";
        inherit resource;
        effect = "deny";
      })
      [
        ".env"
        ".env.*"
        "**/.env"
        "**/.env.*"
        "secrets/**"
        "**/secrets/**"
        "**/vault.bin"
        "**/id_ed25519"
        "**/id_rsa"
      ]
  ++
    map
      (resource: {
        action = "shell";
        inherit resource;
        effect = "allow";
      })
      [
        "git status*"
        "git log*"
        "git diff*"
        "git show*"
        "git branch*"
        "git remote*"
        "tree*"
        "wc*"
        "find*"
        "gh run list*"
        "gh run view*"
      ]
  ++
    map
      (resource: {
        action = "shell";
        inherit resource;
        effect = "deny";
      })
      [
        "git push*"
        "git reset --hard*"
        "rm -rf*"
      ];

  # =========================================================================
  # Formatter overrides — hermetic store paths
  # =========================================================================
  # Disable upstream executable/npm discovery; enabled entries have store paths.
  formatter =
    lib.recursiveUpdate
      (lib.genAttrs
        [
          "gofmt"
          "mix"
          "oxfmt"
          "prettier"
          "biome"
          "zig"
          "clang-format"
          "ktlint"
          "ruff"
          "air"
          "uv"
          "rubocop"
          "standardrb"
          "htmlbeautifier"
          "dart"
          "ocamlformat"
          "terraform"
          "latexindent"
          "gleam"
          "rustfmt"
          "pint"
          "ormolu"
          "cljfmt"
          "dfmt"
        ]
        (_: {
          disabled = true;
        })
      )
      {
        biome = {
          disabled = false;
          extensions = [
            ".js"
            ".jsx"
            ".mjs"
            ".cjs"
            ".ts"
            ".tsx"
            ".mts"
            ".cts"
            ".json"
            ".jsonc"
          ];
          command = [
            (lib.getExe formatters.biome.package)
            "format"
            "--write"
            "$FILE"
          ];
        };
        prettier = {
          disabled = false;
          extensions = [
            ".md"
            ".mdx"
            ".yaml"
            ".yml"
            ".html"
            ".css"
            ".scss"
            ".astro"
            ".vue"
            ".svelte"
          ];
          command = [
            (lib.getExe formatters.prettier.package)
            "--write"
            "$FILE"
          ];
        };
        taplo = {
          disabled = false;
          extensions = [ ".toml" ];
          command = [
            (lib.getExe formatters.taplo.package)
            "format"
            "$FILE"
          ];
        };
        ruff = {
          disabled = false;
          extensions = [
            ".py"
            ".pyi"
          ];
          command = [
            (lib.getExe linters.ruff.package)
            "format"
            "$FILE"
          ];
        };
        gofmt = {
          disabled = false;
          extensions = [ ".go" ];
          command = [
            (lib.getExe' pkgs.konductor.go "gofmt")
            "-w"
            "$FILE"
          ];
        };
        rustfmt = {
          disabled = false;
          extensions = [ ".rs" ];
          command = [
            (lib.getExe' languages.rustToolchain "rustfmt")
            "--edition"
            "2024"
            "$FILE"
          ];
        };
        nixfmt = {
          disabled = false;
          extensions = [ ".nix" ];
          command = [
            (lib.getExe formatters.nixfmt.package)
            "$FILE"
          ];
        };
        shfmt = {
          disabled = false;
          extensions = [
            ".sh"
            ".bash"
          ];
          command = [
            (lib.getExe formatters.shfmt.package)
            "-w"
            "$FILE"
          ];
        };
      };

  # =========================================================================
  # LSP overrides — hermetic store paths
  # =========================================================================
  lsp = {
    nil = {
      disabled = false;
      extensions = [ ".nix" ];
      command = [ (lib.getExe pkgs.nil) ];
    };
  };
}
