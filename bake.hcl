# docker-bake.hcl
# Multi-arch container build configuration for Konductor
#
# Build flow:
#   1. Build nix2container base images per-arch using Nix (amd64, arm64)
#      - mise run konductor (builds and tags as :nix2container)
#   2. Use docker buildx bake to build Dockerfile refinement for all arches
#   3. Buildx creates multi-arch manifest combining both
#
# Build strategies:
#   Local single-arch:  docker buildx bake konductor-local
#   Multi-arch:         docker buildx bake konductor
#   Production push:    docker buildx bake --push
#
# Prerequisites:
#   - nix2container base images must exist with tag :nix2container
#   - Build them with: mise run konductor (on each arch OR use cross-compilation)
#
# Reproducibility:
#   All builds use Nix flake.lock for pinned dependencies.
#   Same flake.lock = identical container contents (bit-for-bit).

# =============================================================================
# Variables
# =============================================================================

variable "REGISTRY" {
  default = "ghcr.io"
}

variable "REPO" {
  default = "braincraftio"
}

variable "IMAGE_NAME" {
  default = "konductor"
}

variable "TAG" {
  default = "latest"
}

variable "GITHUB_SHA" {
  default = ""
}

variable "GITHUB_REF_NAME" {
  default = ""
}

variable "GITHUB_RUN_NUMBER" {
  default = ""
}

# Cache configuration
variable "CACHE_REGISTRY" {
  default = "ghcr.io/braincraftio/konductor-cache"
}

# =============================================================================
# Functions
# =============================================================================

# Generate image tags based on build context
function "tags" {
  params = [name]
  result = compact([
    # Always tag with specified TAG (default: latest)
    "${REGISTRY}/${REPO}/${name}:${TAG}",
    # SHA tag for immutable reference
    GITHUB_SHA != "" ? "${REGISTRY}/${REPO}/${name}:sha-${substr(GITHUB_SHA, 0, 7)}" : "",
    # Branch tag for non-main branches
    GITHUB_REF_NAME != "" && GITHUB_REF_NAME != "main" ? "${REGISTRY}/${REPO}/${name}:${replace(GITHUB_REF_NAME, "/", "-")}" : "",
    # Build number for CI traceability
    GITHUB_RUN_NUMBER != "" ? "${REGISTRY}/${REPO}/${name}:build-${GITHUB_RUN_NUMBER}" : "",
  ])
}

# =============================================================================
# Groups
# =============================================================================

group "default" {
  targets = ["konductor"]
}

group "all" {
  targets = ["konductor", "konductor-amd64", "konductor-arm64"]
}

group "local" {
  targets = ["konductor-local"]
}

# =============================================================================
# Base Target (inherited by all builds)
# =============================================================================

target "_common" {
  context    = "."
  dockerfile = "Dockerfile"
  target     = "production"

  labels = {
    "org.opencontainers.image.title"       = "Konductor Development Environment"
    "org.opencontainers.image.description" = "Reproducible polyglot development container with Python, Go, Node.js, and Rust"
    "org.opencontainers.image.source"      = "https://github.com/braincraftio/flake"
    "org.opencontainers.image.licenses"    = "MIT"
    "org.opencontainers.image.vendor"      = "BrainCraft.io"
    "org.opencontainers.image.revision"    = GITHUB_SHA
  }
}

# =============================================================================
# Local Development Target (docker driver compatible)
# =============================================================================
# Used for: Fast local builds with default docker driver
# Builds: Native platform only, loads directly to Docker
# Cache: Inline only (docker driver limitation)
#
# Note: The docker driver does not support cache-to/cache-from with external
# backends. BuildKit's layer caching still works for unchanged Dockerfile steps.

