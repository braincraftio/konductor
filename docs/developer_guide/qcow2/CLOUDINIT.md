# Cloud-Init Configuration for NixOS QCOW2 Images

## About

This document describes cloud-init integration patterns for Konductor NixOS QCOW2 virtual machine images. It covers userdata and networkdata configuration, DNS routing, proxy settings, and NixOS-specific considerations for deploy-time configuration injection.

Cloud-init provides the mechanism for configuring virtual machines at first boot without baking environment-specific settings into the image. This enables a single QCOW2 image to deploy across diverse environments with different networking, DNS, and proxy requirements.

---

## Table of Contents

- [Architecture Overview](#architecture-overview)
- [Cloud-Init Execution Model](#cloud-init-execution-model)
- [Userdata Configuration](#userdata-configuration)
- [Networkdata Configuration](#networkdata-configuration)
- [DNS Configuration](#dns-configuration)
- [Proxy Configuration](#proxy-configuration)
- [Static Host Entries](#static-host-entries)
- [NixOS-Specific Considerations](#nixos-specific-considerations)
- [Troubleshooting](#troubleshooting)
- [Reference](#reference)

---

## Architecture Overview

The Konductor QCOW2 image uses cloud-init with the NoCloud datasource, receiving configuration via two separate data streams:

```
┌─────────────────────────────────────────────────────────────────────────┐
│                         Cloud-Init Data Flow                            │
├─────────────────────────────────────────────────────────────────────────┤
│                                                                         │
│  ┌──────────────┐     ┌──────────────┐     ┌──────────────────────────┐│
│  │   Userdata   │     │  Networkdata │     │      Metadata            ││
│  │  (YAML)      │     │  (YAML v2)   │     │  (instance-id, etc.)     ││
│  └──────┬───────┘     └──────┬───────┘     └──────────────────────────┘│
│         │                    │                                          │
│         ▼                    ▼                                          │
│  ┌─────────────────────────────────────────────────────────────────────┐│
│  │                     cloud-init Stages                               ││
│  │  ┌─────────┐  ┌─────────┐  ┌─────────┐  ┌─────────┐                ││
│  │  │ Local   │→ │  Init   │→ │ Config  │→ │  Final  │                ││
│  │  │(network)│  │(modules)│  │(runcmd) │  │(scripts)│                ││
│  │  └─────────┘  └─────────┘  └─────────┘  └─────────┘                ││
│  └─────────────────────────────────────────────────────────────────────┘│
│         │                    │                                          │
│         ▼                    ▼                                          │
│  ┌──────────────┐     ┌──────────────┐                                 │
│  │ systemd-     │     │ systemd-     │                                 │
│  │ networkd     │     │ resolved     │                                 │
│  │ (.network)   │     │ (DNS)        │                                 │
│  └──────────────┘     └──────────────┘                                 │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘
```

### Component Responsibilities

| Component | Role |
|-----------|------|
| **Userdata** | User accounts, SSH keys, file creation, shell commands |
| **Networkdata** | Interface configuration, IP addressing, basic DNS |
| **systemd-networkd** | Network interface management, .network file processing |
| **systemd-resolved** | DNS resolution, per-link DNS routing, caching |

---

## Cloud-Init Execution Model

Cloud-init executes in four distinct stages during boot. Understanding this sequence is essential for correct configuration ordering.

### Execution Stages

```
Boot Timeline
─────────────────────────────────────────────────────────────────────────►

  │ init-local │    init    │   config   │   final   │
  │            │            │            │           │
  │ Network    │ write_files│  runcmd    │  scripts  │
  │ rendered   │ users      │            │           │
  │            │ ssh        │            │           │
  │            │            │            │           │
  ▼            ▼            ▼            ▼           ▼
  Network UP   Modules      Commands     Late tasks
```

| Stage | Timing | Key Operations |
|-------|--------|----------------|
| **init-local** | Before network | Networkdata processing, interface configuration |
| **init** | Network available | `write_files`, user creation, SSH key injection |
| **config** | After init | `runcmd` execution |
| **final** | Late boot | Deferred scripts, package installation |

### Implications for Configuration Order

1. Networkdata is processed **before** userdata modules execute
2. Files written via `write_files` exist **before** `runcmd` executes
3. DNS routing configured in networkdata is active when `runcmd` runs
4. Services started in `runcmd` inherit the configured network environment

---

## Userdata Configuration

Userdata follows the `#cloud-config` YAML format and configures system state beyond networking.

### Structure

```yaml
#cloud-config

# File creation (init stage)
write_files:
  - path: /etc/example/config.env
    permissions: '0644'
    content: |
      KEY=value

# User accounts
users:
  - name: operator
    uid: 1000
    groups: wheel, docker
    shell: /run/current-system/sw/bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    lock_passwd: true

# Shell commands (config stage)
runcmd:
  - [systemctl, start, docker]
  - echo "Boot complete"

# Disk expansion
growpart:
  mode: auto
  devices: ['/']

resize_rootfs: true
```

### write_files Module

The `write_files` module creates files during the init stage, before `runcmd` executes.

| Field | Required | Description |
|-------|----------|-------------|
| `path` | Yes | Absolute filesystem path |
| `permissions` | No | Octal permissions (default: 0644) |
| `owner` | No | owner:group (default: root:root) |
| `content` | Yes | File contents (literal or base64) |
| `encoding` | No | `text`, `base64`, `gzip`, `gz+base64` |
| `defer` | No | Write in final stage if `true` |

### runcmd Module

Commands execute sequentially during the config stage. Both formats are supported:

```yaml
runcmd:
  # List format (no shell interpretation)
  - [/usr/bin/systemctl, restart, docker]

  # String format (shell interpretation)
  - 'echo "Hello" >> /var/log/boot.log'
```

On NixOS, binaries reside in `/run/current-system/sw/bin/`. Use full paths:

```yaml
runcmd:
  - [/run/current-system/sw/bin/systemctl, start, docker]
```

---

## Networkdata Configuration

Networkdata configures network interfaces via systemd-networkd. The Konductor image uses version 2 format with the `networkd` renderer.

### Version 2 Format

```yaml
network:
  version: 2
  renderer: networkd
  ethernets:
    enp1s0:
      dhcp4: true
      dhcp6: false
      dhcp4-overrides:
        route-metric: 300
        use-routes: false
      routes:
        - to: 10.96.0.0/12
          via: 10.0.2.1
          metric: 100
      nameservers:
        addresses:
          - 10.96.0.10
        search:
          - svc.cluster.local
    enp2s0:
      dhcp4: true
      dhcp-identifier: mac
      dhcp4-overrides:
        route-metric: 100
```

### Supported Configuration Options

| Option | Description |
|--------|-------------|
| `dhcp4`, `dhcp6` | Enable DHCP for IPv4/IPv6 |
| `addresses` | Static IP addresses with CIDR notation |
| `gateway4`, `gateway6` | Default gateway addresses |
| `routes` | Static route entries |
| `nameservers.addresses` | DNS server IP addresses |
| `nameservers.search` | DNS search domains |
| `dhcp4-overrides` | DHCP behavior customization |
| `mtu` | Interface MTU |
| `optional` | Interface not required for boot |

### Networkdata Limitations

Cloud-init networkdata version 2 has specific limitations relevant to advanced DNS configurations:

| Feature | Supported | Workaround |
|---------|-----------|------------|
| DNS servers per interface | Yes | — |
| Search domains | Yes | — |
| **Routing domains (`~prefix`)** | **No** | Use `write_files` |
| **DNSDefaultRoute** | **No** | Use `write_files` |
| **Per-link DNS routing** | **No** | Use `write_files` |

The `nameservers.search` field sets search domains only. It does not support the `~` prefix syntax required for DNS routing domains in systemd-resolved.

---

## DNS Configuration

Complex DNS environments require per-link DNS routing, where different DNS servers handle queries for specific domains. This is common in Kubernetes environments with multiple DNS zones.

### DNS Resolution Architecture

```
┌─────────────────────────────────────────────────────────────────────┐
│                      systemd-resolved                               │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  Query: api.k8s.example.arpa                                        │
│         │                                                           │
│         ▼                                                           │
│  ┌─────────────────────────────────────────────────────────────┐   │
│  │              Domain Routing Table                            │   │
│  ├─────────────────────────────────────────────────────────────┤   │
│  │  Link      │ DNS Server    │ Routing Domains                │   │
│  │────────────┼───────────────┼────────────────────────────────│   │
│  │  enp1s0    │ 10.96.0.10    │ ~svc.cluster.local             │   │
│  │            │               │ ~pod.cluster.local             │   │
│  │────────────┼───────────────┼────────────────────────────────│   │
│  │  enp2s0    │ 192.0.2.53    │ ~example.arpa                  │   │
│  │────────────┼───────────────┼────────────────────────────────│   │
│  │  (global)  │ 198.51.100.1  │ (default route)                │   │
│  └─────────────────────────────────────────────────────────────┘   │
│         │                                                           │
│         ▼                                                           │
│  Route to: enp2s0 → 192.0.2.53                                     │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### Routing Domains vs Search Domains

| Type | Syntax | Behavior |
|------|--------|----------|
| **Search domain** | `example.com` | Appended to unqualified hostnames |
| **Routing domain** | `~example.com` | Queries for `*.example.com` route to this link's DNS |

### Configuring DNS Routing via write_files

Since networkdata does not support routing domains, use `write_files` to create supplemental `.network` files:

```yaml
#cloud-config
write_files:
  # Kubernetes cluster DNS routing
  - path: /etc/systemd/network/99-enp1s0-dns.network
    permissions: '0644'
    content: |
      [Match]
      Name=enp1s0

      [Network]
      DNS=10.96.0.10
      Domains=~svc.cluster.local ~pod.cluster.local
      DNSDefaultRoute=false

  # Custom domain DNS routing
  - path: /etc/systemd/network/99-enp2s0-dns.network
    permissions: '0644'
    content: |
      [Match]
      Name=enp2s0

      [Network]
      DNS=192.0.2.53
      Domains=~example.arpa
      DNSDefaultRoute=false

runcmd:
  # Reload networkd to apply supplemental .network files
  - [/run/current-system/sw/bin/systemctl, reload, systemd-networkd]
```

### .network File Reference

| Section | Option | Description |
|---------|--------|-------------|
| `[Match]` | `Name` | Interface name to match |
| `[Network]` | `DNS` | Space-separated DNS server addresses |
| `[Network]` | `Domains` | Space-separated domains (prefix with `~` for routing) |
| `[Network]` | `DNSDefaultRoute` | `true`/`false` - use this link's DNS as default |
| `[Network]` | `LLMNR` | Link-Local Multicast Name Resolution |
| `[Network]` | `MulticastDNS` | mDNS configuration |

### File Naming and Precedence

systemd-networkd processes `.network` files in lexicographical order. Files with higher numbers are processed later and can supplement earlier configurations.

| Prefix | Typical Use |
|--------|-------------|
| `00-` to `40-` | NixOS-generated base configuration |
| `50-` to `70-` | Cloud-init networkdata rendered files |
| `80-` to `99-` | Supplemental configuration (DNS routing) |

Using `99-` prefixed files ensures DNS routing configuration supplements rather than conflicts with base network configuration.

---

## Proxy Configuration

HTTP/HTTPS proxy settings are injected via environment files and systemd drop-ins.

### Proxy Environment File

```yaml
#cloud-config
write_files:
  - path: /etc/konductor/proxy.env
    permissions: '0644'
    content: |
      http_proxy=http://proxy.example.com:8080
      HTTP_PROXY=http://proxy.example.com:8080
      https_proxy=http://proxy.example.com:8080
      HTTPS_PROXY=http://proxy.example.com:8080
      no_proxy=localhost,127.0.0.1,10.0.0.0/8,.cluster.local
      NO_PROXY=localhost,127.0.0.1,10.0.0.0/8,.cluster.local
```

### Service Integration

The Konductor image includes `konductor-proxy-setup.service` which reads `/etc/konductor/proxy.env` and creates systemd drop-ins for services requiring proxy configuration:

- `nix-daemon.service` — Nix builds and cache fetches
- `docker.service` — Container image pulls

The service creates drop-ins in `/run/systemd/system/<service>.service.d/proxy.conf`:

```ini
[Service]
EnvironmentFile=/etc/konductor/proxy.env
```

### Proxy Bypass Patterns

The `no_proxy` variable accepts:

| Pattern | Matches |
|---------|---------|
| `localhost` | Literal hostname |
| `127.0.0.1` | Literal IP address |
| `.example.com` | All subdomains of example.com |
| `10.0.0.0/8` | CIDR network range |
| `*.cluster.local` | Wildcard subdomain |

---

## Static Host Entries

Static host entries resolve hostnames before DNS is available. This is essential for proxy hostname resolution during early boot when DNS depends on the proxy being reachable.

### Bootstrap Resolution Problem

```
┌─────────────────────────────────────────────────────────────────────┐
│                    Chicken-and-Egg Problem                          │
├─────────────────────────────────────────────────────────────────────┤
│                                                                     │
│  1. VM boots, needs to fetch packages via proxy                     │
│  2. Proxy URL is http://proxy.example.com:8080                      │
│  3. DNS lookup for proxy.example.com requires network               │
│  4. Network requires proxy to reach DNS servers                     │
│  5. Deadlock                                                        │
│                                                                     │
│  Solution: Static host entry resolves proxy.example.com → IP       │
│            before DNS is available                                  │
│                                                                     │
└─────────────────────────────────────────────────────────────────────┘
```

### Configuring Static Hosts

```yaml
#cloud-config
write_files:
  - path: /etc/konductor/static-hosts
    permissions: '0644'
    content: |
      # Bootstrap DNS resolution
      192.0.2.1 proxy.example.com

runcmd:
  # Append static hosts to /etc/hosts
  - '/run/current-system/sw/bin/cat /etc/konductor/static-hosts >> /etc/hosts'
```

### NixOS Requirement

Appending to `/etc/hosts` requires the `/etc` overlay filesystem. See [NixOS-Specific Considerations](#nixos-specific-considerations).

---

## NixOS-Specific Considerations

NixOS manages system configuration declaratively, which affects how cloud-init modifications persist.

### /etc Overlay Filesystem

NixOS traditionally manages `/etc` as symlinks to the Nix store, making it read-only. The overlay filesystem feature enables runtime modifications:

```nix
{
  # Enable writable /etc via overlay filesystem
  system.etc.overlay.enable = true;

  # Requires systemd in initrd
  boot.initrd.systemd.enable = true;
}
```

| Path | Without Overlay | With Overlay |
|------|-----------------|--------------|
| `/etc/hosts` | Read-only (symlink to store) | Writable (overlay upperdir) |
| `/etc/systemd/network/` | Read-only | Writable |
| `/etc/konductor/` | Writable (not managed by NixOS) | Writable |

### Overlay Behavior

- Modifications persist in `/.rw-etc/upper/`
- Changes survive reboots
- Changes do **not** survive `nixos-rebuild switch`
- Kernel 6.6 or later required

### systemd-networkd File Sources

With cloud-init network enabled, `.network` files originate from multiple sources:

```
/etc/systemd/network/
├── 00-*.network          ← NixOS systemd.network.networks
├── 50-cloud-init-*.network  ← cloud-init networkdata renderer
└── 99-*-dns.network      ← cloud-init write_files (supplemental)
```

### NixOS Cloud-Init Module Settings

The Konductor image configures cloud-init with NixOS-specific settings:

```nix
{
  services.cloud-init = {
    enable = true;
    network.enable = true;  # Use systemd-networkd renderer

    settings = {
      system_info.network.renderers = [ "networkd" ];

      cloud_init_modules = [
        "write_files"
        "growpart"
        "resizefs"
        "update_etc_hosts"
        "users_groups"
        "ssh"
      ];

      cloud_config_modules = [
        "runcmd"
        "ssh"
      ];
    };
  };
}
```

### Binary Paths

NixOS does not use standard Linux paths. All commands in `runcmd` must use full paths:

| Standard Path | NixOS Path |
|---------------|------------|
| `/usr/bin/systemctl` | `/run/current-system/sw/bin/systemctl` |
| `/bin/cat` | `/run/current-system/sw/bin/cat` |
| `/usr/bin/mkdir` | `/run/current-system/sw/bin/mkdir` |

---

## Troubleshooting

### Verifying Cloud-Init Execution

```bash
# Check cloud-init status
cloud-init status --long

# View cloud-init logs
journalctl -u cloud-init-local -u cloud-init -u cloud-config -u cloud-final

# Inspect rendered network configuration
cat /etc/systemd/network/*.network
```

### Verifying DNS Configuration

```bash
# Show per-link DNS configuration
resolvectl status

# Test domain routing
resolvectl query api.example.arpa

# Show routing domain assignments
resolvectl domain
```

<details>
<summary>Example resolvectl status output</summary>

```
Global
       Protocols: +LLMNR +mDNS -DNSOverTLS DNSSEC=allow-downgrade
resolv.conf mode: stub

Link 2 (enp1s0)
    Current Scopes: DNS LLMNR/IPv4
         Protocols: +DefaultRoute +LLMNR -mDNS -DNSOverTLS DNSSEC=allow-downgrade
Current DNS Server: 10.96.0.10
       DNS Servers: 10.96.0.10
        DNS Domain: ~svc.cluster.local ~pod.cluster.local

Link 3 (enp2s0)
    Current Scopes: DNS LLMNR/IPv4
         Protocols: -DefaultRoute +LLMNR -mDNS -DNSOverTLS DNSSEC=allow-downgrade
Current DNS Server: 192.0.2.53
       DNS Servers: 192.0.2.53
        DNS Domain: ~example.arpa
```

</details>

### Verifying Proxy Configuration

```bash
# Check proxy environment in nix-daemon
systemctl show nix-daemon --property=Environment

# Check Docker proxy
systemctl show docker --property=Environment

# Test proxy connectivity
curl -v --proxy $http_proxy https://cache.nixos.org
```

### Common Issues

| Symptom | Cause | Resolution |
|---------|-------|------------|
| `/etc/hosts` append fails | `/etc` overlay not enabled | Enable `system.etc.overlay.enable` |
| DNS routing not working | Missing `~` prefix on domains | Use `Domains=~domain` syntax |
| Proxy not applied to services | Drop-in not loaded | Run `systemctl daemon-reload` |
| `.network` file ignored | File naming precedence | Use higher prefix (e.g., `99-`) |
| `command not found` in runcmd | Missing full path | Use `/run/current-system/sw/bin/` |

---

## Reference

### Cloud-Init Documentation

- [Cloud-Init Documentation](https://cloudinit.readthedocs.io/)
- [Network Config Version 2](https://cloudinit.readthedocs.io/en/latest/reference/network-config-format-v2.html)
- [Module Reference](https://cloudinit.readthedocs.io/en/latest/reference/modules.html)

### systemd Documentation

- [systemd.network(5)](https://www.freedesktop.org/software/systemd/man/systemd.network.html)
- [resolved.conf(5)](https://www.freedesktop.org/software/systemd/man/resolved.conf.html)
- [resolvectl(1)](https://www.freedesktop.org/software/systemd/man/resolvectl.html)

### NixOS Documentation

- [NixOS Cloud-Init Module](https://search.nixos.org/options?query=services.cloud-init)
- [NixOS systemd-networkd](https://search.nixos.org/options?query=systemd.network)
- [NixOS /etc Overlay](https://nixos.wiki/wiki/Etc_overlay)

### Related Files in This Repository

| File | Description |
|------|-------------|
| `src/qcow2/default.nix` | QCOW2 image NixOS configuration |
| `src/lib/versions.nix` | Version definitions |
| `docs/developer_guide/qcow2/BUILD.md` | Image build instructions |
