---
name: opencode-clients
description: >-
  Operate OpenCode V2 from another agent or application using its CLI, HTTP API, and TypeScript
  client. Use for noninteractive runs, explicit session targeting, cross-session messages, execution
  monitoring, service authentication, skill discovery, and diagnosing client/server configuration or
  environment mismatches.
---

# OpenCode clients

## Operating model

OpenCode is a client/server system. The TUI, CLI, and API clients connect to a server that owns
sessions, configuration, plugins, permissions, and execution. Closing a TUI does not restart that
server. A session ID identifies a conversation; a location identifies the directory and optional
workspace whose configuration and tools apply.

Use the installed V2 binary's `--help`, the target server's API contract, and matching upstream
source. Do not mix V1 routes or SDK examples into V2 requests. The public API contains experimental
endpoints; verify their schemas before using them.

Failure modes to check first: a correct request targeting the wrong server or directory; a
misspelled session ID creating a new conversation; a queued prompt mistaken for a completed answer;
a permission request mistaken for a hung model; a new shell environment mistaken for the running
server's environment; sensitive values exposed by config diagnostics.

## Establish the target

```bash
opencode --version
opencode api --help
opencode service status
opencode api get /api/info
```

Use the shell tool's working-directory parameter for project-local commands. Do not rely on a
previous command changing directories. For location-scoped API calls, pass the absolute directory
explicitly and inspect the response's `location`:

```bash
opencode api skill.list --param "location[directory]=$PWD"
```

`--param` belongs to operation-ID requests. With raw HTTP method/path requests, encode query
parameters into the URL instead. Do not assume a `--param` supplied with a raw path was applied.
URL-encode directory values, including spaces and reserved characters.

Local `opencode api` uses the same service discovery and authentication as the CLI. For a remote or
dedicated server, retain the explicit `--server` URL and its authentication context for every
request. Never hardcode an observed localhost port into reusable automation.

## Noninteractive CLI execution

```bash
opencode run --help
opencode session list --format json
```

Use `run` rather than opening an interactive TUI in a shell tool:

```bash
opencode run --format json "Explain the current repository structure without changing files."
```

`--format json` is machine-oriented output; inspect its records rather than assuming the entire
stream is one JSON object. Preserve stderr and the process exit status.

To continue a known session, first retrieve it and check its identity and location:

```bash
opencode api session.get --param "sessionID=$SESSION_ID"
opencode run --session "$SESSION_ID" --format json "Report the remaining work."
```

`run --session` can create the supplied ID when it does not exist. Do not use it as an existence
check. Avoid `--continue` in multi-session automation: it selects the last session, not necessarily
the intended one. `--fork` forks before continuing. Discover available agents and models before
selecting `--agent` or `--model provider/model#variant`; never invent IDs.

`--auto` auto-approves permissions not explicitly denied. Use it only when that permission policy is
intended, not as a remedy for an unexplained wait. Creating sessions or sending prompts can trigger
tool execution and provider charges; keep the task and allowed scope explicit.

## HTTP session workflow

Use `opencode api` for small requests, or a typed client for a sustained integration. The examples
below use V2 `text`, not V1 message-part payloads. Set `PROJECT_DIR` to the absolute target
directory and `TASK` to the complete task before running them.

Create a session at an explicit location and retain the returned `data.id`:

```bash
payload=$(jq -n --arg directory "$PROJECT_DIR" \
  '{title: "Agent task", location: {directory: $directory}}')
opencode api post /api/session --data "$payload"
```

Send a prompt to that exact ID:

```bash
payload=$(jq -n --arg text "$TASK" '{text: $text, delivery: "queue"}')
opencode api session.prompt --param "sessionID=$SESSION_ID" --data "$payload"
```

Use JSON serialization for dynamic text; never interpolate arbitrary prompt text into JSON. The
prompt response confirms durable admission to the inbox, not completion. `delivery` supports `queue`
and `steer`; choose deliberately when communicating with an active session. `resume: false` admits
input without scheduling execution. Do not send repeated prompts merely because the first request
returned before an answer appeared.

