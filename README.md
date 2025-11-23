# Workspace Management Scripts

This directory hosts the `workspaces` CLI, a general-purpose manager for git worktrees and per-task development environments. It was designed with AI agents and automation in mind: multiple workspaces can be created, started, and torn down concurrently, letting different agents (or humans) work on isolated tasks without stepping on each other.

## `workspaces`

`workspaces` wraps git worktrees, tmux, and developer conventions to give each unit of work its own isolated environment:

- **Git Worktrees:** Each workspace lives under `~/.worktrees/<project>/<workspace>`, with matching state in `~/.worktrees/config/...`. Workspaces get their own branches and clean working directories, perfect for parallel AI or human tasks.
- **Lifecycle Commands:** `new`, `start`, `attach`, `list`, `stop`, `reset`, and `rm` manage the entire workspace lifecycle. Flags like `--branch`, `--attach`, `--rm`, `--reset`, and `-- <args>` customize behavior per workspace.
- **Pluggable Runner (tmux by default):** The script exports workspace-specific env vars (`WORKSPACE_NAME`, `WORKSPACE_SESSION`, `WORKSPACE_DIR`, etc.) into `WORKSPACES_*_CMD` commands:
  - `WORKSPACES_SETUP_CMD` — runs once after creating a workspace (e.g., dependency install).
  - `WORKSPACES_START_CMD` — starts the workspace environment (default: new tmux session/window layout).
  - `WORKSPACES_ATTACH_CMD` — attaches to a running workspace (default: `tmux attach`).
  - `WORKSPACES_STOP_CMD` — stops the workspace (default: `tmux kill-session`).
  - `WORKSPACES_CHECK_CMD` — returns success if the workspace is running.
  You can override any of these to plug in your own tooling (containers, remote shells, IDEs, etc.).
- **Automation Hooks:** Handles IDE integration, direnv approval, saving default args, and running setup commands whenever a workspace is created.
- **Isolation:** The `run_workspace_cmd` helper executes commands in a subshell with a clean environment, so global shell state remains untouched. Workspaces can be reset or removed without affecting others.

## Example Runner (`tmux-dev.sh`)

One `WORKSPACES_*_CMD` implementation included here is `tmux-dev.sh`, which shows how a project might wire services together inside tmux:

- Launches multiple processes (backend, frontend, Storybook) in dedicated tmux windows per workspace.
- Handles dependency installation, configurable ports/offsets, and health checks.
- Sets a friendly `@display_name` per tmux session so status bars can show concise labels.
- Supports flags like `--session`, `--port-offset`, `--bg`, `--setup`, and `--kill` for scriptability.

Because `WORKSPACES_*_CMD` is pluggable, you can point those commands at any runner (containers, VS Code terminals, remote hosts, etc.), making the system suitable for both human developers and AI agents that need reproducible, isolated sandboxes.

See each script for detailed usage instructions, flags, and environment overrides.
