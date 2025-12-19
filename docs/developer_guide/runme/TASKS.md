# Runme Task Architecture

Convention-based executable documentation for progressive scope automation.

## Contents

- [Quick Reference](#quick-reference)
- [Progressive Disclosure](#progressive-disclosure)
- [Naming Convention](#naming-convention)
- [Tag Taxonomy](#tag-taxonomy)
- [Document Structure](#document-structure)
- [Configuration](#configuration)
- [CLI Patterns](#cli-patterns)

---

## Quick Reference

```sh
# Shell alias (add to .bashrc)
alias rr='runme run'

# Execute
rr nix-build-qcow2              # Full qcow2 build
rr nix-build-qcow2-vm-start     # Single atomic task

# Glob (beta)
runme beta run "nix-build-*"    # All nix builds
runme beta run "*-vm-*"         # All VM tasks
```

---

## Progressive Disclosure

### The Pattern

Names narrow scope left-to-right. Each segment added restricts the operation:

```text
nix                    →  All nix operations
nix-build              →  All nix build operations
nix-build-qcow2        →  Build qcow2 image (ENTRY POINT)
nix-build-qcow2-vm     →  VM lifecycle within qcow2 build
nix-build-qcow2-vm-start  →  Start the VM (ATOMIC TASK)
```

### Execution Layers

| Layer | Scope | Example | Audience |
|-------|-------|---------|----------|
| 0 | Entry point | `rr nix-build-qcow2` | Operators |
| 1 | Subdomain | `runme beta run "nix-build-qcow2-vm-*"` | CI/CD |
| 2 | Atomic | `rr nix-build-qcow2-vm-start` | Developers |

### Glob Patterns

Progressive disclosure enables intuitive glob patterns:

```sh
# All nix operations
runme beta run "nix-*"

# All build operations across all tools
runme beta run "*-build-*"

# All VM lifecycle tasks across all builds
runme beta run "*-vm-*"

# All qcow2 tasks
runme beta run "*-qcow2*"
```

---

## Naming Convention

### Canonical Pattern

```text
{tool}-{action}-{target}[-{subtarget}][-{operation}]

tool:       Build system or tool (nix, docker, helm, kubectl)
action:     What the tool does (build, deploy, test, lint)
target:     What is being built/deployed (qcow2, container, chart)
subtarget:  Component within target (vm, image, cache)
operation:  Specific action (start, stop, clean, verify)
```

### Examples

```text
Entry Points (run everything):
  nix-build-qcow2           Build the qcow2 VM image
  nix-build-container       Build the container image
  docker-push-registry      Push all images to registry
  helm-deploy-cluster       Deploy to Kubernetes

Atomic Tasks (granular control):
  nix-build-qcow2-nix           Run nix build
  nix-build-qcow2-vm-start      Start the build VM
  nix-build-qcow2-vm-stop       Stop the build VM
  nix-build-qcow2-vm-ssh        SSH into the VM
  nix-build-qcow2-image-compress   Compress the image
  nix-build-qcow2-verify        Verify the output
```

### Character Rules

| Allowed | Forbidden | Rationale |
|---------|-----------|-----------|
| `a-z` | `A-Z` | Lowercase only, no case confusion |
| `0-9` | | Version suffixes allowed |
| `-` | `_` `:` `.` `/` | Hyphen only, no shift key needed |

### Domain Registry

| Tool | Actions | Targets |
|------|---------|---------|
| `nix` | `build`, `develop`, `check` | `qcow2`, `container`, `devshell` |
| `docker` | `build`, `push`, `pull` | `registry`, `image` |
| `helm` | `deploy`, `upgrade`, `rollback` | `cluster`, `chart` |
| `kubectl` | `apply`, `delete`, `get` | `namespace`, `deployment` |
| `pulumi` | `up`, `down`, `preview` | `stack`, `infra` |
| `test` | `unit`, `e2e`, `integration` | `api`, `ui`, `cli` |
| `lint` | `check`, `fix` | `nix`, `shell`, `python`, `yaml` |

---

## Tag Taxonomy

### Phase Tags (Ordered Execution)

```text
phase:build      →  phase:prepare  →  phase:configure  →  phase:package  →  phase:verify
```

Use for CI/CD pipeline stages:

```sh
runme run --all --tag=phase:build
runme run --all --tag=phase:verify
```

### Scope Tags

| Tag | Purpose |
|-----|---------|
| `scope:dev` | Development environment |
| `scope:ci` | CI/CD pipelines |
| `scope:prod` | Production operations |

### Type Tags

| Tag | Purpose |
|-----|---------|
| `type:entry` | Entry point task (runs sub-tasks) |
| `type:destructive` | Deletes data, requires confirmation |
| `type:readonly` | Safe, no mutations |
| `type:debug` | Troubleshooting utilities |
| `type:meta` | Documentation/help tasks |

### Requirement Tags

| Tag | Purpose |
|-----|---------|
| `requires:nix` | Needs nix installed |
| `requires:docker` | Needs docker daemon |
| `requires:kvm` | Needs KVM acceleration |
| `requires:guestfs` | Needs libguestfs tools |

### Duration Tags

| Tag | Purpose |
|-----|---------|
| `duration:fast` | < 10 seconds |
| `duration:slow` | > 1 minute |
| `duration:background` | Long-running service |

---

## Document Structure

### Frontmatter

```yaml
---
cwd: ../../..
shell: bash
skipPrompts: true
tag: target:qcow2,scope:dev,scope:ci
runme:
  version: v3
---
```

Document-level tags apply to ALL blocks in the file.

### Entry Point Pattern

Every executable document has ONE entry point that runs the full workflow:

````markdown
## Quick Start

```sh {"name":"nix-build-qcow2","excludeFromRunAll":"true","tag":"type:entry"}
runme run --filename docs/developer_guide/qcow2/BUILD.md --all
```

`rr nix-build-qcow2`
````

The entry point:

1. Is `excludeFromRunAll` (prevents recursion)
2. Tagged `type:entry`
3. Calls `runme run --filename <this-file> --all`
4. Documents the simple invocation

### Atomic Task Pattern

Individual tasks follow naming convention with phase tags:

````markdown
```sh {"name":"nix-build-qcow2-vm-start","tag":"phase:configure,requires:kvm"}
qemu-system-x86_64 \
    -machine q35,accel=kvm \
    ...
```
````

### Pipeline Diagram

Include a visual pipeline in the entry point section:

````markdown
```text
rr nix-build-qcow2

phase:build  →  phase:prepare  →  phase:configure  →  phase:package  →  phase:verify
    │                │                │                    │                │
    ▼                ▼                ▼                    ▼                ▼
  -nix           -ssh-keygen      -vm-start           -image-clean      -verify
                 -cloudinit-gen   -vm-wait            -image-compress
                 -image-reset     -copy-source        -image-sparsify
                                  -cache-warm
                                  -vm-stop

All tasks prefixed: nix-build-qcow2-{task}
```
````

---

## Configuration

### Project Configuration

```yaml
# runme.yaml
version: v1alpha1

project:
  root: .
  find_repo_upward: true
  filename: README.md
  ignore:
    - node_modules
    - .venv
    - .direnv
    - vendor
    - result
    - "*.qcow2"
    - .git
    - .claude
  disable_gitignore: false
  env:
    sources:
      - .env.local
      - .env

filters:
  - type: block
    condition: "isNamed == true"

log:
  enabled: false
  path: /tmp/runme.log
```

### Filter Expressions

Filter blocks by properties:

```yaml
# Only CI-safe tasks
filters:
  - type: block
    condition: "len(intersection(tags, extra.allowed)) > 0"
    extra:
      allowed: ["scope:ci"]

# Exclude destructive operations
filters:
  - type: block
    condition: "len(intersection(tags, extra.excluded)) == 0"
    extra:
      excluded: ["type:destructive"]
```

Available block properties:

| Property | Type | Description |
|----------|------|-------------|
| `name` | string | Task name |
| `tags` | []string | Task tags |
| `language` | string | Code block language |
| `isNamed` | bool | Has explicit name |
| `background` | bool | Background execution |
| `interactive` | bool | Interactive mode |
| `excludeFromRunAll` | bool | Excluded from --all |

---

## CLI Patterns

### Operators (Layer 0)

One command, full workflow:

```sh
rr nix-build-qcow2
```

### CI/CD (Layer 1)

Phase-based execution:

```sh
# Run specific phase
runme run --filename <file> --all --tag=phase:build

# Run glob pattern
runme beta run "nix-build-qcow2-image-*"
```

### Developers (Layer 2)

Atomic task execution:

```sh
# Single task
rr nix-build-qcow2-vm-start

# SSH into running VM
rr nix-build-qcow2-vm-ssh

# Kill stuck VM
rr nix-build-qcow2-vm-kill
```

### Discovery

```sh
# List all tasks in project
runme list

# List tasks in specific file
runme list --filename docs/developer_guide/qcow2/BUILD.md

# Interactive TUI
runme tui
```

---

## File Organization

```text
project-root/
├── runme.yaml                      # Project configuration
├── .env                            # Shared environment
├── README.md                       # Project overview tasks
│
└── docs/
    └── developer_guide/
        ├── qcow2/
        │   └── BUILD.md            # nix-build-qcow2-* tasks
        ├── container/
        │   └── BUILD.md            # nix-build-container-* tasks
        ├── deploy/
        │   └── DEPLOY.md           # helm-deploy-* tasks
        └── runme/
            └── TASKS.md            # This reference
```

Each domain gets its own markdown file with:

- One entry point (`{tool}-{action}-{target}`)
- Atomic tasks (`{tool}-{action}-{target}-{subtarget}-{operation}`)
- Phase tags for ordered execution
- Pipeline diagram for visual reference

---

## Appendix: Shell Configuration

Add to `.bashrc`:

```sh
# Task automation aliases
alias mr='mise run'      # mise tasks
alias rr='runme run'     # runme tasks

# Runme completions (if available)
if command -v runme >/dev/null 2>&1; then
  source <(runme completion bash)
fi
```
