# OpenCode Integration

OpenCode is a multi-provider AI coding agent that runs as a local service and connects to 75+ LLM providers. Konductor provides deep Neovim integration through the opencode.nvim plugin, enabling AI-assisted development without leaving your editor.

> **Package Sources**: Both `opencode` CLI and `opencode-nvim` are sourced from nixpkgs-unstable for latest features. These packages evolve rapidly.

## Quick Start

| Action | Keys | Description |
|--------|------|-------------|
| Toggle OpenCode | `<leader>oo` | Open/close the OpenCode panel |
| Ask anything | `<leader>oa` | Interactive prompt with completions |
| Review code | `go{motion}` | Review code using Vim motions |

From the dashboard, press `o` to open the OpenCode menu.

---

## Understanding OpenCode

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        Neovim                               │
│  ┌──────────┐  ┌──────────────────┐  ┌──────────────────┐  │
│  │ Explorer │  │      Editor      │  │    OpenCode      │  │
│  │  (left)  │  │     (center)     │  │     (right)      │  │
│  │          │  │                  │  │                  │  │
│  │ <leader>e│  │    Your code     │  │   <leader>oo     │  │
│  └──────────┘  └──────────────────┘  └──────────────────┘  │
│  ┌──────────────────────────────────────────────────────┐  │
│  │                    Terminal (bottom)                  │  │
│  │                      <leader>tt                       │  │
│  └──────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                              │
                              │ HTTP + SSE
                              ▼
                    ┌──────────────────┐
                    │  OpenCode Server │
                    │    (port 3232)   │
                    └──────────────────┘
                              │
                              ▼
                    ┌──────────────────┐
                    │   LLM Provider   │
                    │ (Anthropic, etc) │
                    └──────────────────┘
