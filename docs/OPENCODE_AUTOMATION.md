# OpenCode Automation Guide

This document covers the extensibility and automation systems in OpenCode, including
skills, commands, custom tools, plugins, and agents.

## Overview

OpenCode provides multiple extension points for automation:

| Concept | Purpose | Location | Trigger |
|---------|---------|----------|---------|
| **Skill** | Reusable instructions agents load on-demand | `SKILL.md` files | Agent calls `skill()` tool |
| **Command** | Custom prompts for repetitive tasks | Markdown or JSON | User types `/name` in TUI |
| **Tool** | Functions the LLM can call | TypeScript/JavaScript | LLM decides to invoke |
| **Plugin** | Event hooks and lifecycle interception | TypeScript/JavaScript | Automatic on events |
| **Agent** | Specialized AI assistants | Markdown or JSON | User switches or `@mentions` |

---

## Skills

Skills are reusable instruction sets that agents discover and load on-demand via the
native `skill` tool. They provide specialized knowledge for specific tasks.

### Locations

Skills are discovered from these paths (searched in order):

```
.opencode/skill/<name>/SKILL.md          # Project-level
~/.config/opencode/skill/<name>/SKILL.md # Global
.claude/skills/<name>/SKILL.md           # Claude-compatible (project)
~/.claude/skills/<name>/SKILL.md         # Claude-compatible (global)
```

For project paths, OpenCode walks up from `cwd` to the git worktree root.

### Structure

Each `SKILL.md` must have YAML frontmatter with required fields:

```markdown
---
name: git-release
description: Create consistent releases and changelogs
license: MIT
compatibility: opencode
metadata:
  audience: maintainers
  workflow: github
---

## What I do

- Draft release notes from merged PRs
- Propose a version bump
- Provide a copy-pasteable `gh release create` command

## When to use me

Use this when you are preparing a tagged release.
Ask clarifying questions if the target versioning scheme is unclear.
```

### Frontmatter Fields

| Field | Required | Description |
|-------|----------|-------------|
| `name` | Yes | Skill identifier (must match directory name) |
| `description` | Yes | Brief explanation (1-1024 chars) |
| `license` | No | License identifier |
| `compatibility` | No | Compatibility information |
| `metadata` | No | String-to-string map for additional data |

### Name Validation

The `name` field must:

- Be 1-64 characters
- Be lowercase alphanumeric with single hyphen separators
- Not start or end with `-`
- Not contain consecutive `--`
- Match the containing directory name

Regex: `^[a-z0-9]+(-[a-z0-9]+)*$`

### Permissions

Control skill access in `opencode.json`:

```json
{
  "permission": {
    "skill": {
      "pr-review": "allow",
      "internal-*": "deny",
      "experimental-*": "ask",
      "*": "allow"
    }
  }
}
```

| Permission | Behavior |
|------------|----------|
| `allow` | Skill loads immediately |
| `deny` | Skill hidden from agent, access rejected |
| `ask` | User prompted for approval |

Wildcards supported: `internal-*` matches `internal-docs`, `internal-tools`, etc.

### Per-Agent Override

In agent frontmatter:

```yaml
---
permission:
  skill:
    "documents-*": "allow"
---
```

Or in `opencode.json` for built-in agents:

```json
{
  "agent": {
    "plan": {
      "permission": {
        "skill": {
          "internal-*": "allow"
        }
      }
    }
  }
}
```

### Disable Skill Tool

For agents that should not use skills:

```yaml
---
tools:
  skill: false
---
```

---

## Commands

Commands are custom prompts triggered with `/name` in the TUI. They extend built-in
commands like `/init`, `/undo`, `/redo`, `/share`, `/help`.

### Locations

```
.opencode/command/<name>.md          # Project-level
~/.config/opencode/command/<name>.md # Global
opencode.json → "command" field      # JSON config
```

The filename becomes the command name (e.g., `test.md` → `/test`).

### Markdown Format

