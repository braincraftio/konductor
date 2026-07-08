# Authelia / Envoy Gateway Integration Contract

Deployment-agnostic contract between the Konductor VM's per-user web services
and any identity plane fronting them. Written from upstream sources only —
no environment-specific state. Environments (Pulumi IaC, Ansible domain
config) conform **up** to this contract; the VM image implements its side
unconditionally and ships with authentication disabled until the
environment satisfies the preconditions.

Source anchors (verified against upstream clones, 2026-07):

- `authelia/authelia` `docs/content/integration/kubernetes/envoy/gateway.md`
- `authelia/authelia` `docs/content/configuration/security/access-control.md`
- `envoyproxy/gateway` `api/v1alpha1/ext_auth_types.go`
- `tsl0922/ttyd` `src/http.c`, `src/protocol.c`, `src/server.c`

## Architecture

```
client (any device)
  → edge (Cloudflare tunnel / LAN / any L4 path — untrusted)
    → Envoy Gateway (TLS termination for public hostnames)
      → SecurityPolicy extAuth ──► Authelia ──► LDAP (FreeIPA)
      │     403/302 on failure          │
      │     Remote-* headers on success ┘
      → HTTPRoute per user+service
        → Konductor VM port (7000 + UID−1000 for ttyd, 8000+… vscode, …)
          → ttyd -H remote-user  (or code-server --auth none)
            → TTYD_USER=<username> in the session environment
```

## Hostname and identity scheme

- Per-user, per-service hostnames: `<service>.<username>.konductor.<apex>`
  (e.g. `ttyd-rw.usrbinkat.konductor.example.com`).
- `<username>` is simultaneously: the FreeIPA `uid`, the VM POSIX username,
  the Authelia subject username, and a DNS label. The intersection of those
  constraints is the mandated charset:

  ```
  ^[a-z][a-z0-9-]{0,31}$
  ```

  Rationale: DNS labels forbid `_`; POSIX and LDAP allow it but Authelia
  applies **no normalization** to named-group matches and documents that
  non-alphanumeric values are not recommended (access-control.md §Named
  Regex Groups). FreeIPA (Ansible layer) MUST enforce this charset at user
  creation.
- Reserved VM UIDs: 1000 `kc2`, 1001 `kc2admin`, 1003 `runner`, 1004
  `forgejo`. Domain / cloud-init users allocate 1005+. The port formula
  `base + (UID − 1000)` depends on stable UIDs — FreeIPA POSIX UIDs MUST be
  identical on every host that mounts the same NFS home.

## Authelia contract

### Endpoint

Envoy integrations use the `ExtAuthz` authz implementation
(`integration/proxies/envoy.md` §Implementation):

```yaml
server:
  endpoints:
    authz:
      ext-authz:
        implementation: 'ExtAuthz'
```

Requests are authorized at `/api/authz/ext-authz/`.

### Session cookies

Access-control domains MUST be subdomains of the session cookie domain
(access-control.md lines 134-137). With per-user hostnames three labels
deep, the cookie domain is the apex (e.g. `example.com`), and
`authelia_url` lives on a sibling subdomain (e.g. `auth.example.com`):

```yaml
session:
  cookies:
    - domain: 'example.com'
      authelia_url: 'https://auth.example.com'
```

### Access control — per-user isolation in one rule

`domain_regex` named group `User` matches **Equals** against the
authenticated username (access-control.md §Named Regex Groups). This is the
entire multi-user authorization model:

```yaml
access_control:
  default_policy: 'deny'   # recommended default; everything unlisted is denied
  rules:
    # Web terminals + IDE: the user in the hostname must BE the
    # authenticated user. Captured group compared Equals to username.
    - domain_regex:
        - '^(ttyd-rw|vscode|restty|ghostty)\.(?P<User>[a-z][a-z0-9-]{0,31})\.konductor\.example\.com$'
      policy: 'two_factor'
```

Constraints inherited from upstream semantics:

- Named-group rules are **subject-reliant**: they require authentication to
  evaluate and MUST NOT use `policy: bypass` (Rule Matching Concept 2).
  Any genuine bypass rules (e.g. `OPTIONS` preflight) MUST precede them
  (Rule Matching Concept 1: first match wins, sequential order).
