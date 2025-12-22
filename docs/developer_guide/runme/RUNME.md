---
# This file is REFERENCE DOCUMENTATION about runme, not executable tasks.
# All code blocks are examples showing runme syntax, not meant for execution.
skipPrompts: true
shell: bash
runme:
  version: v3
---

# Runme: Executable Markdown Documentation

Runme transforms Markdown files into interactive, executable documents. Instead of copy-pasting commands from documentation, developers can run code blocks directly from their editor or CLI.

## Installation

```sh {"name":"_example:install-runme","excludeFromRunAll":"true"}
# macOS
brew install runme

# Linux (via script)
curl -sSL https://runme.dev/install.sh | sh

# npm
npm install -g runme

# Go
go install github.com/stateful/runme/v3@latest
```

## Quick Start

```sh {"name":"_example:runme-help","excludeFromRunAll":"true","interactive":"false"}
runme --help
```

### Run a Named Block

```sh {"name":"_example:runme-run","excludeFromRunAll":"true"}
# Run a specific named code block
runme run block-name

# Run from a specific file
runme run --filename docs/BUILD.md block-name
```

### Run All Blocks

```sh {"name":"_example:runme-all","excludeFromRunAll":"true"}
# Run all executable blocks in sequence
runme run --all

# Run all blocks with a specific tag
runme run --all --tag=setup
```

## Code Block Syntax

Runme uses fenced code blocks with attributes in curly braces. Two syntax formats are supported:

### JSON Format

````markdown
```sh {"name":"my-command","interactive":"false","background":"false"}
echo "Hello, Runme!"
```
````

### HTML-like Format

````markdown
```sh { name=my-command interactive=false background=false }
echo "Hello, Runme!"
```
````

## Code Block Attributes

| Attribute | Type | Default | Description |
|-----------|------|---------|-------------|
| `name` | string | auto | Unique identifier for the block |
| `interactive` | bool | `true` | Show output in real-time terminal |
| `background` | bool | `false` | Run command in background |
| `cwd` | string | doc dir | Working directory for execution |
| `excludeFromRunAll` | bool | `false` | Skip when running `--all` |
| `promptEnv` | bool | `true` | Prompt for environment variables |
| `interpreter` | string | auto | Custom interpreter (e.g., `dagger shell`) |
| `tag` | string | none | Categorize blocks (e.g., `setup,build`) |
| `terminalRows` | int | auto | Terminal row allocation |
| `skipPrompts` | bool | `false` | Skip all prompts for this block |

### Attribute Examples

#### Named Block

````markdown
```sh {"name":"build-project"}
nix build .#default
```
````

Run with: `runme run build-project`

#### Non-Interactive (Captured Output)

````markdown
```sh {"name":"check-version","interactive":"false"}
nix --version
```
````

Output is captured and displayed after completion. Useful for commands that produce structured output.

#### Background Process

````markdown
```sh {"name":"start-server","background":"true"}
python -m http.server 8080
```
````

Command runs in background. Use for long-running services.

#### Custom Working Directory

````markdown
```sh {"name":"test-subdir","cwd":"./tests"}
pytest .
```
````

#### Exclude from Run All

````markdown
```sh {"name":"dangerous-cleanup","excludeFromRunAll":"true"}
rm -rf ./build/*
```
````

Block won't run with `runme run --all`. Must be explicitly invoked.

#### Tagged Blocks

````markdown
```sh {"name":"install-deps","tag":"setup,deps"}
npm install
```

```sh {"name":"build","tag":"build"}
npm run build
```

```sh {"name":"test","tag":"test"}
npm test
```
````

Run by tag: `runme run --all --tag=setup`

#### Custom Interpreter

````markdown
```sh {"name":"dagger-build","interpreter":"dagger shell"}
container | from "alpine" | withExec ["echo", "hello"]
```
````

## Document Frontmatter