target "konductor-local" {
  inherits = ["_common"]

  # Empty platforms = native platform
  platforms = []

  tags = [
    "${REGISTRY}/${REPO}/${IMAGE_NAME}:local",
    "${REGISTRY}/${REPO}/${IMAGE_NAME}:dev",
  ]

  # No cache-from/cache-to for docker driver compatibility
  # BuildKit internal layer caching still applies

  # Load directly into docker daemon
  output = ["type=docker"]
}

# =============================================================================
# Development Target (docker-container driver)
# =============================================================================
# Used for: Local development with full cache support
# Requires: docker buildx create --use --driver docker-container
# Builds: Native platform, with local filesystem cache

target "konductor-dev" {
  inherits = ["_common"]

  platforms = []

  tags = [
    "${REGISTRY}/${REPO}/${IMAGE_NAME}:dev",
  ]

  # Local cache - requires docker-container driver
  cache-from = [
    "type=local,src=/tmp/.buildx-cache",
  ]

  cache-to = [
    "type=local,dest=/tmp/.buildx-cache,mode=max",
  ]

  output = ["type=docker"]
}

# =============================================================================
# Production Multi-Arch Target
# =============================================================================
# Used for: CI/CD releases, registry pushes
# Builds: linux/amd64, linux/arm64

target "konductor" {
  inherits = ["_common"]

  platforms = [
    "linux/amd64",
    "linux/arm64",
  ]

  tags = tags(IMAGE_NAME)

  # Multi-tier cache strategy (requires docker-container driver or CI runner)
  cache-from = [
    # GitHub Actions cache (CI builds)
    "type=gha",
    # Registry cache (cross-machine sharing)
    "type=registry,ref=${CACHE_REGISTRY}:buildcache",
    # Architecture-specific caches for better hit rates
    "type=registry,ref=${CACHE_REGISTRY}:buildcache-amd64",
    "type=registry,ref=${CACHE_REGISTRY}:buildcache-arm64",
  ]

  cache-to = [
    # Export to GHA cache with max mode for all layers
    "type=gha,mode=max",
  ]
}

# =============================================================================
# Platform-Specific Targets
# =============================================================================
# Used for: Native runner builds, debugging platform issues

target "konductor-amd64" {
  inherits = ["_common"]

  platforms = ["linux/amd64"]

  tags = [
    "${REGISTRY}/${REPO}/${IMAGE_NAME}:${TAG}-amd64",
  ]

  cache-from = [
    "type=gha,scope=amd64",
    "type=registry,ref=${CACHE_REGISTRY}:buildcache-amd64",
  ]

  cache-to = [
    "type=gha,mode=max,scope=amd64",
  ]
}

target "konductor-arm64" {
  inherits = ["_common"]

  platforms = ["linux/arm64"]

  tags = [
    "${REGISTRY}/${REPO}/${IMAGE_NAME}:${TAG}-arm64",
  ]

  cache-from = [
    "type=gha,scope=arm64",
    "type=registry,ref=${CACHE_REGISTRY}:buildcache-arm64",
  ]

  cache-to = [
    "type=gha,mode=max,scope=arm64",
  ]
}

# =============================================================================
# CI/CD Targets
# =============================================================================
# Used for: GitHub Actions workflows with registry cache export

target "konductor-ci" {
  inherits = ["konductor"]

  # Export cache to registry for cross-workflow sharing
  cache-to = [
    "type=gha,mode=max",
    "type=registry,ref=${CACHE_REGISTRY}:buildcache,mode=max",
  ]
}

target "konductor-ci-amd64" {
  inherits = ["konductor-amd64"]

  cache-to = [
    "type=gha,mode=max,scope=amd64",
    "type=registry,ref=${CACHE_REGISTRY}:buildcache-amd64,mode=max",
  ]
}

target "konductor-ci-arm64" {
  inherits = ["konductor-arm64"]

  cache-to = [
    "type=gha,mode=max,scope=arm64",
    "type=registry,ref=${CACHE_REGISTRY}:buildcache-arm64,mode=max",
  ]
}