```

OpenCode runs as a local HTTP server. The Neovim plugin communicates with this server to send prompts and receive responses. Real-time updates arrive via Server-Sent Events (SSE), which trigger buffer reloads when files are modified.

### Context Injection

OpenCode understands your editor state through context placeholders:

| Placeholder | Expands To |
|-------------|------------|
| `@this` | Current selection, operator range, or cursor position |
| `@buffer` | Entire current buffer |
| `@visible` | Currently visible text in the viewport |
| `@diagnostics` | LSP errors and warnings |
| `@diff` | Uncommitted git changes |

These placeholders are automatically injected into prompts, giving the AI relevant context.

---

## Keybindings

### Primary Actions

| Keys | Action | Description |
|------|--------|-------------|
| `<leader>oo` | Toggle | Open or close OpenCode panel |
| `<leader>oa` | Ask | Interactive prompt with history and completions |
| `<leader>oS` | Select | Pick from available prompts |
| `<leader>oc` | Cycle Agent | Switch between agents (build, plan, general, explore) |

### Code Intelligence Prompts

All prompts work in normal mode (operates on `@this`) and visual mode (operates on selection).

| Keys | Prompt | What It Does |
|------|--------|--------------|
| `<leader>opr` | Review | Analyze code for correctness and readability |
| `<leader>ope` | Explain | Describe what the code does and why |
| `<leader>opd` | Document | Add documentation comments |
| `<leader>opf` | Fix | Fix LSP diagnostics |
| `<leader>opt` | Test | Generate tests with edge cases |
| `<leader>opo` | Optimize | Improve performance and readability |
| `<leader>opi` | Implement | Write code based on context and comments |
| `<leader>opR` | Refactor | Restructure without changing behavior |

### Session Management

| Keys | Action | Description |
|------|--------|-------------|
| `<leader>osn` | New Session | Start a fresh conversation |
| `<leader>osl` | List Sessions | Browse previous sessions |
| `<leader>oss` | Share | Generate a shareable link |
| `<leader>osu` | Undo | Revert last AI change (git-based) |
| `<leader>osr` | Redo | Restore reverted change |

### Navigation

| Keys | Action |
|------|--------|
| `<leader>o[` | Page up in conversation |
| `<leader>o]` | Page down in conversation |
| `<leader>o{` | Jump to first message |
| `<leader>o}` | Jump to last message |

### Vim Operator

The `go` prefix creates a Vim operator for OpenCode:

```
goap    Review paragraph
goiw    Review word
go3j    Review next 3 lines
gG      Review to end of file
```

This follows Vim grammar: `go` + motion. The operation defaults to "review" but can be configured.

### Quick Access

| Keys | Location | Action |
|------|----------|--------|
| `<leader>vo` | Vibe menu | Quick toggle (same as `<leader>oo`) |
| `o` | Dashboard | Open OpenCode menu |
| `<Esc><Esc>` | Terminal mode | Close OpenCode panel |

---

## Workflows

### Code Review

**Review a function:**
1. Position cursor inside the function
2. Press `goaf` (operator + "a function" text object)
3. OpenCode analyzes and provides feedback in the panel

**Review selected code:**
1. Visually select code with `v`, `V`, or `<C-v>`
2. Press `<leader>opr`
3. Review appears in OpenCode panel

### Fix Diagnostics

When LSP shows errors:
1. Press `<leader>opf`
2. OpenCode reads `@diagnostics` and suggests fixes
3. Review the suggested changes
4. Accept or modify as needed

### Generate Tests

1. Position cursor on function to test
2. Press `<leader>opt`
3. OpenCode generates tests covering:
   - Happy path
   - Edge cases
   - Error conditions

### Document Code

1. Select undocumented code
2. Press `<leader>opd`
3. OpenCode adds language-appropriate documentation

### Interactive Development

For open-ended questions:
1. Press `<leader>oa`
2. Type your question (supports `@` context references)
3. Press Enter
4. Continue the conversation naturally

---

## Configuration

### Theme Integration

Konductor automatically configures OpenCode with the **Catppuccin Frappe** theme to match Neovim. When you enter a Konductor devshell with IDE tools (dev, full, konductor), the theme is deployed to `~/.config/opencode/themes/catppuccin-frappe.json`.

The theme configuration ensures visual consistency:
- OpenCode TUI uses the same Catppuccin Frappe palette as Neovim
- Colors match the dashboard, syntax highlighting, and diff views
- Primary accent (mauve) matches the tmux accent color

**Theme source:** `src/config/opencode/catppuccin-frappe.json`

To use a different theme, run `/theme` in OpenCode and select from built-in themes, or create a custom theme in `~/.config/opencode/themes/`.

### OpenCode Server

OpenCode server is configured via `~/.config/opencode/opencode.json` or project-local `opencode.json`:

```json
{
  "provider": {
    "anthropic": {
      "options": {
        "apiKey": "{env:ANTHROPIC_API_KEY}"
      }
    }
  },
  "model": "anthropic/claude-sonnet-4"
}
```

### Neovim Plugin

The opencode.nvim plugin is configured via `vim.g.opencode_opts`. Valid keys:

| Key | Type | Description |
|-----|------|-------------|
| `port` | number | Server port (auto-detected if nil) |
| `auto_reload` | boolean | Reload buffers when opencode edits files |
| `auto_fallback_to_embedded` | boolean | Launch embedded terminal if no server found |
| `prompts` | table | Custom prompts with description and prompt text |
| `contexts` | table | Custom context providers |
| `input` | table | snacks.input options |
| `terminal` | table | snacks.terminal options |

Konductor sets these automatically. Override in your config if needed.

### Custom Agents

Create agents in `~/.config/opencode/agent/`:

```markdown
---
model: anthropic/claude-sonnet-4
temperature: 0.3
tools:
  bash: true
  edit: true
description: Security-focused code reviewer
---

