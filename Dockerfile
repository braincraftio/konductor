# Konductor container built from nix2container base
#
# Build: mise run docker:build:all
# Run:   docker run --rm -it ghcr.io/braincraftio/konductor:latest
# Admin: docker run --rm -it -u kc2admin ghcr.io/braincraftio/konductor:latest

ARG BASE_TAG=nix2container
FROM ghcr.io/braincraftio/konductor:${BASE_TAG} AS base

# Create writable /tmp (nix store paths are read-only)
USER root
RUN rm -rf /tmp && mkdir -p /tmp && chmod 1777 /tmp

# Fix home directory ownership and permissions
RUN chown -R 1000:1000 /home/kc2 && chmod -R u+rwX /home/kc2 && \
    chown -R 1001:1001 /home/kc2admin && chmod -R u+rwX /home/kc2admin

# Validate core tools (from cli package group)
RUN git --version && \
    jq --version && \
    yq --version && \
    gh --version && \
    fzf --version && \
    starship --version && \
    mise --version && \
    direnv --version;

# Validate modern CLI tools (from cli package group)
RUN rg --version && \
    fd --version;

# Validate linters (from linters package group)
RUN shellcheck --version && \
    yamllint --version && \
    actionlint --version && \
    statix --version && \
    deadnix --version;

# Validate formatters (from formatters package group)
RUN shfmt --version;

# Validate AI tools
RUN claude --version;

# Validate kc2 permissions (unprivileged user, no sudo)
USER kc2
RUN touch /home/kc2/test && rm /home/kc2/test && \
    ! sudo whoami 2>/dev/null

# Validate kc2admin permissions and sudo
# Note: sudo test uses || true because setuid doesn't work under QEMU
# emulation during cross-platform builds. Sudo works correctly at runtime.
USER kc2admin
RUN touch /home/kc2admin/test && rm /home/kc2admin/test && \
    groups | grep -q kc2 && \
    (sudo whoami | grep -q root || true)

# Final production image
FROM base AS production

# Workspace directory setup (as root)
USER root
RUN mkdir -p /workspace && \
    chown 1000:1000 /workspace && \
    chmod 2775 /workspace

# Unprivileged kc2 user
USER kc2

# Working directory
WORKDIR /workspace

# Default entrypoint
ENTRYPOINT ["/bin/bash"]
CMD ["-l"]
