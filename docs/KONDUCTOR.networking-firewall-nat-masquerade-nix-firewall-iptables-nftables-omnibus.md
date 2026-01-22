# Konductor Networking: Firewall, NAT, Masquerade, iptables, nftables Omnibus

> Comprehensive guide for NixOS networking configuration in Konductor QCOW2 VMs
> covering port forwarding from external interfaces to Docker/Kubernetes networks.

## Table of Contents

- [Problem Statement](#problem-statement)
- [Architecture Overview](#architecture-overview)
- [NixOS Networking Options](#nixos-networking-options)
  - [Option 1: networking.nat (Recommended)](#option-1-networkingnat-recommended)
  - [Option 2: networking.nat.extraCommands](#option-2-networkingnatextracommands)
  - [Option 3: networking.firewall.extraCommands](#option-3-networkingfirewallextracommands)
  - [Option 4: nftables](#option-4-nftables)
  - [Option 5: systemd-networkd](#option-5-systemd-networkd)
  - [Option 6: Docker-native Solutions](#option-6-docker-native-solutions)
- [Boot Ordering and Systemd](#boot-ordering-and-systemd)
- [iptables Chain Architecture](#iptables-chain-architecture)
- [Docker Interaction](#docker-interaction)
- [Implementation Recommendations](#implementation-recommendations)
- [Troubleshooting](#troubleshooting)
- [References](#references)

---

## Problem Statement

### Scenario

Konductor is a NixOS QCOW2 VM built via nixos-generators that serves as a development
environment. The VM runs Docker with a Talos Kubernetes cluster inside containers.

**Network Topology:**
```
┌─────────────────────────────────────────────────────────────────────────────┐
│ Home Network (192.168.1.0/24)                                               │
│                                                                             │
│   Laptop (192.168.1.x) ──────► Konductor VM (192.168.1.83:80/443)          │
│                                       │                                     │
└───────────────────────────────────────┼─────────────────────────────────────┘
                                        │
┌───────────────────────────────────────┼─────────────────────────────────────┐
│ Konductor VM                          │                                     │
│                                       ▼                                     │
│   enp2s0: 192.168.1.83 (external, DHCP)                                    │
│   br-*: 10.5.0.1 (Docker bridge)                                           │
│                                       │                                     │
│                                       ▼                                     │
│   ┌─────────────────────────────────────────────────────────────────────┐  │
│   │ Docker Network (10.5.0.0/24)                                        │  │
│   │                                                                     │  │
│   │   Talos Container (10.5.0.11)                                      │  │
│   │       └── Kubernetes Cluster                                        │  │
│   │           ├── Envoy Gateway LB: 10.5.0.241:80/443                  │  │
│   │           ├── Cilium Ingress LB: 10.5.0.240:80/443                 │  │
│   │           └── CoreDNS LB: 10.5.0.243:53                            │  │
│   └─────────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Goal

Users on the home network (192.168.1.0/24) should access Kubernetes services by
connecting to the VM's external IP (192.168.1.83:80/443), which forwards traffic
to Envoy Gateway (10.5.0.241:80/443) inside the Docker network.

### Requirements

1. **Port Forwarding (DNAT)**: External traffic → Docker network services
2. **Masquerading (SNAT)**: Return traffic appears from VM's Docker bridge IP
3. **Persistence**: Rules survive reboots and firewall reloads
4. **Docker Coexistence**: NixOS rules must not conflict with Docker's iptables
5. **Declarative**: Configuration in Nix, not ad-hoc commands

---

## Architecture Overview

### Current NixOS Configuration

```nix
# From k9/src/qcow2/default.nix
networking = {
  hostName = "konductor";
  useNetworkd = true;
};

systemd.network = {
  enable = true;
  networks."10-ethernet" = {
    matchConfig.Type = "ether";
    networkConfig.DHCP = "yes";
  };
  # Docker interfaces unmanaged to prevent systemd-networkd conflicts
  networks."05-docker-unmanaged" = {
    matchConfig.Name = "docker* br-* veth*";
    linkConfig = {
      Unmanaged = "yes";
      RequiredForOnline = "no";
    };
  };
};

virtualisation.docker = {
  enable = true;
  daemon.settings = {
    iptables = true;
    ip-forward = true;
    ip-masq = true;
    userland-proxy = false;
  };
};
```

### Network Interfaces

| Interface | IP Address | Role |
|-----------|------------|------|
| `enp2s0` | 192.168.1.83 (DHCP) | External, home network |
| `br-*` | 10.5.0.1/24 | Docker bridge |
| `docker0` | 172.17.0.1/16 | Default Docker bridge (unused) |

---

## NixOS Networking Options

### Option 1: networking.nat (Recommended)

The `networking.nat` module is the NixOS-idiomatic way to configure NAT and port forwarding.

#### How It Works

- Creates custom iptables chains: `nixos-nat-pre`, `nixos-nat-post`, `nixos-nat-out`
- Integrates with `firewall.service` if firewall is enabled
- Automatically enables IP forwarding (`net.ipv4.ip_forward = 1`)
- Applied BEFORE Docker starts (safe ordering)

#### Configuration

```nix
networking.nat = {
  enable = true;

  # External interface receiving incoming traffic
  externalInterface = "enp2s0";

  # Internal interfaces to masquerade (SNAT)
  # NOTE: Wildcards like "br-*" do NOT work - must use explicit names
  internalInterfaces = [ "br-5e13af75e05a" ];

  # Port forwarding rules (DNAT)
  forwardPorts = [
    {
      sourcePort = 80;
      destination = "10.5.0.241:80";
      proto = "tcp";
      # loopbackIPs enables hairpin NAT (accessing from VM itself)
      loopbackIPs = [ "192.168.1.83" ];
    }
    {
      sourcePort = 443;
      destination = "10.5.0.241:443";
      proto = "tcp";
      loopbackIPs = [ "192.168.1.83" ];
    }
  ];
};
```

#### Generated iptables Rules

```bash
# PREROUTING chain (DNAT)
-A nixos-nat-pre -i enp2s0 -p tcp --dport 80 -j DNAT --to-destination 10.5.0.241:80
-A nixos-nat-pre -i enp2s0 -p tcp --dport 443 -j DNAT --to-destination 10.5.0.241:443

# POSTROUTING chain (MASQUERADE)
-A nixos-nat-post -o enp2s0 -s 10.5.0.0/24 -j MASQUERADE

# OUTPUT chain (loopback DNAT for hairpin NAT)
-A nixos-nat-out -d 192.168.1.83 -p tcp --dport 80 -j DNAT --to-destination 10.5.0.241:80
```

#### Pros

- Declarative, NixOS-native
- Proper systemd integration
- Handles hairpin NAT via `loopbackIPs`
- Automatically manages IP forwarding

#### Cons

- **Wildcard interfaces not supported**: `internalInterfaces = [ "br-*" ]` does NOT work
- Must know exact Docker bridge name (changes on recreation)
- No dynamic interface detection

#### Module Source

- `nixos/modules/services/networking/nat.nix`

---

### Option 2: networking.nat.extraCommands

For cases requiring wildcards or custom rules not covered by `forwardPorts`.

#### Configuration

```nix
networking.nat = {
  enable = true;
  externalInterface = "enp2s0";

  extraCommands = ''
    # DNAT from external interface to Envoy Gateway
    iptables -t nat -A nixos-nat-pre -i enp2s0 -p tcp --dport 80 -j DNAT --to-destination 10.5.0.241:80
    iptables -t nat -A nixos-nat-pre -i enp2s0 -p tcp --dport 443 -j DNAT --to-destination 10.5.0.241:443

    # Allow forwarded traffic to Docker network
    iptables -A FORWARD -d 10.5.0.0/24 -j ACCEPT
    iptables -A FORWARD -s 10.5.0.0/24 -j ACCEPT

    # Masquerade for all Docker bridges (wildcard)
    iptables -t nat -A nixos-nat-post -s 10.5.0.0/24 ! -d 10.5.0.0/24 -j MASQUERADE
  '';

  extraStopCommands = ''
    iptables -t nat -D nixos-nat-pre -i enp2s0 -p tcp --dport 80 -j DNAT --to-destination 10.5.0.241:80 || true
    iptables -t nat -D nixos-nat-pre -i enp2s0 -p tcp --dport 443 -j DNAT --to-destination 10.5.0.241:443 || true
  '';
};
```

#### Pros

- Supports wildcards and complex rules
- Full iptables flexibility
- Still integrates with NixOS NAT module

#### Cons

- Less declarative
- Must manually handle cleanup in `extraStopCommands`

---

### Option 3: networking.firewall.extraCommands

If you prefer all rules in the firewall module.

#### Configuration

```nix
networking.firewall = {
  enable = true;

  # Allow incoming traffic on forwarded ports
  allowedTCPPorts = [ 80 443 ];

  # Trust Docker bridges (bypass firewall for container traffic)
  trustedInterfaces = [ "docker0" ];
  # Note: Can't use wildcards here either

  extraCommands = ''
    # DNAT rules
    iptables -t nat -A PREROUTING -i enp2s0 -p tcp --dport 80 -j DNAT --to-destination 10.5.0.241:80
    iptables -t nat -A PREROUTING -i enp2s0 -p tcp --dport 443 -j DNAT --to-destination 10.5.0.241:443

    # Allow forwarding
    iptables -A FORWARD -d 10.5.0.0/24 -j ACCEPT
    iptables -A FORWARD -s 10.5.0.0/24 -j ACCEPT
  '';
};
```

#### Differences from networking.nat

| Aspect | networking.nat | networking.firewall |
|--------|---------------|---------------------|
| Chain used | `nixos-nat-pre` | Direct `PREROUTING` |
| Masquerade | Automatic | Manual |
| IP forward | Automatic | Manual |
| Integration | Own service or firewall hook | Part of firewall |

---

### Option 4: nftables

NixOS can use `nftables` instead of `iptables` as the firewall backend.

#### Configuration

```nix
networking.nftables = {
  enable = true;

  tables = {
    nat = {
      family = "ip";
      content = ''
        chain prerouting {
          type nat hook prerouting priority dstnat;
          iifname "enp2s0" tcp dport 80 dnat to 10.5.0.241:80
          iifname "enp2s0" tcp dport 443 dnat to 10.5.0.241:443
        }

        chain postrouting {
          type nat hook postrouting priority srcnat;
          oifname "enp2s0" ip saddr 10.5.0.0/24 masquerade
        }
      '';
    };
  };
};
```

#### Critical Warning: Docker Compatibility

**Docker ALWAYS loads iptables kernel modules**, even when NixOS uses nftables.

```
When networking.nftables.enable = true:
- NixOS uses nftables for its firewall
- Docker still uses iptables
- Both rule systems coexist
- Can cause confusion and conflicts
```

From nixpkgs source:
> "The nftables module disables the ip_tables kernel module, but Docker automatically loads it."

#### When to Use nftables

- New deployments without Docker
- Environments where you can configure Docker to not use iptables
- When you need nftables-specific features (sets, maps, etc.)

#### When to Avoid nftables

- Docker-heavy environments (like Konductor)
- When you need predictable iptables behavior
- Mixed environments with legacy iptables tools

---

### Option 5: systemd-networkd

`systemd-networkd` has limited NAT capabilities.

#### Available Options

```nix
systemd.network.networks."10-ethernet" = {
  networkConfig = {
    # Enable IP forwarding on this interface
    IPForward = "yes";  # or "ipv4", "ipv6"

    # Enable masquerading (SNAT) - basic only
    IPMasquerade = "yes";  # or "ipv4", "ipv6"
  };
};
```

#### Limitations

- **No DNAT/port forwarding**: systemd-networkd cannot do destination NAT
- **Basic masquerading only**: No fine-grained control
- **Not suitable for our use case**: Cannot forward external ports to internal IPs

#### When to Use

- Simple masquerading for outbound traffic
- As a supplement to iptables/nftables, not a replacement
- When you just need IP forwarding enabled

---

### Option 6: Docker-native Solutions

Docker provides its own port publishing mechanisms.

#### Port Publishing

```yaml
# docker-compose.yml
services:
  envoy:
    ports:
      - "192.168.1.83:80:80"   # Bind to specific IP
      - "192.168.1.83:443:443"
```

Or via Docker daemon settings:

```nix
virtualisation.docker.daemon.settings = {
  iptables = true;      # Let Docker manage iptables (default)
  ip-forward = true;    # Enable IP forwarding (default)
  ip-masq = true;       # Enable masquerading (default)
  userland-proxy = false;  # Use iptables instead of userland proxy
};
```

#### Why This Doesn't Work for Konductor

1. **Kubernetes LoadBalancer IPs**: Services get IPs like 10.5.0.241 from Cilium L2
2. **Not container ports**: These are virtual IPs on the Docker network
3. **Docker port publishing operates on containers**, not network-level services

Docker's `-p` flag works for:
```
Host:Port → Container:Port
```

We need:
```
Host:Port → Docker-Network-IP:Port (LoadBalancer VIP)
```

This requires host-level NAT (networking.nat), not Docker port publishing.

---

## Boot Ordering and Systemd

### Service Ordering

```
                    ┌──────────────────┐
                    │ sysinit.target   │
                    └────────┬─────────┘
                             │
                    ┌────────▼─────────┐
                    │ network-pre.     │
                    │ target           │◄──── firewall.service (before)
                    └────────┬─────────┘
                             │
                    ┌────────▼─────────┐
                    │ network.target   │◄──── nat.service (if firewall disabled)
                    └────────┬─────────┘
                             │
                    ┌────────▼─────────┐
                    │ network-online.  │
                    │ target           │
                    └────────┬─────────┘
                             │
                    ┌────────▼─────────┐
                    │ docker.service   │◄──── Docker iptables rules applied here
                    └──────────────────┘
```

### Key Ordering Facts

| Service | Ordering | When Rules Applied |
|---------|----------|-------------------|
| `firewall.service` | `before = [ "network-pre.target" ]` | **FIRST** - Very early |
| `nat.service` | `after = [ "network-pre.target" ]` | After basic network, before online |
| `docker.service` | `after = [ "network-online.target" ]` | **LAST** - After network ready |

**Implication**: NixOS firewall/NAT rules are applied BEFORE Docker starts.
This is correct behavior - no race condition.

### Systemd Units

#### When `networking.firewall.enable = true` AND `networking.nat.enable = true`

- NAT rules injected into `firewall.service` via `extraCommands`
- Single service manages both firewall and NAT
- Unit: `firewall.service`

#### When `networking.firewall.enable = false` AND `networking.nat.enable = true`

- Separate `nat.service` created
- Unit: `nat.service`

### Custom Service Example

If you need a custom systemd service for iptables rules:

```nix
systemd.services.custom-nat = {
  description = "Custom NAT rules for Konductor";

  after = [ "network-online.target" ];
  before = [ "docker.service" ];
  wants = [ "network-online.target" ];
  wantedBy = [ "multi-user.target" ];

  serviceConfig = {
    Type = "oneshot";
    RemainAfterExit = true;
    ExecStart = pkgs.writeShellScript "setup-nat" ''
      iptables -t nat -A PREROUTING -i enp2s0 -p tcp --dport 80 -j DNAT --to-destination 10.5.0.241:80
      iptables -t nat -A PREROUTING -i enp2s0 -p tcp --dport 443 -j DNAT --to-destination 10.5.0.241:443
    '';
    ExecStop = pkgs.writeShellScript "teardown-nat" ''
      iptables -t nat -D PREROUTING -i enp2s0 -p tcp --dport 80 -j DNAT --to-destination 10.5.0.241:80 || true
      iptables -t nat -D PREROUTING -i enp2s0 -p tcp --dport 443 -j DNAT --to-destination 10.5.0.241:443 || true
    '';
  };
};
```

---

## iptables Chain Architecture

### Tables and Chains

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ PACKET FLOW                                                                 │
│                                                                             │
│   Incoming ──► nat/PREROUTING ──► filter/FORWARD ──► nat/POSTROUTING ──► Out│
│                     │                   │                   │               │
│                     ▼                   ▼                   ▼               │
│              nixos-nat-pre      nixos-fw-forward     nixos-nat-post        │
│              (DNAT rules)       (filter rules)       (MASQUERADE)          │
│                                                                             │
│   Local ────► nat/OUTPUT ──► filter/OUTPUT ──► nat/POSTROUTING ──► Out     │
│                   │                                     │                   │
│                   ▼                                     ▼                   │
│            nixos-nat-out                         nixos-nat-post            │
│            (loopback DNAT)                       (MASQUERADE)              │
└─────────────────────────────────────────────────────────────────────────────┘
```

### NixOS NAT Chains

| Chain | Table | Purpose |
|-------|-------|---------|
| `nixos-nat-pre` | nat | DNAT rules (port forwarding) |
| `nixos-nat-post` | nat | SNAT/MASQUERADE rules |
| `nixos-nat-out` | nat | Loopback DNAT (hairpin NAT) |
| `nixos-nat-forward` | filter | Forward filtering for NAT |

### Docker Chains

Docker creates its own chains:

| Chain | Table | Purpose |
|-------|-------|---------|
| `DOCKER` | nat | Container port DNAT |
| `DOCKER-USER` | filter | User-defined rules (check first) |
| `DOCKER-ISOLATION-STAGE-1` | filter | Network isolation |
| `DOCKER-ISOLATION-STAGE-2` | filter | Network isolation |

### Rule Precedence

```bash
# View rule order
iptables -t nat -L PREROUTING -n --line-numbers
iptables -t nat -L POSTROUTING -n --line-numbers
iptables -L FORWARD -n --line-numbers
```

Typical order:
1. NixOS chains (applied at boot)
2. Docker chains (applied when Docker starts)
3. Docker container rules (applied when containers start)

---

## Docker Interaction

### Docker's iptables Behavior

When `virtualisation.docker.daemon.settings.iptables = true`:

1. Docker creates its chains on daemon start
2. Container port publishing adds DNAT rules to `DOCKER` chain
3. Docker manages `DOCKER-USER` for user customization
4. Masquerading handled by Docker for container outbound traffic

### Coexistence Strategy

```nix
# Recommended Docker settings for coexistence
virtualisation.docker.daemon.settings = {
  iptables = true;       # Let Docker manage its own rules
  ip-forward = true;     # Required for routing
  ip-masq = true;        # Docker handles its own masquerading
  userland-proxy = false; # Use iptables for port publishing (more efficient)
  icc = true;            # Inter-container communication
  live-restore = true;   # Reduce iptables churn on daemon restart
};
```

### trustedInterfaces

Docker bridges should be trusted to allow container traffic:

```nix
networking.firewall.trustedInterfaces = [ "docker0" ];

# For specific bridges (can't use wildcards):
# networking.firewall.trustedInterfaces = [ "docker0" "br-5e13af75e05a" ];
```

**Effect**: Traffic on trusted interfaces bypasses `nixos-fw` chain entirely.

### Potential Conflicts

| Scenario | Problem | Solution |
|----------|---------|----------|
| Both NixOS and Docker DNAT same port | First rule wins | Use different approaches for different ports |
| Masquerade conflicts | Double NAT | Let Docker handle container masquerade, NixOS handles external |
| Firewall blocks forwarded traffic | Packets dropped | Add FORWARD rules or use trustedInterfaces |

---

## Implementation Recommendations

### For Konductor QCOW2

#### Recommended: networking.nat with extraCommands

```nix
# Add to k9/src/qcow2/default.nix in konductorModule

networking.nat = {
  enable = true;
  externalInterface = "enp2s0";

  # Use extraCommands for flexibility with Docker bridge names
  extraCommands = ''
    # Forward HTTP/HTTPS to Envoy Gateway
    iptables -t nat -A nixos-nat-pre -i enp2s0 -p tcp --dport 80 -j DNAT --to-destination 10.5.0.241:80
    iptables -t nat -A nixos-nat-pre -i enp2s0 -p tcp --dport 443 -j DNAT --to-destination 10.5.0.241:443

    # Forward SSH (port 22) to Envoy Gateway for git+ssh
    iptables -t nat -A nixos-nat-pre -i enp2s0 -p tcp --dport 22 -j DNAT --to-destination 10.5.0.241:22

    # Allow forwarded traffic to Docker network
    iptables -A FORWARD -d 10.5.0.0/24 -o br-+ -j ACCEPT
    iptables -A FORWARD -s 10.5.0.0/24 -i br-+ -j ACCEPT

    # Masquerade for Docker network (handles return traffic)
    iptables -t nat -A nixos-nat-post -s 10.5.0.0/24 ! -d 10.5.0.0/24 -j MASQUERADE
  '';
};

networking.firewall = {
  enable = true;
  allowedTCPPorts = [ 22 80 443 6443 50000 ];  # SSH, HTTP, HTTPS, K8s API, Talos
  # Trust Docker interfaces for container-to-container traffic
  trustedInterfaces = [ "docker0" ];
};
```

#### Why This Approach

1. **networking.nat.enable = true**: Gets proper systemd integration and IP forwarding
2. **extraCommands**: Flexibility for wildcard matching (`br-+` in iptables)
3. **Explicit FORWARD rules**: Ensures traffic can traverse to Docker network
4. **Masquerade rule**: Handles return traffic correctly
5. **trustedInterfaces**: Allows Docker internal traffic without explicit rules

### For Dynamic Bridge Names

If the Docker bridge name changes (e.g., on compose recreation), use interface patterns:

```bash
# iptables supports + as wildcard
-o br-+    # Matches br-* (any Docker bridge)
-i br-+    # Matches br-* incoming
```

### Environment-Specific Configuration

For cloud-init based configuration (different targets have different external interfaces):

```nix
# Could be extended to read from /etc/konductor/network.env
# Written by cloud-init with target-specific values
networking.nat.extraCommands = ''
  EXTERNAL_IF="''${KONDUCTOR_EXTERNAL_IF:-enp2s0}"
  ENVOY_IP="''${KONDUCTOR_ENVOY_IP:-10.5.0.241}"

  iptables -t nat -A nixos-nat-pre -i "$EXTERNAL_IF" -p tcp --dport 80 -j DNAT --to-destination "$ENVOY_IP:80"
  iptables -t nat -A nixos-nat-pre -i "$EXTERNAL_IF" -p tcp --dport 443 -j DNAT --to-destination "$ENVOY_IP:443"
'';
```

---

## Troubleshooting

### Verify Rules Are Applied

```bash
# NAT table rules
sudo iptables -t nat -L -n -v

# Filter table (FORWARD chain)
sudo iptables -L FORWARD -n -v

# Specific chains
sudo iptables -t nat -L nixos-nat-pre -n -v
sudo iptables -t nat -L nixos-nat-post -n -v
```

### Check IP Forwarding

```bash
cat /proc/sys/net/ipv4/ip_forward
# Should be 1
```

### Test Connectivity

```bash
# From external machine
curl -k https://192.168.1.83/

# From VM (hairpin NAT test)
curl -k https://192.168.1.83/

# Direct to Envoy (from VM)
curl -k https://10.5.0.241/
```

### Debug Packet Flow

```bash
# Watch NAT table counters
watch -n 1 'sudo iptables -t nat -L nixos-nat-pre -n -v'

# Trace packets
sudo iptables -t raw -A PREROUTING -p tcp --dport 443 -j TRACE
sudo dmesg | grep TRACE
```

### Common Issues

| Symptom | Cause | Fix |
|---------|-------|-----|
| Connection refused | Firewall blocking | Add to `allowedTCPPorts` |
| Connection timeout | No DNAT rule | Check `nixos-nat-pre` chain |
| Works locally, not externally | Missing FORWARD rule | Add FORWARD ACCEPT rules |
| Intermittent failures | Docker rule conflicts | Check rule ordering |

---

## References

### NixOS Modules

- `nixos/modules/services/networking/nat.nix` - NAT module
- `nixos/modules/services/networking/firewall.nix` - Firewall module
- `nixos/modules/services/networking/nftables.nix` - nftables module
- `nixos/modules/virtualisation/docker.nix` - Docker module

### External Documentation

- [NixOS Manual: Firewall](https://nixos.org/manual/nixos/stable/#sec-firewall)
- [iptables Tutorial](https://www.frozentux.net/iptables-tutorial/iptables-tutorial.html)
- [Docker Networking with iptables](https://docs.docker.com/network/iptables/)
- [systemd-networkd.network man page](https://www.freedesktop.org/software/systemd/man/systemd.network.html)

### DeepWiki Queries

This document was informed by comprehensive queries to the NixOS/nixpkgs DeepWiki:
- networking.nat module options and implementation
- networking.firewall extraCommands vs extraForwardRules
- Boot ordering between firewall, nat, and docker services
- Docker iptables interaction with NixOS firewall
- nftables vs iptables tradeoffs

---

## Changelog

| Date | Change |
|------|--------|
| 2026-01-21 | Initial document created from DeepWiki research |
