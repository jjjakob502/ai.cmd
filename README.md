# Universal AI Agent Runner

A single cross-platform script to run AI coding agent CLIs (`claude`, `codex`, `agy`, `grok`, `pi`) inside an isolated container with persistent logins.

---

## Why

Setting up multiple AI coding agents usually means installing competing Node and Python versions, global npm packages, and developer toolchains on your host machine.

This project wraps them into a single container:
- **No host clutter:** Node 22, Python 3, build tools, and agent CLIs stay in the container.
- **Persistent logins:** Credentials and sessions persist in a volume (`ai-auth`) so you only log in once per agent.
- **Cross-platform:** A single polyglot script (`ai.cmd`) runs natively in bash, zsh, Windows CMD, and PowerShell.
- **Engine agnostic:** Works with Podman (recommended for rootless setups) or Docker on `amd64` and `arm64`.

---

## Included Agents

| Command | Agent | Provider |
| :--- | :--- | :--- |
| `ai claude` | Claude Code | Anthropic |
| `ai codex` | OpenAI Codex CLI | OpenAI |
| `ai agy` | Antigravity CLI | Google |
| `ai grok` | Grok CLI | xAI |
| `ai pi` / `ai pi-coding-agent` | Pi Coding Agent | Earendil Works |

---

## Requirements

Either [Podman](https://podman.io/) (recommended) or [Docker](https://www.docker.com/) installed and running.

---

## Usage

Run `ai.cmd` from any directory you want the agent to work in (it mounts your current directory to `/workspace`):

### Linux & macOS
```bash
./ai.cmd claude
./ai.cmd codex
./ai.cmd agy
./ai.cmd              # drops into an interactive bash shell in /workspace
```

### Windows (CMD or PowerShell)
```cmd
ai claude
ai codex
ai agy
ai
```

On first run, the script automatically pulls the published image (`ghcr.io/jjjakob502/ai.cmd:latest`) or builds it locally if unavailable. When an agent requests authentication, complete the login link in your browser; tokens are saved into the `ai-auth` volume. Host environment variables for API keys (`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `GEMINI_API_KEY`, `GROK_API_KEY`, `GITHUB_TOKEN`) pass through automatically when set.

---

## Runner Commands

The script includes a few utilities to manage images and session state:

| Command | Description |
| :--- | :--- |
| `ai --build` | Rebuilds the container image with the latest packages. |
| `ai --export [file] [--clean]` | Backs up the `ai-auth` volume. Use `--clean` to strip credentials and export sessions only. |
| `ai --import <file.tar.gz>` | Restores a session/auth archive into the local volume. |
| `ai --sync [push\|pull] <host>` | Streams the volume between machines over SSH. |
| `ai -- <command>` | Passes flags directly to the container without interception. |

*(Commands also work without the `--` prefix, e.g. `ai build`, `ai export`).*

---

## Connecting to Host Tools & MCPs

Because the container runs on the host network, agents can easily connect to MCP servers, databases, or dev servers running on your machine:

* On **Windows / macOS**: Connect to host services using `http://host.docker.internal:<port>` (e.g. for Unreal Engine, local databases, or custom tools).
* On **Linux**: Connect directly via `http://localhost:<port>`.

---

## Optional: Global Setup

To use `ai` from anywhere on your machine:

**macOS / Linux:**
```bash
# Add an alias to ~/.bashrc or ~/.zshrc:
alias ai="/path/to/ai.cmd/ai.cmd"
```

**Windows:**
Add the repository directory to your user `PATH`. You can then run `ai <agent>` in any terminal.

## Choose which CLIs to install

Build a custom image with a space-separated selection:

```bash
AI_IMAGE=localhost/ai-selected:local AI_CLIS='claude codex' ./ai.cmd --build
AI_IMAGE=localhost/ai-selected:local ./ai.cmd claude
```

Windows CMD:

```cmd
set AI_IMAGE=localhost/ai-selected:local
set AI_CLIS=claude codex
ai.cmd --build
ai.cmd claude
```

Valid names: `claude`, `codex`, `agy`, `grok`, `pi`. The default installs all five;
`none` installs no AI CLIs. Git, GitHub CLI and the common toolchain remain included.
Unknown names fail the build. `AI_CLIS` is a **build-time** setting: changing it
while running a prebuilt image does not change that image's installed programs.
Use a separate image tag so a custom build does not replace the upstream tag.

Direct engine build is also supported:

```bash
podman build --build-arg 'AI_CLIS=claude codex' -t localhost/ai-selected:local .
```

The selection controls what is shipped, not what a user can install later in a
writable sandbox. Existing home volumes and saved credentials are not removed.