```bash
opencode api post "/api/experimental/session/$SESSION_ID/wait"
opencode api get "/api/session/$SESSION_ID/message"
```

The wait endpoint waits for the agent loop to become idle. Idle alone does not prove success:
inspect messages, execution errors, pending permissions/forms, and the requested deliverable. Use
the current message-list schema's pagination controls for long histories. On a timeout or
disconnect, inspect the inbox and messages before retrying a mutation; admission may have succeeded.

For cross-session work, discover and retrieve the recipient before posting. Titles are not unique.
Do not interrupt, delete, move, or change the model of another active session as incidental cleanup.
Session deletion also deletes child sessions. Report the target ID and actual result.

## TypeScript clients

The network client is `@opencode/client`; the in-process SDK is a different integration. Use the
dependency version and installation mechanism owned by the consuming project.

For an authenticated local service connection:

```typescript
import { OpenCode } from '@opencode/client';
import { Service } from '@opencode/client/service';

const endpoint = await Service.ensure();
const client = OpenCode.make({
  baseUrl: endpoint.url,
  headers: Service.headers(endpoint),
});
const info = await client.server.info();
console.log(info);
```

`Service.discover()` finds a healthy registered endpoint without starting a process;
`Service.ensure()` may start one. Browser clients use an explicit server and authorized headers, not
the Node-only service module. Verify installed generated method signatures before building session
workflows. Client methods unwrap responses: the documented session-create result exposes
`session.id`, whereas raw HTTP returns `data.id`.

Event subscriptions are async iterables and live-only: no replay or automatic reconnection. Consume
the subscription before relying on events, filter by session/location, and resynchronize from
durable state after disconnects. Do not infer that an unobserved event never occurred. Use
cancellation and bounded request timeouts, handle rejected operations, and close only
subscriptions/processes owned by the caller.

## Configuration and service lifecycle

For file edits at existing paths, OpenCode watches configuration; `/reload` forces a reload. A
different `OPENCODE_CONFIG` path is a process-environment change. `direnv allow` updates the shell,
not an already-running background server. With Nix, each rebuilt configuration has a new immutable
store path, so reconnecting the TUI alone can retain the old configuration.

Compare the shell's `OPENCODE_CONFIG` with the paths and skill entries in the server's config
response. `opencode debug config` can resolve environment substitutions, including credentials
embedded in command arguments. Inspect only the required fields and redact secrets before logging.

When the server demonstrably retains the old startup environment, restart it from the refreshed
shell. This affects every connected client and may cancel the shell call requesting the restart.
After reconnection, verify server health, the active config path, and location-scoped skill
discovery. Do not repeatedly restart because a tool call was cancelled during the first restart.

`--standalone` gives a private server lifecycle, not a guarantee of isolated credentials, database,
or configuration. For a multi-request loader check, use one dedicated server across requests: an
initial empty skill response can precede plugin initialization. Check `/api/plugin` and then query
skills once initialization is established; avoid tight polling loops.

## Authentication and diagnosis

Keep credentials out of skill files, source control, command examples, and diagnostic output. Use
service discovery or the deployment's configured authentication. Do not dump service registration
files or complete environments to discover one field. Remote MCP OAuth and model provider
authentication are separate from authenticating the API client to the OpenCode server.

Check failures in order: target server/version, location/session identity, loaded config, plugin
state, authentication, pending permissions/forms, execution errors. A successful HTTP status or
process launch is not evidence that the requested work completed. A truncated JSON response is not a
valid schema: use a complete authenticated HTTP response or matching source, and pagination where
supported, rather than guessing the missing structure.

## Authoritative references

- CLI: <https://opencode.ai/v2/docs/cli>
- HTTP API: <https://opencode.ai/v2/docs/api>
- TypeScript client: <https://opencode.ai/v2/docs/build/client>
- Configuration: <https://opencode.ai/v2/docs/config>
- Troubleshooting: <https://opencode.ai/v2/docs/troubleshooting>

For exact deployed behavior, read the installed CLI help and server contract first. Upstream source
places routes in `packages/protocol/src/groups/`, request types in `packages/schema/src/`, and CLI
commands in `packages/cli/src/`. Public documentation can be newer than the deployed build.