```markdown
---
description: Run tests with coverage
agent: build
model: anthropic/claude-3-5-sonnet-20241022
subtask: false
---

Run the full test suite with coverage report and show any failures.
Focus on the failing tests and suggest fixes.
```

### JSON Format

In `opencode.json`:

```json
{
  "command": {
    "test": {
      "template": "Run the full test suite with coverage report.",
      "description": "Run tests with coverage",
      "agent": "build",
      "model": "anthropic/claude-3-5-sonnet-20241022"
    },
    "component": {
      "template": "Create a React component named $ARGUMENTS with TypeScript.",
      "description": "Create a new component"
    }
  }
}
```

### Options

| Option | Required | Description |
|--------|----------|-------------|
| `template` | Yes | Prompt sent to LLM |
| `description` | No | Shown in TUI command list |
| `agent` | No | Which agent executes (defaults to current) |
| `model` | No | Override model for this command |
| `subtask` | No | Force subagent invocation |

### Template Variables

#### Arguments

```markdown
Create a component named $ARGUMENTS with TypeScript.
```

Run: `/component Button` → `$ARGUMENTS` becomes `Button`

#### Positional Parameters

```markdown
Create file $1 in directory $2 with content: $3
```

Run: `/create-file config.json src "{ \"key\": \"value\" }"`

- `$1` → `config.json`
- `$2` → `src`
- `$3` → `{ "key": "value" }`

#### Shell Output

Inject command output with `` !`command` ``:

```markdown
Here are the current test results:
!`npm test`

Based on these results, suggest improvements.
```

#### File References

Include file content with `@path`:

```markdown
Review the component in @src/components/Button.tsx.
Check for performance issues.
```

---

## Custom Tools

Custom tools are functions the LLM can call during conversations, extending built-in
tools like `read`, `write`, `bash`, `glob`, `grep`.

### Locations

```
.opencode/tool/<name>.ts          # Project-level
~/.config/opencode/tool/<name>.ts # Global
```

The filename becomes the tool name.

### Basic Structure

```typescript
import { tool } from "@opencode-ai/plugin"

export default tool({
  description: "Query the project database",
  args: {
    query: tool.schema.string().describe("SQL query to execute"),
  },
  async execute(args) {
    // Your logic here
    return `Executed query: ${args.query}`
  },
})
```

### Arguments with Zod