- Group-based escalation (e.g. admins reaching any user's terminal) is an
  explicit additional rule with `subject: 'group:...'` — never a widening
  of the regex.

## Envoy Gateway contract (SecurityPolicy)

Canonical shape from `authelia/authelia`
`integration/kubernetes/envoy/gateway.md`, field semantics from
`envoyproxy/gateway` `api/v1alpha1/ext_auth_types.go`:

```yaml
apiVersion: gateway.envoyproxy.io/v1alpha1
kind: SecurityPolicy
metadata:
  name: authelia-extauthz
spec:
  targetRefs:
    # Scope per HTTPRoute (per user+service), or per Gateway with bypass
    # rules in Authelia for unauthenticated hostnames.
    - group: gateway.networking.k8s.io
      kind: HTTPRoute
      name: <route>
  extAuth:
    headersToExtAuth:
      - 'accept'
      - 'cookie'          # REQUIRED — see invariant below
      - 'authorization'
      - 'proxy-authorization'
      - 'x-forwarded-proto'
    failOpen: false        # fail closed (also the API default)
    http:
      backendRefs:
        - name: authelia
          namespace: <authelia-ns>
          port: 80
      path: '/api/authz/ext-authz/'
      headersToBackend:
        - Remote-User
        - Remote-Groups
        - Remote-Name
        - Remote-Email
```

Invariants, with mechanism:

1. **`cookie` in `headersToExtAuth` is load-bearing.** For HTTP ext-auth
   services Envoy forwards only `Host, Method, Path, Content-Length,
   Authorization` by default (`ext_auth_types.go` lines 27-34). Authelia
   sessions are cookie-borne — omit `cookie` and every request is
   anonymous: browsers redirect-loop, WebSockets 403.
2. **`headersToBackend` MUST include `Remote-User`**, or ttyd's
   auth-header mode 407s every request (see VM contract below).
   `Remote-Groups/Name/Email` ride along for future in-VM consumption.
3. **`failOpen: false`** — an Authelia outage blocks access; it must never
   grant it.
4. **WebSocket semantics**: ext-authz evaluates the HTTP upgrade request.
   An established WS is NOT re-authorized when the Authelia session later
   expires; the connection lives until closed. Accepted for interactive
   terminals; revocation = delete the HTTPRoute or stop the user's service.
5. **Cross-namespace `backendRefs`** require a `ReferenceGrant` in
   Authelia's namespace (gateway.md §Reference Grant).
6. If ext-auth-added headers ever participate in route matching, set
   `recomputeRoute: true` (`ext_auth_types.go` lines 59-65). Not needed for
   hostname-based routing.
7. Timeout defaults to 10s; `statusOnError` defaults to 403
   (`ext_auth_types.go`).

## Konductor VM contract (implemented in this repo)

Configuration surface — `/var/lib/konductor/services.toml`:

```toml
[ttyd]
# OFF by default. Enable ONLY after the SecurityPolicy is live —
# with -H set, ttyd returns 407 for every request lacking the header.
auth_header = "remote-user"
```

Mechanism chain (all verified in ttyd source):

- Orchestrator (`konductor-init.service`) writes
  `KONDUCTOR_TTYD_AUTH_HEADER=remote-user` to the service EnvironmentFile;
  the `ttyd-konductor` wrapper appends `-H remote-user`.
- HTTP without the header → `407 Proxy Authentication Required`
  (`http.c` `check_auth`); WebSocket without it → connection refused
  (`protocol.c` `LWS_CALLBACK_FILTER_PROTOCOL_CONNECTION`).
- ttyd lowercases the configured name and matches the header
  case-insensitively at the LWS layer (`server.c` lines 583-588) —
  `Remote-User` from Authelia matches `remote-user`.
- The header VALUE (username) is exported as `TTYD_USER` into the session
  environment (`protocol.c` `build_env`) — in-VM identity attribution.
- `--check-origin` is ON by default (wrapper): WebSocket `Origin` must
  equal `Host`. Same-origin browser traffic through any proxy chain that
  preserves `Host` passes; cross-origin drive-by WS is refused.
- code-server runs `--auth none` by design: the gateway is its sole
  authenticator. It MUST NOT be reachable except via the gateway (next
  section).

### Enforcement invariant — port reachability

ttyd **trusts** the auth header. The scheme is sound iff ports
7000-10499 are reachable exclusively from the gateway data plane.
A LAN client that can reach `vm:7005` directly can send
`Remote-User: victim` itself.

REQUIRED before any environment enables `auth_header`:

- VM side (implemented): set `[network].trusted_source_cidr = "<gateway-cidr>"`
  in services.toml — every per-user service's nftables accept rule becomes
  `ip saddr <cidr> tcp dport <port> accept`. The orchestrator warns loudly
  if `auth_header` is enabled without it.
- Environment side: the gateway egress CIDR toward the VM MUST be stable
  and documented by the IaC layer.

## Ansible / FreeIPA contract

- Enforce username charset `^[a-z][a-z0-9-]{0,31}$` at provisioning.
- Publish stable POSIX UIDs (1005+) — identical across NFS home consumers.
- Provide the LDAP backend Authelia binds to; groups intended for Authelia
  `group:` subjects and `Remote-Groups` MUST be POSIX groups visible via
  that bind.
- 2FA enrollment policy is the identity plane's decision; this contract
  only fixes `two_factor` as the policy for terminal/IDE routes.

## Activation sequence (per environment)

1. Deploy/verify Authelia (`ext-authz` endpoint, session cookie domain,
   access-control rules above) and LDAP bind to FreeIPA.
2. Apply SecurityPolicy to ONE user's ttyd HTTPRoute.
3. Verify from outside: unauthenticated `curl -I https://ttyd-rw.<u>...`
   → 302 to `auth.<apex>`; authenticated browser session reaches the
   terminal; a SECOND user's session against the first user's hostname
   → 403.
4. Flip the VM: set `[ttyd].auth_header = "remote-user"` and
   `[network].trusted_source_cidr = "<gateway-cidr>"` in services.toml —
   the config watcher reloads konductor-init automatically.
5. Verify enforcement: direct `curl -k https://<vm-lan-ip>:70xx/` → 407;
   via gateway → 200; `echo $TTYD_USER` inside the web terminal prints the
   authenticated username.
6. Roll out to remaining routes/services.

Rollback: remove `auth_header` from services.toml (watcher reloads;
services revert to gateway-only trust), then detach the SecurityPolicy.
