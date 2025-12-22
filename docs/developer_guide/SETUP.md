---
cwd: ../..
shell: bash
skipPrompts: true
tag: target:setup,scope:dev,scope:ci
runme:
  version: v3
---

# Konductor Developer Setup

Verify prerequisites and configure your development environment.

## Contents

- [Output](#output)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Task Reference](#task-reference)
- [Check Tasks](#check-tasks)
- [Install Tasks](#install-tasks)
- [Debug Tools](#debug-tools)

---

## Output

| State | Exit | Description |
|-------|------|-------------|
| Ready | 0 | All prerequisites met, devshell loads correctly |
| Warning | 0 | Functional with optional components missing (KVM, etc.) |
| Failed | 1 | Critical prerequisite missing, cannot proceed |

After successful setup:

| Command | Description |
|---------|-------------|
| `nix develop .#full` | Enter devshell with all tools |
| `direnv allow` | Auto-load environment on cd |
| `ssh localhost` | Connect to build VM (after devshell) |
| `runme run build:qcow2:image` | Build VM image |

---

## Prerequisites

| Tool | Purpose | Check | Fix |
|------|---------|-------|-----|
| Nix/Lix | Package manager | `nix --version` | `setup:nix` |
| Flakes | Modern Nix CLI | `nix show-config` | `setup:flakes` |
| KVM | VM builds (Linux) | `/dev/kvm` writable | `setup:kvm` |
| Git user | Commits | `git config user.name` | `setup:git` |

---

## Quick Start

| Task | Description |
|------|-------------|
| `setup` | Show this help |
| `setup:verify` | Check all prerequisites (CI: exits 1 on failure) |
| `setup:nix` | Install Lix package manager |
| `setup:flakes` | Enable flakes in nix.conf |
| `setup:git` | Configure git user |
| `setup:kvm` | Configure KVM access (Linux) |
| `setup:registry` | Add konductor to flake registry |
| `setup:test` | Test devshell loads correctly |

### setup

Show available tasks.

```sh {"name":"setup","excludeFromRunAll":"true","tag":"type:entry"}
cat << 'EOF'
setup - Konductor Developer Setup

Usage: runme run setup:<task>

Tasks:
  :verify     Check all prerequisites (CI-friendly, exits 1 on failure)
  :nix        Install Lix package manager (interactive)
  :flakes     Enable flakes in ~/.config/nix/nix.conf
  :git        Configure git user name and email
  :kvm        Configure KVM access for VM builds (Linux)
  :registry   Add konductor to Nix flake registry
  :test       Test that devshell loads correctly

First Time:
  1. runme run setup:verify     # See what's missing
  2. runme run setup:nix        # Install Lix (if needed)
  3. nix develop .#full         # Enter devshell
  4. runme run setup:git        # Configure git (if needed)

CI Usage:
  runme run setup:verify        # Exits 1 if not ready
  runme run setup:test          # Exits 1 if devshell broken
EOF
```

`runme run setup`

---

### setup:verify

Check all prerequisites. Runs internal `_setup:check:*` tasks.

Pipeline: `nix → flakes → daemon → kvm → git → project → summary`

```sh {"name":"setup:verify","excludeFromRunAll":"true","tag":"type:entry,scope:ci"}
set -e
echo "=== Konductor Prerequisites ==="
echo ""
runme run --filename docs/developer_guide/SETUP.md --all 2>&1
```

`runme run setup:verify`

---

### setup:test

Test that Nix devshell loads correctly.

```sh {"name":"setup:test","excludeFromRunAll":"true","tag":"type:entry,scope:ci,requires:nix"}
set -e
echo "=== Devshell Test ==="
echo ""

FAILED=0

printf "%-12s" "default:"
if nix develop .#default --command true 2>/dev/null; then
    echo "OK"
else
    echo "FAILED"
    FAILED=1
fi

printf "%-12s" "full:"
if nix develop .#full --command true 2>/dev/null; then
    echo "OK"
else
    echo "FAILED"
    FAILED=1
fi

printf "%-12s" "konductor:"
if [ -w /dev/kvm ] 2>/dev/null; then
    if nix develop .#konductor --command true 2>/dev/null; then
        echo "OK"
    else
        echo "FAILED"
        FAILED=1
    fi
else
    echo "SKIP (no KVM)"
fi

echo ""
if [ $FAILED -gt 0 ]; then
    echo "Devshell test failed. Run: nix develop --show-trace"
    exit 1
fi
echo "All devshells OK"
```

`runme run setup:test`

---

## Task Reference

**Entry Points:**

| Task | Description |
|------|-------------|
| `setup` | Show help |
| `setup:verify` | Check all prerequisites (runs --all on check tasks) |
| `setup:test` | Test devshell loads |
| `setup:nix` | Install Lix (interactive) |
| `setup:flakes` | Enable flakes |
| `setup:git` | Configure git user (interactive) |
| `setup:kvm` | Configure KVM access (Linux) |
| `setup:registry` | Add flake to registry |

**Check Tasks** (internal, run via `setup:verify`):

| Task | Description |
|------|-------------|
| `_setup:check:nix` | Nix installed |
| `_setup:check:flakes` | Flakes enabled |
| `_setup:check:daemon` | Nix daemon running (Linux) |
| `_setup:check:kvm` | KVM accessible (Linux) |
| `_setup:check:git` | Git user configured |
| `_setup:check:project` | In project root |
| `_setup:summary` | Print result and exit code |

**Debug Tools:**

| Task | Description |
|------|-------------|
| `_setup:debug:config` | Show Nix configuration |
| `_setup:debug:env` | Show environment variables |

**Exit Codes:** `0` = Ready, `1` = Critical prerequisite missing

---

## Check Tasks

These run automatically via `setup:verify`. Each checks one thing.

### _setup:check:nix

```sh {"name":"_setup:check:nix","tag":"scope:ci"}
printf "%-16s" "Nix:"
if command -v nix >/dev/null 2>&1; then
    VERSION=$(nix --version 2>/dev/null | head -1 | sed 's/.*) //')
    echo "OK ($VERSION)"
else
    echo "MISSING"
    echo "  Fix: runme run setup:nix"
    echo ""
    export SETUP_ERRORS=$((${SETUP_ERRORS:-0} + 1))
fi
```

---

### _setup:check:flakes

```sh {"name":"_setup:check:flakes","tag":"scope:ci"}
printf "%-16s" "Flakes:"
if ! command -v nix >/dev/null 2>&1; then
    echo "SKIP (no nix)"
elif nix show-config 2>/dev/null | grep -q "experimental-features.*flakes"; then
    echo "OK"
else
    echo "MISSING"
    echo "  Fix: runme run setup:flakes"
    echo ""
    export SETUP_ERRORS=$((${SETUP_ERRORS:-0} + 1))
fi
```

---

### _setup:check:daemon

```sh {"name":"_setup:check:daemon","tag":"scope:ci"}
if [ "$(uname -s)" != "Linux" ]; then
    exit 0  # macOS doesn't need daemon check
fi

printf "%-16s" "Nix daemon:"
if systemctl is-active nix-daemon >/dev/null 2>&1; then
    echo "OK"
elif pgrep -x nix-daemon >/dev/null 2>&1; then
    echo "OK"
else
    echo "STOPPED"
    echo "  Fix: sudo systemctl start nix-daemon"
    echo ""
    export SETUP_ERRORS=$((${SETUP_ERRORS:-0} + 1))
fi
```

---

### _setup:check:kvm

```sh {"name":"_setup:check:kvm","tag":"scope:ci"}
if [ "$(uname -s)" != "Linux" ]; then
    exit 0  # KVM only on Linux
fi

printf "%-16s" "KVM:"
if [ -w /dev/kvm ]; then
    echo "OK"
elif [ -e /dev/kvm ]; then
    echo "NO ACCESS (optional)"
    echo "  Fix: runme run setup:kvm"
    echo ""
    export SETUP_WARNINGS=$((${SETUP_WARNINGS:-0} + 1))
else
    echo "UNAVAILABLE (optional)"
    echo "  Note: VM builds require KVM"
    echo ""
    export SETUP_WARNINGS=$((${SETUP_WARNINGS:-0} + 1))
fi
```

---

### _setup:check:git

```sh {"name":"_setup:check:git","tag":"scope:ci"}
printf "%-16s" "Git user:"
GIT_NAME=$(git config user.name 2>/dev/null || true)
GIT_EMAIL=$(git config user.email 2>/dev/null || true)
if [ -n "$GIT_NAME" ] && [ -n "$GIT_EMAIL" ]; then
    echo "OK ($GIT_NAME)"
else
    echo "NOT SET (optional)"
    echo "  Fix: runme run setup:git"
    echo ""
    export SETUP_WARNINGS=$((${SETUP_WARNINGS:-0} + 1))
fi
```

---

### _setup:check:project

```sh {"name":"_setup:check:project","tag":"scope:ci"}
printf "%-16s" "Project:"
if [ -f flake.nix ]; then
    echo "OK"
else
    echo "NOT FOUND"
    echo "  Fix: cd to konductor repo root"
    echo ""
    export SETUP_ERRORS=$((${SETUP_ERRORS:-0} + 1))
fi
```

---

### _setup:summary

Print summary and set exit code.

```sh {"name":"_setup:summary","tag":"scope:ci"}
ERRORS=${SETUP_ERRORS:-0}
WARNINGS=${SETUP_WARNINGS:-0}

echo ""
echo "─────────────────────────────────"
if [ $ERRORS -gt 0 ]; then
    echo "FAILED: $ERRORS error(s), $WARNINGS warning(s)"
    echo ""
    echo "Fix errors before proceeding."
    false  # exit 1
elif [ $WARNINGS -gt 0 ]; then
    echo "READY: $WARNINGS warning(s)"
    echo ""
    echo "Next: nix develop .#full"
else
    echo "READY: All checks passed"
    echo ""
    echo "Next: nix develop .#full"
fi
```

---

## Install Tasks

### setup:nix

Install Lix package manager. Interactive.

```sh {"name":"setup:nix","excludeFromRunAll":"true","tag":"type:entry","interactive":"true"}
set -e
echo "=== Install Lix ==="
echo ""

if command -v nix >/dev/null 2>&1; then
    echo "Already installed: $(nix --version)"
    exit 0
fi

echo "Lix is a Nix fork with better defaults and error messages."
echo ""
echo "This will:"
echo "  - Install Nix with flakes enabled"
echo "  - Configure multi-user daemon (Linux)"
echo "  - Add shell integration"
echo ""
read -p "Install Lix? [y/N] " RESPONSE
case "$RESPONSE" in
    [yY]|[yY][eE][sS])
        curl -sSf -L https://install.lix.systems/lix | sh -s -- install
        echo ""
        echo "Restart your shell, then run: runme run setup:verify"
        ;;
    *)
        echo "Cancelled."
        exit 1
        ;;
esac
```

`runme run setup:nix`

---

### setup:flakes

Enable flakes in Nix configuration.

```sh {"name":"setup:flakes","excludeFromRunAll":"true","tag":"type:entry"}
set -e
echo "=== Enable Flakes ==="
echo ""

if nix show-config 2>/dev/null | grep -q "experimental-features.*flakes"; then
    echo "Already enabled"
    exit 0
fi

NIX_CONF="$HOME/.config/nix/nix.conf"
mkdir -p "$(dirname "$NIX_CONF")"

if [ -f "$NIX_CONF" ] && grep -q "experimental-features" "$NIX_CONF"; then
    sed -i 's/experimental-features.*/experimental-features = nix-command flakes/' "$NIX_CONF"
else
    echo "experimental-features = nix-command flakes" >> "$NIX_CONF"
fi

echo "Enabled in: $NIX_CONF"
cat "$NIX_CONF"
```

`runme run setup:flakes`

---

### setup:git

Configure git user. Interactive.

```sh {"name":"setup:git","excludeFromRunAll":"true","tag":"type:entry","interactive":"true"}
set -e
echo "=== Git User ==="
echo ""

GIT_NAME=$(git config user.name 2>/dev/null || true)
GIT_EMAIL=$(git config user.email 2>/dev/null || true)

if [ -n "$GIT_NAME" ] && [ -n "$GIT_EMAIL" ]; then
    echo "Current: $GIT_NAME <$GIT_EMAIL>"
    read -p "Change? [y/N] " RESPONSE
    case "$RESPONSE" in
        [yY]|[yY][eE][sS]) ;;
        *) exit 0 ;;
    esac
    echo ""
fi

read -p "Name: " NAME
read -p "Email: " EMAIL

[ -z "$NAME" ] || [ -z "$EMAIL" ] && { echo "Both required"; exit 1; }

git config --global user.name "$NAME"
git config --global user.email "$EMAIL"
echo ""
echo "Set: $NAME <$EMAIL>"
```

`runme run setup:git`

---

### setup:kvm

Configure KVM access. Linux only.

```sh {"name":"setup:kvm","excludeFromRunAll":"true","tag":"type:entry"}
set -e
echo "=== KVM Access ==="
echo ""

[ "$(uname -s)" != "Linux" ] && { echo "Linux only"; exit 0; }

if [ ! -e /dev/kvm ]; then
    echo "/dev/kvm not found"
    echo ""
    echo "Requirements:"
    echo "  1. CPU: VT-x (Intel) or AMD-V"
    echo "  2. BIOS: Virtualization enabled"
    echo "  3. Module: sudo modprobe kvm_intel  # or kvm_amd"
    exit 1
fi

if [ -w /dev/kvm ]; then
    echo "Already accessible"
    exit 0
fi

echo "Adding $USER to kvm group..."
sudo usermod -aG kvm "$USER"
echo ""
echo "Apply with: newgrp kvm"
echo "Or log out and back in."
```

`runme run setup:kvm`

---

### setup:registry

Add konductor to Nix flake registry.

```sh {"name":"setup:registry","excludeFromRunAll":"true","tag":"type:entry"}
set -e
echo "=== Flake Registry ==="
echo ""

command -v nix >/dev/null 2>&1 || { echo "Nix required"; exit 1; }

if nix registry list 2>/dev/null | grep -q "flake:konductor"; then
    echo "Already registered"
    nix registry list | grep konductor
else
    nix registry add konductor github:braincraftio/konductor
    echo "Added: konductor -> github:braincraftio/konductor"
fi

echo ""
echo "Usage:"
echo "  nix develop konductor#full"
echo "  nix build konductor#qcow2"
```

`runme run setup:registry`

---

## Debug Tools

### _setup:debug:config

Show Nix configuration.

```sh {"name":"_setup:debug:config","excludeFromRunAll":"true","tag":"type:debug"}
echo "=== Nix Config ==="
echo ""
echo "User config:"
cat ~/.config/nix/nix.conf 2>/dev/null || echo "(none)"
echo ""
echo "Effective config:"
nix show-config 2>/dev/null | grep -E "^(experimental-features|substituters|trusted)" || echo "(nix not available)"
```

`runme run _setup:debug:config`

---

### _setup:debug:env

Show environment variables.

```sh {"name":"_setup:debug:env","excludeFromRunAll":"true","tag":"type:debug"}
echo "=== Environment ==="
echo ""
echo "PATH entries with nix:"
echo "$PATH" | tr ':' '\n' | grep -i nix || echo "(none)"
echo ""
echo "NIX_* variables:"
env | grep ^NIX_ || echo "(none)"
echo ""
echo "Shell: $SHELL"
echo "User: $USER ($(id -u))"
echo "Platform: $(uname -s) $(uname -m)"
```

`runme run _setup:debug:env`