Frontmatter provides document-level configuration. Runme supports YAML, JSON, and TOML formats, auto-detecting based on delimiters.

### Frontmatter Schema

| Field | Type | Description |
|-------|------|-------------|
| `cwd` | string | Default working directory for all blocks |
| `shell` | string | Default shell interpreter |
| `skipPrompts` | bool | Skip all prompts document-wide |
| `terminalRows` | string | Default terminal row allocation |
| `tag` | string | Document-level tags (comma-separated) |
| `category` | string | **Deprecated** - use `tag` instead |
| `runme` | object | Runme-specific metadata (nested) |

#### Nested `runme` Object

| Field | Type | Description |
|-------|------|-------------|
| `runme.id` | string | Unique document identifier (ULID, auto-generated) |
| `runme.version` | string | Runme version (e.g., `v3`) |
| `runme.session.id` | string | Session identifier |
| `runme.session.updated` | string | Last session update timestamp |
| `runme.document.relativePath` | string | Relative path of the document |

### YAML Format (Recommended)

Delimited by `---`:

```yaml
---
cwd: ../..
shell: bash
skipPrompts: false
terminalRows: "24"
tag: build,deploy
runme:
  id: 01HFVTDYA775K2HREH9ZGQJ75B
  version: v3
  session:
    id: 01HJS35FZ2K0JBWPVAXPMMVTGN
    updated: "2024-01-15 10:30:00-05:00"
  document:
    relativePath: docs/BUILD.md
---
```

### JSON Format

Delimited by `---` with JSON content:

```json
---
{
  "cwd": "../..",
  "shell": "bash",
  "skipPrompts": false,
  "terminalRows": "24",
  "tag": "build,deploy",
  "runme": {
    "id": "01HF7AX2R37KPNPH1MQ2KEEYGM",
    "version": "v3",
    "session": {
      "id": "01HJS35FZ2K0JBWPVAXPMMVTGN",
      "updated": "2024-01-15 10:30:00-05:00"
    },
    "document": {
      "relativePath": "docs/BUILD.md"
    }
  }
}
---
```

### TOML Format

Delimited by `+++`:

```toml
+++
cwd = "../.."
shell = "bash"
skipPrompts = false
terminalRows = "24"
tag = "build,deploy"

[runme]
id = "01JN4EXJWJH3CDJNQNSBFQAKEQ"
version = "v3"

[runme.session]
id = "01HJS35FZ2K0JBWPVAXPMMVTGN"
updated = "2024-01-15 10:30:00-05:00"

[runme.document]
relativePath = "docs/BUILD.md"
+++
```

### Frontmatter Behavior

**Parsing**: Runme auto-detects format by delimiters and attempts YAML → JSON → TOML parsing.

**Serialization**: When saving, Runme preserves the original format and updates metadata:
- `runme.id` is auto-generated as a ULID if missing
- `runme.session.updated` is refreshed on save
- `runme.version` is set to current Runme version

**Identity Resolution**: The `runme.id` ensures document tracking across renames and moves. Generated using ULID (Universally Unique Lexicographically Sortable Identifier).

### Minimal Frontmatter

For most use cases, minimal frontmatter is sufficient:

```yaml
---
cwd: .
shell: bash
---
```

Runme auto-populates `runme.id` and `runme.version` on first save.

## Supported Languages

Runme auto-detects interpreters based on language identifiers:

| Language ID | Interpreter | Execution Mode |
|-------------|-------------|----------------|
| `sh`, `bash`, `shell` | `bash` | Inline shell |
| `zsh` | `zsh` | Inline shell |
| `fish` | `fish` | Inline shell |
| `powershell`, `pwsh` | `powershell` | Inline shell |
| `python`, `py` | `python3` | Temp file |
| `javascript`, `js` | `node` | Temp file |
| `typescript`, `ts` | `ts-node` / `deno` / `bun` | Temp file |
| `ruby`, `rb` | `ruby` | Temp file |
| `go` | `go run` | Temp file |
| `rust`, `rs` | `rust-script` | Temp file |
| `lua` | `lua` | Temp file |
| `perl` | `perl` | Temp file |
| `php` | `php` | Temp file |

