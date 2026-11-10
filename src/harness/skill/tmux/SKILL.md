---
name: tmux
description: >-
  tmux workspace integration for pane observation, command execution, and window management. Use
  with TMUX set for long tasks, build monitoring, logs, and visible command execution. Not for
  simple inline commands.
---

# tmux — workspace-aware terminal collaboration

## Ownership boundary

Each harness session owns only the windows it creates under `harness:<session-id>:<purpose>`. Use a
unique session identifier, retain it for the session, and never adopt another session's windows. The
user owns everything else.

- Create, split, and destroy panes **only** inside this session's windows
- The user's windows and panes are **read-only structure** — observe with `capture-pane`, act with
  `send-keys`, never `split-window` / `new-window` / `kill-pane` / `swap-pane` targeting them
- If the user asks you to mutate their layout, comply — user discretion overrides

## Primitives

### Observe: what exists

```bash
tmux list-panes -a -F '#{session_name}:#{window_index}.#{pane_index} #{window_name} #{pane_current_command} #{pane_current_path}'
```

Run this to learn the workspace shape before acting on any pane. Also useful:

```bash
tmux list-windows -a -F '#{session_name}:#{window_index} #{window_name}'
tmux list-panes -t <session>:<window> -F '#{pane_index} #{pane_width}x#{pane_height} #{pane_current_command}'
```

### Observe: what a pane shows

```bash
tmux capture-pane -t <target> -p          # last screenful
tmux capture-pane -t <target> -p -S -50   # last 50 lines
```

Use to check build progress, test results, log output, service status — anything visible in another
pane without asking the user to look and report.

**Neovim panes**: `capture-pane` on a neovim pane returns rendered TUI output (statusline, line
numbers, gutter icons). Useful for seeing what file is open and the cursor position. Not useful for
reading file contents — use the Read tool.

### Act: run a command in a pane

```bash
tmux send-keys -t <target> "command" Enter
```

Before every `send-keys` to a **user** pane, state in the conversation what you are about to send
and which pane. The user must never be surprised by keystrokes appearing in their terminal.

`send-keys` to this session's own pane needs no announcement.

### Act: create a session-owned window

```bash
tmux new-window -n 'harness:<session-id>:<purpose>'
```

Use descriptive purposes: `build`, `test`, `logs`, or `agent-0`.

## Targeting: always use session:index

Window names are ambiguous — especially with grouped sessions (konductor uses `new-session -t` for
multi-device roaming). A `new-window` appears in **all** grouped sessions. Target panes and windows
by `session_name:window_index.pane_index`:

```bash
# Discover the index after creating a window
tmux list-windows -a -F '#{session_name}:#{window_index} #{window_name}'

# Target by session:index, not window name
tmux send-keys -t k9-3:2 "command" Enter
tmux capture-pane -t k9-3:2.1 -p
tmux kill-window -t k9-3:2
```

Never target by bare window name — tmux resolves the name as a session name first and errors.

## Rerun hygiene: clear before reuse

Before rerunning a command in an owned pane, send `clear` first. Without this, `capture-pane` reads
stale output from the previous run and conclusions are ambiguous.

```bash
tmux send-keys -t k9-3:2 'clear' Enter
tmux send-keys -t k9-3:2 'nix flake check; echo "EXIT: $?"' Enter
```

Append a sentinel like `echo "EXIT: $?"` or `echo "DONE"` so `capture-pane` can unambiguously detect
completion.

## When to use session-owned windows vs inline shell execution

| Scenario                                           | Where                      |
| -------------------------------------------------- | -------------------------- |
| Quick command, output consumed immediately         | Inline Bash tool           |
| Long-running build or test suite                   | Session-owned build window |
| Tailing logs while working on something else       | Session-owned logs window  |
| Command the user should see executed transparently | `send-keys` to user pane   |
| Subagent doing visible work                        | Subagent-owned window      |

## Usage patterns

- **Build-then-check**: start build in the session-owned build window, continue conversation,
  `capture-pane` periodically to check completion
- **Transparent execution**: `send-keys` a command to a user pane so they see it run in context —
  auditable by default
- **Log monitoring**: `capture-pane` a log-tailing pane to extract specific lines without the user
  copy-pasting
- **Agent observability**: subagents work in their own windows — the user can switch to them and
  watch, building trust through visibility
- **Open file in neovim**: `send-keys` with `:e <path>` to the neovim pane (only when neovim is in
  NORMAL mode — check the mode line via `capture-pane` first)

## Neovim integration

When `$NVIM` is set (the harness running inside neovim's `:terminal`), prefer the neovim RPC socket
over tmux `send-keys` for editor interaction:

```bash
nvim --server "$NVIM" --remote-expr 'getcwd()'
nvim --server "$NVIM" --remote-expr 'expand("%:p")'
nvim --server "$NVIM" --remote-expr 'line(".")'
nvim --server "$NVIM" --remote +'42' src/foo.nix    # open file at line 42
```

When `$NVIM` is not set (the harness in a tmux pane adjacent to neovim), use `send-keys` for editor
commands like `:e <path>`.

## Cleanup

Destroy this session's windows when their task is complete and the result is consumed:

```bash
tmux kill-window -t <session>:<index>
```

Do not accumulate stale windows. If you forget, the user sees them in their window list and can kill
them — but do not rely on that.

## Anti-patterns

| Anti-pattern                                                 | Correct                                      |
| ------------------------------------------------------------ | -------------------------------------------- |
| Creating panes in the user's windows                         | Create a session-owned window instead        |
| `send-keys` to a user pane without announcing it             | State the target and command first           |
| Polling `capture-pane` in a tight loop                       | Check once, do other work, check again later |
| `send-keys` into an interactive program (nvim, htop) blindly | Check the mode line via `capture-pane` first |
| Leaving owned windows after task completion                  | `kill-window` when done                      |
| Using owned windows for trivial one-off commands             | Inline shell execution is sufficient         |
| Creating windows when `$TMUX` is not set                     | Primitives require a tmux session            |
| Targeting windows by name                                    | Target by `session:index` (`-t k9-3:2`)      |
| Rerunning in a pane without clearing first                   | `send-keys 'clear' Enter` before the command |
| Reading `capture-pane` without a completion sentinel         | Append `echo "EXIT: $?"` or `echo "DONE"`    |
