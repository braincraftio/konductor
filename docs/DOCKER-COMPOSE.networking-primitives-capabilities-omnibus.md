# Docker Compose Networking: Primitives and Capabilities Omnibus

> Comprehensive guide for Docker Compose networking capabilities, limitations,
> and integration with host-level networking (NixOS) for the Konductor platform.

## Table of Contents

- [Problem Statement](#problem-statement)
- [Architecture Overview](#architecture-overview)
- [Network Drivers](#network-drivers)
  - [Bridge Networks](#bridge-networks)
  - [macvlan Networks](#macvlan-networks)
  - [ipvlan Networks](#ipvlan-networks)
  - [Host Network Mode](#host-network-mode)
- [Port Publishing](#port-publishing)
- [Advanced Networking](#advanced-networking)
  - [Multiple Networks Per Service](#multiple-networks-per-service)
  - [Network Namespace Sharing](#network-namespace-sharing)
  - [External Networks](#external-networks)
  - [IPAM Configuration](#ipam-configuration)
- [Capabilities and Sysctls](#capabilities-and-sysctls)
- [Docker Daemon Integration](#docker-daemon-integration)
- [Compose Networking Limitations](#compose-networking-limitations)
- [Solution Comparison](#solution-comparison)
- [Recommended Architecture](#recommended-architecture)
- [References](#references)

---

## Problem Statement

### Scenario

Konductor is a NixOS VM running Docker Compose with a Talos Kubernetes cluster
inside containers. External users need to access Kubernetes services via the VM's
external IP.

### Network Topology

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ External Network (192.168.1.0/24)                                           │
│                                                                             │
│   External Users ──────► Konductor VM (192.168.1.83:80/443)                │
└────────────────────────────────┬────────────────────────────────────────────┘
                                 │
                                 ▼
┌────────────────────────────────────────────────────────────────────────────┐
│ NixOS VM "Konductor"                                                        │
│                                                                             │
│   enp2s0: 192.168.1.83 (external interface, DHCP)                          │
│   br-xxxxx: 10.5.0.1 (Docker bridge gateway)                               │
│                                                                             │
│   ┌────────────────────────────────────────────────────────────────────┐   │
│   │ Docker Compose Network (10.5.0.0/24)                               │   │
│   │                                                                    │   │
│   │   talos-cp1: 10.5.0.11 (Talos Kubernetes container)               │   │
│   │       │                                                            │   │
│   │       └── Kubernetes Cluster (inside container)                    │   │
│   │           ├── Pod Network: 10.244.0.0/16 (Cilium CNI)             │   │
│   │           │                                                        │   │
│   │           └── LoadBalancer VIPs (Cilium L2 Announcements)         │   │
│   │               ├── Envoy Gateway: 10.5.0.241:80/443                │   │
│   │               ├── Cilium Ingress: 10.5.0.240:80/443               │   │
│   │               └── CoreDNS: 10.5.0.243:53                          │   │
│   └────────────────────────────────────────────────────────────────────┘   │
└────────────────────────────────────────────────────────────────────────────┘
```

### The Challenge

The LoadBalancer VIPs (10.5.0.240-255) are **virtual IPs** managed by Cilium L2
inside the Kubernetes cluster. They are NOT container IPs - they're announced
via ARP on the Docker bridge network by Cilium.

**Goal**: External users connect to `192.168.1.83:80` → traffic forwards to `10.5.0.241:80`

---

## Architecture Overview

### Current compose.yaml

```yaml
networks:
  talos-network:
    name: talos-network
    driver: bridge
    ipam:
      config:
        - subnet: 10.5.0.0/24
          gateway: 10.5.0.1
          ip_range: 10.5.0.0/24

services:
  talos-cp1:
    image: ghcr.io/siderolabs/talos:v1.9.4
    container_name: talos-cp1
    hostname: cp1
    privileged: true
    networks:
      talos-network:
        ipv4_address: 10.5.0.11
    ports:
      - "127.0.0.1:6443:6443"   # Kubernetes API
      - "127.0.0.1:50000:50000" # Talos API
      - "127.0.0.1:80:80"       # HTTP (localhost only)
      - "127.0.0.1:443:443"     # HTTPS (localhost only)
    volumes:
      - talos-cp1-var:/var
      - talos-cp1-etc:/etc/kubernetes
```

---

## Network Drivers

### Bridge Networks

The default and most common Docker network driver.

#### Configuration Options

```yaml
networks:
  my-network:
    driver: bridge
    driver_opts:
      # Bridge name on host (default: br-<network-id>)
      com.docker.network.bridge.name: "my-bridge"

      # Enable IP masquerading (SNAT for outbound traffic)
      com.docker.network.bridge.enable_ip_masquerade: "true"

      # Inter-container communication on this bridge
      com.docker.network.bridge.enable_icc: "true"

      # Host IP to bind published ports (default: 0.0.0.0)
      com.docker.network.bridge.host_binding_ipv4: "192.168.1.83"

      # Maximum Transmission Unit
      com.docker.network.driver.mtu: "1500"

    ipam:
      driver: default
      config:
        - subnet: 10.5.0.0/24
          gateway: 10.5.0.1
          ip_range: 10.5.0.0/28  # Allocatable range for containers
          aux_addresses:
            # Reserve IPs for LoadBalancer VIPs (won't be auto-assigned)
            lb_envoy: 10.5.0.241
            lb_cilium: 10.5.0.240
            lb_coredns: 10.5.0.243
```

#### Key driver_opts Explained

| Option | Default | Description |
|--------|---------|-------------|
| `enable_ip_masquerade` | true | SNAT for container outbound traffic |
| `enable_icc` | true | Containers can communicate on same bridge |
| `host_binding_ipv4` | 0.0.0.0 | Host IP for published ports |
| `name` | br-<id> | Custom bridge interface name |
| `mtu` | 1500 | Maximum packet size |

#### Relevance to Our Use Case

- `host_binding_ipv4` controls which host IP published ports bind to
- Does NOT help forward to VIPs - only affects container ports
- `aux_addresses` reserves IPs for Cilium L2 LoadBalancer pool

---

### macvlan Networks

Containers get their own MAC address and appear as physical devices on the network.

#### Configuration

```yaml
networks:
  external-macvlan:
    driver: macvlan
    driver_opts:
      parent: enp2s0  # Host's physical interface
    ipam:
      config:
        - subnet: 192.168.1.0/24
          gateway: 192.168.1.1
          ip_range: 192.168.1.200/28  # Range for containers

services:
  talos-cp1:
    networks:
      external-macvlan:
        ipv4_address: 192.168.1.100
```

#### How It Works

1. Container gets unique MAC address
2. Traffic goes directly to physical network via parent interface
3. Container is reachable at 192.168.1.100 from anywhere on the LAN
4. No NAT required - direct L2 connectivity

#### Advantages

- Direct network presence (no NAT)
- Full L2 connectivity with physical network
- Cilium L2 could advertise VIPs directly on 192.168.1.x

#### Limitations

| Limitation | Impact | Workaround |
|------------|--------|------------|
| Host cannot reach container | VM can't talk to talos-cp1 | Create macvlan interface on host |
| Promiscuous mode may be required | Some hypervisors block this | Check virtualization settings |
| IP conflicts possible | Must coordinate with DHCP | Use static IPs outside DHCP range |
| Complex for Kubernetes | Pod networking complexity | Requires careful CNI configuration |

#### Host-to-Container Communication Fix

```bash
# Create macvlan interface on host for communication
ip link add mac0 link enp2s0 type macvlan mode bridge
ip addr add 192.168.1.250/24 dev mac0
ip link set mac0 up
```

---

### ipvlan Networks

Similar to macvlan but containers share host's MAC address.

#### L2 vs L3 Modes

| Mode | Description | Use Case |
|------|-------------|----------|
| L2 | Containers on same broadcast domain as host | Direct LAN access |
| L3 | Host routes traffic to containers | Network isolation with routing |

#### L2 Mode Configuration

```yaml
networks:
  external-ipvlan:
    driver: ipvlan
    driver_opts:
      parent: enp2s0
      ipvlan_mode: l2
    ipam:
      config:
        - subnet: 192.168.1.0/24

services:
  talos-cp1:
    networks:
      external-ipvlan:
        ipv4_address: 192.168.1.100
```

#### L3 Mode Configuration

```yaml
networks:
  routed-ipvlan:
    driver: ipvlan
    driver_opts:
      parent: enp2s0
      ipvlan_mode: l3
    ipam:
      config:
        - subnet: 10.10.0.0/24  # Different subnet, host routes
```

#### When to Use

- **L2**: When you need direct LAN access like macvlan, but MAC address conservation matters
- **L3**: When you want host to act as router for containers

---

### Host Network Mode

Container shares the host's network namespace entirely.

#### Configuration

```yaml
services:
  talos-cp1:
    image: ghcr.io/siderolabs/talos:v1.9.4
    network_mode: host
    # Note: 'ports' cannot be used with network_mode: host
```

#### What Happens

1. Container uses host's network interfaces directly
2. Container sees `enp2s0` (192.168.1.83) as its own interface
3. Any ports opened bind directly to host IPs
4. No network isolation from host

#### Implications for Talos/Kubernetes

| Aspect | With Host Network | Impact |
|--------|-------------------|--------|
| Cilium L2 VIPs | Advertised on host's 192.168.1.x | VIPs would be on physical network |
| Pod Network | Uses host's network namespace | More complex CNI setup required |
| Port Conflicts | Container ports conflict with host | Must manage port allocation |
| Network Isolation | None | Security considerations |

#### Mixing Host Mode with Other Networks

```yaml
services:
  talos-cp1:
    network_mode: host  # Uses host network

  helper:
    networks:
      - internal-bridge  # Uses Docker bridge
```

**Note**: A single container cannot use both `network_mode: host` AND Docker-managed networks.

---

## Port Publishing

### Short Syntax

```yaml
ports:
  # Bind to all interfaces
  - "80:80"

  # Bind to specific host IP
  - "192.168.1.83:80:80"

  # Bind to localhost only
  - "127.0.0.1:80:80"

  # Random host port
  - "80"

  # Port range
  - "8080-8090:8080-8090"

  # UDP protocol
  - "53:53/udp"
```

### Long Syntax

```yaml
ports:
  - target: 80        # Container port
    published: 80     # Host port
    protocol: tcp     # tcp or udp
    mode: host        # host or ingress (Swarm)
    host_ip: 192.168.1.83  # Specific host IP
```

### Critical Limitation

**Port publishing forwards to CONTAINER ports, not arbitrary IPs.**

```yaml
# This works: forwards host:80 → container:80
ports:
  - "80:80"

# This is IMPOSSIBLE in pure Docker:
# host:80 → 10.5.0.241:80 (LoadBalancer VIP)
```

Docker's port publishing mechanism uses the container's IP address as the DNAT target.
It cannot forward to arbitrary IPs on the Docker network.

---

## Advanced Networking

### Multiple Networks Per Service

Containers can connect to multiple networks simultaneously.

#### Configuration

```yaml
networks:
  internal:
    driver: bridge
    ipam:
      config:
        - subnet: 10.5.0.0/24

  external:
    driver: macvlan
    driver_opts:
      parent: enp2s0
    ipam:
      config:
        - subnet: 192.168.1.0/24

services:
  talos-cp1:
    networks:
      internal:
        ipv4_address: 10.5.0.11
        priority: 100  # Lower = less preferred for default route
      external:
        ipv4_address: 192.168.1.100
        priority: 1000  # Higher = preferred for default route
```

#### Network Priority

The `priority` field determines:
- Which network's gateway becomes the default route
- Higher priority = used for default gateway

```yaml
services:
  myservice:
    networks:
      primary:
        priority: 1000  # Default gateway from this network
      secondary:
        priority: 100   # Connected but not default route
```

#### Routing Behavior

- Each network adds an interface to the container
- Routes to each subnet go via respective interface
- Default gateway comes from highest-priority network
- Container can reach hosts on all connected networks

---

### Network Namespace Sharing

Containers can share network namespaces.

#### Share with Another Service

```yaml
services:
  main-app:
    image: nginx
    ports:
      - "80:80"

  sidecar:
    image: log-collector
    network_mode: service:main-app
    # Shares main-app's network namespace
    # Same IP, same interfaces, same ports
```

#### Share with External Container

```yaml
services:
  app:
    network_mode: container:existing-container-name
```

#### Use Cases

- Sidecar patterns (logging, monitoring)
- Shared localhost communication
- Network debugging

---

### External Networks

Connect to networks not managed by this Compose project.

#### Configuration

```yaml
networks:
  existing-network:
    external: true
    name: my-preexisting-network  # Actual Docker network name

services:
  app:
    networks:
      - existing-network
```

#### Use Cases

- Connecting to networks created by other tools
- Shared networks across multiple Compose projects
- Integration with non-Compose containers

---

### IPAM Configuration

IP Address Management for Docker networks.

#### Full IPAM Example

```yaml
networks:
  talos-network:
    driver: bridge
    ipam:
      driver: default
      config:
        - subnet: 10.5.0.0/24
          gateway: 10.5.0.1
          ip_range: 10.5.0.0/28  # Only .1-.15 auto-assigned
          aux_addresses:
            # Reserved addresses (never auto-assigned)
            reserved1: 10.5.0.240
            reserved2: 10.5.0.241
            reserved3: 10.5.0.242
            reserved4: 10.5.0.243
      options:
        foo: bar  # Driver-specific options
```

#### Static IP Assignment

```yaml
services:
  talos-cp1:
    networks:
      talos-network:
        ipv4_address: 10.5.0.11
        ipv6_address: "2001:db8::11"
```

#### Reserving LoadBalancer VIP Range

```yaml
networks:
  talos-network:
    ipam:
      config:
        - subnet: 10.5.0.0/24
          ip_range: 10.5.0.0/28  # Auto-assign only .0-.15
          aux_addresses:
            # Reserve .240-.255 for Cilium L2 LoadBalancer
            lb1: 10.5.0.240
            lb2: 10.5.0.241
            lb3: 10.5.0.242
            lb4: 10.5.0.243
            # ... up to .255
```

---

## Capabilities and Sysctls

### Network-Related Capabilities

```yaml
services:
  talos-cp1:
    cap_add:
      - NET_ADMIN   # Network interface configuration, iptables
      - NET_RAW     # Raw sockets (ping, etc.)
      - NET_BIND_SERVICE  # Bind to ports < 1024 as non-root
```

#### What NET_ADMIN Enables

- Configure network interfaces
- Modify routing tables
- Set up iptables rules (within container namespace)
- Manipulate network devices

#### Critical Note on iptables

| Container Mode | iptables Scope |
|----------------|----------------|
| Bridge network + NET_ADMIN | Container's namespace only |
| Host network + NET_ADMIN | Host's iptables (dangerous!) |
| Privileged | Full host access |

### Sysctls

```yaml
services:
  talos-cp1:
    sysctls:
      # Enable IP forwarding in container
      net.ipv4.ip_forward: "1"

      # Allow binding to non-local IPs (for VIPs)
      net.ipv4.ip_nonlocal_bind: "1"

      # Enable local routing (for hairpin NAT)
      net.ipv4.conf.all.route_localnet: "1"

      # ARP settings for Cilium L2
      net.ipv4.conf.all.arp_announce: "2"
      net.ipv4.conf.all.arp_ignore: "1"
```

### Privileged Mode

```yaml
services:
  talos-cp1:
    privileged: true
    # Grants ALL capabilities
    # Can manipulate host kernel/network
    # Required for nested virtualization (KubeVirt)
```

---

## Docker Daemon Integration

### Relevant Daemon Settings

```json
{
  "iptables": true,
  "ip-forward": true,
  "ip-masq": true,
  "userland-proxy": false,
  "default-address-pools": [
    {"base": "10.5.0.0/24", "size": 24}
  ],
  "live-restore": true
}
```

#### Setting Explanations

| Setting | Default | Description |
|---------|---------|-------------|
| `iptables` | true | Docker manages iptables rules |
| `ip-forward` | true | Enable IP forwarding on host |
| `ip-masq` | true | SNAT for container outbound traffic |
| `userland-proxy` | true | Use userspace proxy vs iptables for ports |
| `default-address-pools` | 172.x.x.x | Default subnets for new networks |
| `live-restore` | false | Keep containers running during daemon restart |

#### userland-proxy Impact

| Setting | Behavior |
|---------|----------|
| `true` | docker-proxy process handles port forwarding |
| `false` | Pure iptables DNAT (better performance) |

#### default-address-pools vs Compose IPAM

- Compose IPAM config **overrides** default-address-pools
- If no IPAM specified in compose, daemon defaults are used

---

## Compose Networking Limitations

### What Docker Compose CANNOT Do

| Requirement | Compose Capability | Solution |
|-------------|-------------------|----------|
| DNAT from host IP to internal VIP | ❌ NO | Host-level iptables (NixOS networking.nat) |
| Configure host routing table | ❌ NO | Host-level configuration |
| Forward to non-container IPs | ❌ NO | Host-level NAT |
| Create host iptables rules | ❌ NO | NixOS networking.firewall |
| macvlan host communication | ❌ NO | Host macvlan interface |

### What Docker Compose CAN Do

| Capability | Compose Support |
|------------|-----------------|
| Create bridge/macvlan/ipvlan networks | ✅ YES |
| Assign static container IPs | ✅ YES |
| Reserve IPs (aux_addresses) | ✅ YES |
| Multiple networks per container | ✅ YES |
| Network namespace sharing | ✅ YES |
| Port publishing (container ports only) | ✅ YES |
| Container capabilities (NET_ADMIN) | ✅ YES |
| Sysctls within container | ✅ YES |
| Network priority for default route | ✅ YES |

---

## Solution Comparison

### Option 1: Pure Bridge + Host NAT (Recommended)

```
External → Host iptables DNAT → Docker Bridge → VIP
```

**Compose**:
```yaml
networks:
  talos-network:
    driver: bridge
    ipam:
      config:
        - subnet: 10.5.0.0/24
          aux_addresses:
            lb_envoy: 10.5.0.241
```

**NixOS** (required):
```nix
networking.nat = {
  enable = true;
  externalInterface = "enp2s0";
  extraCommands = ''
    iptables -t nat -A nixos-nat-pre -i enp2s0 -p tcp --dport 80 -j DNAT --to-destination 10.5.0.241:80
    iptables -t nat -A nixos-nat-pre -i enp2s0 -p tcp --dport 443 -j DNAT --to-destination 10.5.0.241:443
  '';
};
```

**Pros**: Simple, well-understood, Cilium L2 works naturally
**Cons**: Requires host configuration

---

### Option 2: macvlan Direct Access

```
External → macvlan → Container (192.168.1.100)
                   → Cilium L2 VIPs (192.168.1.x)
```

**Compose**:
```yaml
networks:
  external:
    driver: macvlan
    driver_opts:
      parent: enp2s0
    ipam:
      config:
        - subnet: 192.168.1.0/24
          ip_range: 192.168.1.200/28

services:
  talos-cp1:
    networks:
      external:
        ipv4_address: 192.168.1.100
```

**Pros**: No NAT, direct L2 access
**Cons**: Host can't reach container, complex Cilium config

---

### Option 3: Host Network Mode

```
External → Host Network → Talos (shares host namespace)
                        → Cilium L2 VIPs on host interface
```

**Compose**:
```yaml
services:
  talos-cp1:
    network_mode: host
```

**Pros**: Simplest network path
**Cons**: No network isolation, port conflicts, complex Kubernetes networking

---

### Option 4: Dual Network (Bridge + macvlan)

```
External → macvlan (192.168.1.100) → Container
Internal → bridge (10.5.0.11) → Container
```

**Compose**:
```yaml
services:
  talos-cp1:
    networks:
      internal:
        ipv4_address: 10.5.0.11
        priority: 100
      external:
        ipv4_address: 192.168.1.100
        priority: 1000
```

**Pros**: Best of both worlds
**Cons**: Complex routing, macvlan limitations still apply

---

## Recommended Architecture

### For Konductor Platform

**Decision**: Option 1 (Bridge + Host NAT)

**Rationale**:
1. Cilium L2 works naturally on bridge network
2. Clean separation between Docker and host networking
3. NixOS networking.nat is declarative and persistent
4. No macvlan host-communication issues
5. Simplest mental model

### compose.yaml Configuration

```yaml
networks:
  talos-network:
    name: talos-network
    driver: bridge
    driver_opts:
      com.docker.network.bridge.name: "docker-dev"
    ipam:
      config:
        - subnet: 10.5.0.0/24
          gateway: 10.5.0.1
          ip_range: 10.5.0.0/28  # .0-.15 for containers
          aux_addresses:
            # Reserve Cilium L2 LoadBalancer pool
            lb_cilium_ingress: 10.5.0.240
            lb_envoy_gateway: 10.5.0.241
            lb_reserved_1: 10.5.0.242
            lb_coredns: 10.5.0.243

services:
  talos-cp1:
    image: ghcr.io/siderolabs/talos:v1.9.4
    container_name: talos-cp1
    hostname: cp1
    privileged: true
    networks:
      talos-network:
        ipv4_address: 10.5.0.11
    sysctls:
      net.ipv4.ip_forward: "1"
      net.ipv4.conf.all.arp_announce: "2"
      net.ipv4.conf.all.arp_ignore: "1"
    ports:
      # Local access only - external access via NixOS NAT
      - "127.0.0.1:6443:6443"   # Kubernetes API
      - "127.0.0.1:50000:50000" # Talos API
    volumes:
      - talos-var:/var
      - talos-etc:/etc/kubernetes
```

### NixOS Configuration

See: `KONDUCTOR.networking-firewall-nat-masquerade-nix-firewall-iptables-nftables-omnibus.md`

```nix
networking.nat = {
  enable = true;
  externalInterface = "enp2s0";
  extraCommands = ''
    # Forward external traffic to Envoy Gateway LoadBalancer VIP
    iptables -t nat -A nixos-nat-pre -i enp2s0 -p tcp --dport 80 -j DNAT --to-destination 10.5.0.241:80
    iptables -t nat -A nixos-nat-pre -i enp2s0 -p tcp --dport 443 -j DNAT --to-destination 10.5.0.241:443
    iptables -t nat -A nixos-nat-pre -i enp2s0 -p tcp --dport 22 -j DNAT --to-destination 10.5.0.241:22

    # Allow forwarding to Docker network
    iptables -A FORWARD -d 10.5.0.0/24 -o docker-dev -j ACCEPT
    iptables -A FORWARD -s 10.5.0.0/24 -i docker-dev -j ACCEPT

    # Masquerade return traffic
    iptables -t nat -A nixos-nat-post -s 10.5.0.0/24 ! -d 10.5.0.0/24 -j MASQUERADE
  '';
};

networking.firewall = {
  enable = true;
  allowedTCPPorts = [ 22 80 443 6443 50000 ];
  trustedInterfaces = [ "docker-dev" "docker0" ];
};
```

---

## References

### Docker Compose Documentation

- [Compose Networking](https://docs.docker.com/compose/networking/)
- [Network Configuration Reference](https://docs.docker.com/compose/compose-file/06-networks/)
- [Service Network Configuration](https://docs.docker.com/compose/compose-file/05-services/#networks)

### Docker Network Drivers

- [Bridge Network Driver](https://docs.docker.com/network/bridge/)
- [Macvlan Network Driver](https://docs.docker.com/network/macvlan/)
- [IPvlan Network Driver](https://docs.docker.com/network/ipvlan/)
- [Host Network Mode](https://docs.docker.com/network/host/)

### Related Documentation

- `KONDUCTOR.networking-firewall-nat-masquerade-nix-firewall-iptables-nftables-omnibus.md` - NixOS networking configuration
- `NIX_SHELL_ENVS_HOOKS_SHELL_PRE_POST_HELPERS_PATTERNS_IMPLEMENTATION.md` - Nix devshell patterns

### DeepWiki Queries

This document was informed by comprehensive queries to the docker/compose DeepWiki:
- Network drivers and driver_opts
- Port publishing mechanisms and limitations
- macvlan/ipvlan configuration and limitations
- Capabilities and sysctls for networking
- Compose networking scope vs host-level configuration

---

## Changelog

| Date | Change |
|------|--------|
| 2026-01-21 | Initial document created from DeepWiki research |