### Shell vs Temp File Execution

**Inline Shell** (`sh`, `bash`, `zsh`): Commands passed via `-c` flag:
```sh
bash -c 'echo "inline execution"'
```

**Temp File** (`python`, `node`, etc.): Script written to temp file:
```sh
python3 /tmp/runme-abc123.py
```

## Project Configuration

### runme.yaml

The `runme.yaml` file configures project-level settings, primarily used by beta commands:

```yaml
# runme.yaml
project:
  root: .
  find_repo_upward: true
  env:
    sources:
      - .env.local
      - .env

filters:
  - tag: setup
  - tag: build
```

### Project Discovery

Runme automatically discovers project roots:

1. **Explicit**: Use `--project /path/to/project`
2. **Git-based**: Searches upward for `.git` directory (default)
3. **Current directory**: Falls back to `.` if no Git repo found

```sh
# Specify project root explicitly
runme run --project /path/to/project block-name

# Use current directory
runme run --chdir ./subdir block-name
```

### File Ignore Patterns

Runme respects ignore patterns when discovering files:

```sh
# Default ignore patterns
--ignore-pattern node_modules
--ignore-pattern .venv

# Respect .gitignore (default: true)
--git-ignore=true
```

## Environment Variables

### Environment Loading Order

Runme loads environment variables from multiple sources in this order (later sources override earlier):

1. **System environment** - Inherited from parent shell
2. **Project `.env` files** - In order specified by `--env-order`
3. **direnv** - Variables from `.envrc` via `direnv export`
4. **Explicit variables** - Passed via CLI or frontmatter
5. **Session variables** - Exported during command execution

### .env File Loading

Runme automatically loads `.env` files from the project root.

**Default behavior** (enabled by default):
```sh
# Controlled by --load-env flag (default: true)
runme run --load-env block-name
```

**Load order** (controlled by `--env-order`):
```sh
# Default order: .env.local, then .env
runme run --env-order=".env.local,.env" block-name

# Custom order
runme run --env-order=".env.production,.env" block-name
```

**Example `.env` file**:
```sh
# .env
OUTPUT_DIR=/tmp/build
SSH_KEY_DIR=/tmp/ssh
MOUNT_PATH=/tmp/mount
LOG_LEVEL=info
```

### direnv Integration

Runme integrates with direnv to load `.envrc` files automatically.

**Default behavior** (enabled by default):
```sh
# Controlled by --direnv flag (default: true)
runme run --direnv block-name

# Disable direnv
runme run --direnv=false block-name
```

**How it works**: Runme executes `eval $(direnv export $SHELL)` in the project root before running commands.

**Example `.envrc`**:
```sh
# .envrc
use flake
export PROJECT_ROOT=$(pwd)
export BUILD_DATE=$(date +%Y%m%d)
```

### Environment Specification Files

Runme supports environment specification files for validation and documentation:

| File | Purpose |
|------|---------|
| `.env.example` | Template showing required variables |
| `.env.sample` | Alternative template name |
| `.env.spec` | Formal specification with validation |
| `.runme/owl.yaml` | Advanced env management with Owl Store |

**Example `.env.example`**:
```sh
# .env.example - Copy to .env and fill in values
DATABASE_URL=postgres://user:pass@host/db
API_KEY=your-api-key-here
```

### Owl Store (Advanced)

The Owl Store provides advanced environment variable management:

- **Validation rules** for variable values
- **Secret management** integration
- **Type-safe resolution** inspired by TypeScript
- **Graph-based dependency resolution**

**Configuration** (`.runme/owl.yaml`):
```yaml
# .runme/owl.yaml
variables:
  DATABASE_URL:
    required: true
    pattern: "^postgres://"
  API_KEY:
    required: true
    secret: true
```

