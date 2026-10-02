# ai.cmd

Isolated container for AI coding agents (`claude`, `codex`, `agy`, `grok`, `pi`). Zero host Node, Python, or npm required.

Workloads run as a non-root user (`ai`) with dropped Linux capabilities and `no-new-privileges`. Bridge networking is enabled by default with isolated, tool-specific persistent volumes.

[Install & Quickstart](#quickstart) · [State & Recipes](#state-and-recipes) · [Commands](#commands) · [Configuration](#configuration) · [Host Services & MCPs](#host-services--mcps)

---

## Quickstart

### 1. Setup

Run the self-installer once to link `ai` into your system:
```bash
# macOS, Linux, WSL:
./ai.cmd install

# Windows:
.\ai.cmd install
```
*(Engines: Rootless Podman or Docker Desktop. Native Linux Docker: `AI_ENGINE=docker ai build`).*

### 2. Run

```bash
ai claude         # Launch Claude with ~/.claude state preserved
ai agy            # Launch Antigravity with ~/.gemini state preserved
ai                # Open a disposable shell with no saved state
ai -- <command>   # Run an arbitrary command inside the container
```

---

## State and Recipes

Only state for the selected tool is mounted. Everything else in `/home/ai` is wiped when the container exits.

| State Flag | Persisted Container Path | Named Volume |
| :--- | :--- | :--- |
| `claude` | `~/.claude` (including `.claude.json`) | `ai-auth-claude` |
| `codex` | `~/.codex` | `ai-auth-codex` |
| `agy` | `~/.gemini` | `ai-auth-agy` |
| `grok` | `~/.grok` | `ai-auth-grok` |
| `pi` | `~/.pi/agent` | `ai-auth-pi` |
| `ssh` | `~/.ssh` | `ai-auth-ssh` |
| `gh` | `~/.config/gh` | `ai-auth-gh` |
| `aws` | `~/.aws` | `ai-auth-aws` |

### Custom State & Recipes

```bash
# Combine multiple state volumes
AI_STATE="claude ssh gh" ai claude

# Run with state disabled
AI_STATE=none ai claude

# Load an environment recipe
AI_RECIPE=/path/to/dev.env ai claude
```

`dev.env` syntax (plain `KEY=value`, no quotes, no shell expansion):
```ini
AI_STATE=claude ssh gh
AI_NETWORK=bridge
AI_PROJECT_MODE=rw
```

### Export & Import State

```bash
# Archive selected state
AI_STATE="claude gh" ai export saved.tar.gz

# Merge state into local volumes (newer destination files are preserved)
AI_STATE=claude ai import saved.tar.gz

# Sync directly over SSH
ai sync push user@remote-host
```

---

## Commands

| Command | Action |
| :--- | :--- |
| `ai install` | Self-install `ai` into system PATH (`~/.local/bin` on Unix, WindowsApps on Windows). |
| `ai [agent]` | Launch agent CLI or open a shell. |
| `ai update` | Pull the latest image (or rebuild on native Linux Docker). |
| `ai build` | Build the image locally from embedded container definition. |
| `ai dockerfile` | Output the embedded Dockerfile to stdout. |
| `ai export [file]` | Archive selected state volumes (default: `ai-state.tar.gz`). |
| `ai import <file> [--overwrite]` | Merge an archive into selected state volumes (or overwrite with `--overwrite`). |
| `ai sync push\|pull <host>` | Sync selected state over SSH to a remote engine. |
| `ai -- <command>` | Run an arbitrary command inside the container. |

---

## Configuration

| Variable | Default | Description |
| :--- | :--- | :--- |
| `AI_STATE` | auto (matches CLI) | State volumes to mount (`claude`, `ssh`, etc., or `none`). |
| `AI_NETWORK` | `bridge` | Network mode: `bridge`, `none`, or `host`. |
| `AI_PROJECT_MODE` | `rw` | Project mount permissions: `rw`, `ro`, or `none`. |
| `AI_ENV` | *(empty)* | Host environment variables to forward (space-separated). |
| `AI_ARGS` | *(empty)* | Extra engine flags (`--gpus all`, `-p 3000:3000`). |
| `AI_CLIS` | `claude codex agy grok pi` | CLIs installed at build time. |
| `AI_VOLUME` | `ai-auth` | Prefix for named volumes. |
| `AI_IMAGE` | `ghcr.io/jjjakob502/ai.cmd:latest` | Container image override. |
| `AI_ENGINE` | *(auto)* | Force `podman` or `docker`. |
| `AI_ALLOW_HOME` | *(empty)* | Set to `1` to permit launching from `$HOME` or `/`. |

---

## Host Services & MCPs

When connecting an agent to services running on your host machine:

- **Podman:** Use `host.containers.internal:<port>`.
- **Docker Desktop:** Use `host.docker.internal:<port>`.
- **Native Linux Docker:** Map the host gateway via `AI_ARGS="--add-host host.docker.internal:host-gateway"`.
- **Host Network Mode:** Set `AI_NETWORK=host` to access host loopback services directly at `localhost`.

---

## Build Identity & Digest Pinning

Published images are tagged with `latest` and unique `run-<id>-<attempt>` tags. For reproducible builds, pin the exact SHA-256 digest:

```bash
export AI_IMAGE="ghcr.io/jjjakob502/ai.cmd@sha256:<digest>"
ai claude
ai -- cat /opt/ai/build-info.json
```