`tool.schema` is an alias for [Zod](https://zod.dev):

```typescript
args: {
  name: tool.schema.string().describe("User name"),
  age: tool.schema.number().optional().describe("User age"),
  tags: tool.schema.array(tool.schema.string()).describe("Tags"),
}
```

Or import Zod directly:

```typescript
import { z } from "zod"

export default {
  description: "Tool description",
  args: {
    param: z.string().describe("Parameter"),
  },
  async execute(args, context) {
    return "result"
  },
}
```

### Context Object

The `execute` function receives context about the current session:

```typescript
async execute(args, context) {
  const {
    sessionID,   // Current session ID
    messageID,   // Current message ID
    agent,       // Current agent name
    abort,       // AbortSignal for cancellation
    callID,      // Unique call identifier
    ask,         // Function for permission requests
    metadata,    // Function to update tool call metadata
  } = context

  return `Agent: ${agent}, Session: ${sessionID}`
}
```

### Multiple Tools Per File

Export multiple named tools:

```typescript
import { tool } from "@opencode-ai/plugin"

export const add = tool({
  description: "Add two numbers",
  args: {
    a: tool.schema.number(),
    b: tool.schema.number(),
  },
  async execute(args) {
    return args.a + args.b
  },
})

export const multiply = tool({
  description: "Multiply two numbers",
  args: {
    a: tool.schema.number(),
    b: tool.schema.number(),
  },
  async execute(args) {
    return args.a * args.b
  },
})
```

Creates tools: `math_add` and `math_multiply` (from `math.ts`).

### Shell Execution

Use Bun's shell API for subprocess execution:

```typescript
import { tool } from "@opencode-ai/plugin"

export default tool({
  description: "Add two numbers using Python",
  args: {
    a: tool.schema.number(),
    b: tool.schema.number(),
  },
  async execute(args) {
    const result = await Bun.$`python3 .opencode/tool/add.py ${args.a} ${args.b}`.text()
    return result.trim()
  },
})
```

### Tool Permissions

Configure in `opencode.json`:

```json
{
  "permission": {
    "*": "ask",
    "bash": "allow",
    "edit": "deny",
    "my-custom-tool": "allow"
  }
}
```

Granular patterns for specific inputs:

```json
{
  "permission": {
    "bash": {
      "*": "ask",
      "git *": "allow",
      "npm *": "allow",
      "rm *": "deny"
    }
  }
}
```

---

## Plugins

Plugins hook into OpenCode events and lifecycle to customize behavior, add tools,
or integrate with external services.

### Locations

```
.opencode/plugin/<name>.ts          # Project-level
~/.config/opencode/plugin/<name>.ts # Global
opencode.json → "plugin" array      # npm packages
```

### npm Plugins

```json
{
  "plugin": [
    "opencode-helicone-session",
    "opencode-wakatime",
    "@my-org/custom-plugin"
  ]
}
```

Packages are auto-installed via Bun, cached in `~/.cache/opencode/node_modules/`.

### Load Order

1. Global config (`~/.config/opencode/opencode.json`)
2. Project config (`opencode.json`)
3. Global plugin directory (`~/.config/opencode/plugin/`)
4. Project plugin directory (`.opencode/plugin/`)

### Basic Structure

```typescript
import type { Plugin } from "@opencode-ai/plugin"

export const MyPlugin: Plugin = async ({ project, client, $, directory, worktree }) => {
  console.log("Plugin initialized!")

  return {
    // Hook implementations
  }
}
```

#### Context Object

| Property | Description |
|----------|-------------|
| `project` | Current project information |
| `directory` | Current working directory |
| `worktree` | Git worktree path |
| `client` | OpenCode SDK client |
| `$` | Bun shell API |

### Available Hooks

#### Tool Hooks

```typescript
return {
  "tool.execute.before": async (input, output) => {
    // Modify args or prevent execution
    if (input.tool === "read" && output.args.filePath.includes(".env")) {
      throw new Error("Do not read .env files")
    }
  },
  "tool.execute.after": async (input, output) => {
    // React to tool completion
  },
}
```

#### Event Hook

Subscribe to system events:

```typescript
return {
  event: async ({ event }) => {
    if (event.type === "session.idle") {
      await $`osascript -e 'display notification "Done!" with title "opencode"'`
    }
  },
}
```

Available events:

- **Session**: `session.created`, `session.idle`, `session.error`, `session.compacted`, `session.deleted`, `session.updated`, `session.status`, `session.diff`
- **Message**: `message.updated`, `message.removed`, `message.part.updated`, `message.part.removed`
- **File**: `file.edited`, `file.watcher.updated`
- **Tool**: `tool.execute.before`, `tool.execute.after`
- **Permission**: `permission.updated`, `permission.replied`
- **LSP**: `lsp.updated`, `lsp.client.diagnostics`
- **TUI**: `tui.prompt.append`, `tui.command.execute`, `tui.toast.show`
- **Other**: `command.executed`, `installation.updated`, `server.connected`, `todo.updated`

#### Chat Hooks

```typescript
return {
  "chat.message": async (input, output) => {
    // Called on new message
  },
  "chat.params": async (input, output) => {
    // Modify LLM parameters (temperature, topP, etc.)
  },
}
```

#### Compaction Hook

Customize session compaction:

```typescript
return {
  "experimental.session.compacting": async (input, output) => {
    // Inject additional context
    output.context.push(`
## Custom Context
- Current task status
- Important decisions made
- Files being actively worked on
`)
  },
}
```

Or replace the entire prompt:

```typescript
return {
  "experimental.session.compacting": async (input, output) => {
    output.prompt = `
You are generating a continuation prompt.
Summarize the current task, files being modified, and next steps.
`
  },
}
```

#### Adding Tools via Plugin

```typescript
import { type Plugin, tool } from "@opencode-ai/plugin"

export const CustomToolsPlugin: Plugin = async (ctx) => {
  return {
    tool: {
      mytool: tool({
        description: "Custom tool from plugin",
        args: {
          foo: tool.schema.string(),
        },
        async execute(args) {
          return `Hello ${args.foo}!`
        },
      }),
    },
  }
}
```

### Dependencies

Local plugins can use npm packages. Create `.opencode/package.json`:

```json
{
  "dependencies": {
    "shescape": "^2.1.0"
  }
}
```

OpenCode runs `bun install` at startup.

### Logging

Use structured logging instead of `console.log`:

```typescript
await client.app.log({
  service: "my-plugin",
  level: "info",  // debug, info, warn, error
  message: "Plugin initialized",
  extra: { foo: "bar" },
})
```

---

## Agents

Agents are specialized AI assistants with custom prompts, models, and tool permissions.

### Types

- **Primary Agents**: Main assistants you interact with directly (switch with `Tab`)
- **Subagents**: Specialized assistants invoked by primary agents or via `@mention`

Built-in agents:

- `build` (primary) - Full access, default agent
- `plan` (primary) - Read-only planning
- `general` (subagent) - General purpose
- `explore` (subagent) - Codebase exploration

### Locations

```
.opencode/agent/<name>.md          # Project-level
~/.config/opencode/agent/<name>.md # Global
opencode.json → "agent" field      # JSON config
```

### Markdown Format

```markdown
---
description: Code review specialist
mode: subagent
model: anthropic/claude-3-5-sonnet-20241022
temperature: 0.3
maxSteps: 10
tools:
  bash: false
  edit: false
permission:
  skill:
    "review-*": "allow"
---

You are a code review specialist. Focus on:
- Code quality and best practices
- Security vulnerabilities
- Performance issues
- Maintainability

Provide constructive feedback with specific suggestions.
```

### JSON Format

In `opencode.json`:

```json
{
  "agent": {
    "reviewer": {
      "description": "Code review specialist",
      "mode": "subagent",
      "model": "anthropic/claude-3-5-sonnet-20241022",
      "temperature": 0.3,
      "prompt": ".opencode/agent/reviewer-prompt.md",
      "tools": {
        "bash": false,
        "edit": false
      },
      "permission": {
        "skill": {
          "review-*": "allow"
        }
      }
    }
  }
}
```

### Options

| Option | Description |
|--------|-------------|
| `description` | Brief explanation (required) |
| `mode` | `primary`, `subagent`, or `all` (default) |
| `model` | Override LLM model (`provider/model-id`) |
| `prompt` | Path to system prompt file |
| `temperature` | Creativity (0.0 focused → 1.0 creative) |
| `maxSteps` | Max agentic iterations before text-only response |
| `tools` | Enable/disable specific tools |
| `permission` | Tool and skill permissions |

### Creating Agents

Interactive creation:

```bash
opencode agent create
```

This guides you through:
1. Save location selection
2. Description input
3. System prompt generation
4. Tool access configuration

---

## Directory Structure Example

```
.opencode/
├── agent/
│   └── reviewer.md
├── command/
│   ├── test.md
│   └── deploy.md
├── plugin/
│   ├── notifications.ts
│   └── env-protection.ts
├── skill/
│   └── git-release/
│       └── SKILL.md
├── tool/
│   ├── database.ts
│   └── deploy.ts
└── package.json          # Dependencies for plugins/tools
```

---

## References

- [OpenCode Skills Documentation](https://opencode.ai/docs/skills)
- [OpenCode Commands Documentation](https://opencode.ai/docs/commands)
- [OpenCode Custom Tools Documentation](https://opencode.ai/docs/custom-tools)
- [OpenCode Plugins Documentation](https://opencode.ai/docs/plugins)
- [OpenCode Agents Documentation](https://opencode.ai/docs/agents)
- [OpenCode Permissions Documentation](https://opencode.ai/docs/permissions)