Owl Store is enabled when a project is configured and owl.yaml exists.

### Session Persistence

Environment variables can persist across code blocks within a session.

**Important**: Session behavior differs between CLI modes:

| Mode | Session Persistence | Use Case |
|------|---------------------|----------|
| `runme run` | No (LocalRunner) | Simple, isolated execution |
| `runme run --server` | Yes (RemoteRunner) | Connected to gRPC server |
| `runme beta run` | Yes (Runner V2) | Automatic session management |
| VS Code Extension | Yes | Interactive notebook experience |

**With `runme beta run`** (recommended for multi-block workflows):

````markdown
```sh {"name":"set-env"}
export PROJECT_NAME="konductor"
export BUILD_DATE=$(date +%Y%m%d)
```

```sh {"name":"use-env"}
echo "Building $PROJECT_NAME on $BUILD_DATE"
```
````

```sh
# Variables persist between blocks
runme beta run set-env use-env
```

**With `runme run --all`** (no persistence - use .env files instead):

```sh
# Create .env with shared variables
echo 'PROJECT_NAME=konductor' > .env
echo "BUILD_DATE=$(date +%Y%m%d)" >> .env

# Variables loaded from .env for each block
runme run --all
```

### Environment Prompts

When `promptEnv` is enabled (default), Runme prompts for undefined variables:

````markdown
```sh {"name":"deploy","promptEnv":"true"}
kubectl apply -f deploy/ --namespace=$NAMESPACE
```
````

Runme will prompt: `Enter value for NAMESPACE:`

Disable prompts for non-interactive execution:

````markdown
```sh {"name":"ci-deploy","promptEnv":"no"}
kubectl apply -f deploy/ --namespace=${NAMESPACE:-default}
```
````

### Best Practice: Self-Contained Blocks

For `runme run --all` without session persistence, make blocks self-contained:

````markdown
```sh {"name":"build"}
# Load from .env or define inline
: ${OUTPUT_DIR:=/tmp/build}
: ${BUILD_DATE:=$(date +%Y%m%d)}

echo "Building to $OUTPUT_DIR on $BUILD_DATE"
mkdir -p "$OUTPUT_DIR"
```
````

Or use a shared `.env` file that all blocks can load.

## CLI Commands

### Standard vs Beta Commands

Runme has two command modes with different capabilities:

| Feature | `runme run` | `runme beta run` |
|---------|-------------|------------------|
| Runner | V1 (LocalRunner) | V2 (SessionRunner) |
| Session persistence | No | Yes |
| direnv integration | Yes | No |
| Glob patterns | No | Yes |
| Configuration | CLI flags | runme.yaml |

**Use `runme run`** when:
- You need direnv/nix shell integration
- Blocks are self-contained or use .env files
- Running individual blocks

**Use `runme beta run`** when:
- You need environment variables to persist between blocks
- Running complex multi-block workflows
- Using glob patterns to select blocks

### Run Commands

```sh {"name":"_example:cli-run","excludeFromRunAll":"true","interactive":"false"}
# Run specific block
runme run block-name

# Run from specific file
runme run --filename=docs/BUILD.md block-name

# Run all blocks
runme run --all

# Run all with tag filter
runme run --all --tag=setup

# Run in parallel
runme run --all --parallel

# Dry run (show what would execute)
runme run --dry-run block-name

# Skip environment prompts
runme run --skip-prompts block-name

# Custom env file order
runme run --env-order=".env.prod,.env" block-name
```

### Beta Run Commands

```sh {"name":"_example:cli-beta-run","excludeFromRunAll":"true","interactive":"false"}
# Run blocks with glob pattern (session persistence)
runme beta run "setup-*"

# Run multiple blocks in sequence
runme beta run block1 block2 block3

# Run all blocks matching pattern
runme beta run "*"

# Filter by tag
runme beta run --tag=build

# From specific file
runme beta run --filename=docs/BUILD.md "build-*"
```