You are a security expert. Review code for vulnerabilities,
focusing on OWASP Top 10, injection attacks, and auth issues.
```

### MCP Servers

Extend OpenCode with Model Context Protocol servers:

```json
{
  "mcp": {
    "my-tools": {
      "type": "local",
      "command": ["node", "path/to/server.js"]
    }
  }
}
```

### Permissions

Control what OpenCode can do:

```json
{
  "permission": {
    "edit": "ask",
    "bash": "ask",
    "webfetch": "deny"
  }
}
```

Options: `"ask"` (prompt each time), `"allow"` (auto-approve), `"deny"` (block)

---

## Statusline Integration

The statusline displays context based on the active panel:

| Context | Display |
|---------|---------|
| OpenCode panel active | ` OpenCode` |
| Claude Code panel active | `󰚩 Claude` |
| Regular file | Relative path |
| Terminal | Working directory |

---

## Events and Automation

OpenCode fires `OpencodeEvent` autocmds for workflow automation:

```lua
vim.api.nvim_create_autocmd("User", {
  pattern = "OpencodeEvent",
  callback = function(event)
    if event.data.type == "session.idle" then
      -- Agent finished responding
      vim.notify("OpenCode ready")
    end
  end,
})
```

Konductor automatically:
- Reloads buffers when OpenCode edits files
- Notifies when sessions become idle

---

## Comparison with Claude Code

Konductor includes both OpenCode and Claude Code. Choose based on your needs:

| Feature | OpenCode | Claude Code |
|---------|----------|-------------|
| Providers | 75+ (OpenAI, Anthropic, Google, local) | Anthropic only |
| Context injection | `@buffer`, `@diagnostics`, `@diff` | File references |
| Vim operators | `go{motion}` | None |
| Session sharing | Built-in web links | None |
| MCP support | Yes | No |
| Agents | Customizable | Fixed |

**Use OpenCode when:**
- You need multiple LLM providers
- You want Vim-native operator motions
- You need custom agents or MCP tools
- You want to share sessions

**Use Claude Code when:**
- You prefer Anthropic's Claude specifically
- You want the official Anthropic integration
- Simplicity is preferred over flexibility

Both tools are available simultaneously. Toggle between them:
- `<leader>oo` for OpenCode
- `<leader>vv` for Claude Code

---

## Troubleshooting

### OpenCode not responding

**Check if server is running:**
```bash
curl http://localhost:3232/health
```

**Start manually:**
```bash
opencode
```

### Connection refused

The plugin auto-starts an embedded OpenCode instance. If this fails:

1. Ensure `opencode` is in your PATH
2. Check for port conflicts on 3232
3. Review logs: `~/.local/share/opencode/logs/`

### Buffers not reloading

Ensure `autoread` is enabled (Konductor sets this by default):
```vim
:set autoread?
```

### Context not injecting

Verify the placeholder syntax in your prompt:
- Correct: `Review @this for issues`
- Incorrect: `Review @THIS for issues` (case-sensitive)

### Health check

Run the plugin health check:
```vim
:checkhealth opencode
```

---

## Reference

### Environment Variables

| Variable | Purpose |
|----------|---------|
| `ANTHROPIC_API_KEY` | Anthropic API authentication |
| `OPENAI_API_KEY` | OpenAI API authentication |
| `OPENCODE_CONFIG` | Custom config file path |
| `OPENCODE_CONFIG_DIR` | Directory for agents/commands |

### File Locations

| Path | Contents |
|------|----------|
| `~/.config/opencode/opencode.json` | Global configuration |
| `~/.config/opencode/themes/*.json` | Custom themes |
| `./opencode.json` | Project configuration |
| `./.opencode/themes/*.json` | Project-local themes |
| `~/.config/opencode/agent/*.md` | Custom agents |
| `~/.local/share/opencode/` | Sessions and data |

### Konductor Theme Files

| Path | Contents |
|------|----------|
| `src/config/opencode/catppuccin-frappe.json` | Catppuccin Frappe theme (source) |
| `src/config/opencode/default.nix` | Theme deployment configuration |

### Keybinding Summary

```
<leader>o        OpenCode menu (which-key)
<leader>oo       Toggle panel
<leader>oa       Ask (interactive)
<leader>oS       Select prompt
<leader>oc       Cycle agent
<leader>op*      Prompts (r/e/d/f/t/o/i/R)
<leader>os*      Session (n/l/s/u/r)
<leader>o[/]     Page up/down
<leader>o{/}     First/last message
go{motion}       Operator (review with motion)
```

---

## Further Reading

- [OpenCode Documentation](https://opencode.ai)
- [OpenCode GitHub](https://github.com/sst/opencode)
- [opencode.nvim](https://github.com/NickvanDyke/opencode.nvim)
- [Model Context Protocol](https://modelcontextprotocol.io)