### Beta Session

```sh {"name":"_example:cli-beta-session","excludeFromRunAll":"true"}
# Start interactive session shell
# All exports persist until exit
runme beta session
```

### List Commands

```sh {"name":"_example:cli-list","excludeFromRunAll":"true","interactive":"false"}
# List all runnable blocks
runme list

# List from specific file
runme list --filename=docs/BUILD.md

# JSON output
runme list --json
```

### TUI Mode

```sh {"name":"_example:cli-tui","excludeFromRunAll":"true"}
# Interactive terminal UI
runme tui

# TUI for specific file
runme tui --filename=docs/BUILD.md
```

### Environment Commands

```sh {"name":"_example:cli-env","excludeFromRunAll":"true","interactive":"false"}
# Show environment from session
runme env

# Source environment (for shell integration)
eval $(runme env --export)
```

## VS Code Integration

Runme provides a VS Code extension for in-editor execution:

1. Install "Runme" extension from marketplace
2. Open any `.md` file
3. Click "Run" button on code blocks
4. View output in integrated terminal

### Notebook Mode

VS Code renders Markdown as interactive notebooks:
- Each code block becomes an executable cell
- Output displays below each cell
- Environment persists across cells

## Best Practices

### 1. Name All Important Blocks

```markdown
# Good - named and discoverable
```sh {"name":"build-image"}
docker build -t myapp .
```

# Avoid - anonymous blocks are hard to reference
```sh
docker build -t myapp .
```
```

### 2. Use Tags for Workflows

````markdown
```sh {"name":"_example:install","tag":"setup"}
npm install
```

```sh {"name":"_example:build","tag":"build"}
npm run build
```

```sh {"name":"_example:test","tag":"test,ci"}
npm test
```

```sh {"name":"_example:deploy","tag":"deploy"}
kubectl apply -f k8s/
```
````

Workflows: `runme run --all --tag=setup,build,test`

### 3. Exclude Dangerous Commands

````markdown
```sh {"name":"cleanup-all","excludeFromRunAll":"true"}
# Destructive - require explicit invocation
rm -rf ./node_modules ./dist ./.cache
```
````

### 4. Use Non-Interactive for CI

````markdown
```sh {"name":"ci-test","interactive":"false","promptEnv":"no"}
npm test -- --ci --coverage
```
````

### 5. Document Prerequisites

````markdown
## Prerequisites

```sh {"name":"check-prereqs","interactive":"false"}
command -v docker >/dev/null && echo "docker: OK" || echo "docker: MISSING"
command -v nix >/dev/null && echo "nix: OK" || echo "nix: MISSING"
command -v kubectl >/dev/null && echo "kubectl: OK" || echo "kubectl: MISSING"
```
````

### 6. Group Related Steps

````markdown
## Database Setup

```sh {"name":"db-start","tag":"db"}
docker-compose up -d postgres
```

```sh {"name":"db-migrate","tag":"db"}
npm run db:migrate
```

```sh {"name":"db-seed","tag":"db"}
npm run db:seed
```

Run all: `runme run --all --tag=db`
````

## Comparison with Alternatives

| Feature | Runme | Makefile | Just | Task |
|---------|-------|----------|------|------|
| Markdown native | Yes | No | No | No |
| Documentation | Built-in | Separate | Separate | Separate |
| VS Code integration | Native | Limited | Limited | Limited |
| Language support | Multi | Shell | Shell | Shell |
| Session persistence | Yes | No | No | No |
| Interactive prompts | Yes | No | No | No |

## Resources

- [Runme Documentation](https://docs.runme.dev/)
- [GitHub Repository](https://github.com/stateful/runme)
- [VS Code Extension](https://marketplace.visualstudio.com/items?itemName=stateful.runme)
- [Examples](https://github.com/stateful/runme/tree/main/examples)
