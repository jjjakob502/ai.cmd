# ai.cmd

Run AI coding agents (`claude`, `codex`, `agy`, `grok`, `pi`) in an isolated container without installing Node, Python, or npm dependencies on your host machine.

Your logins and session state persist across runs in a local `ai-auth` volume. Works out-of-the-box on Windows, macOS, and Linux with Podman or Docker.

---

## Quickstart

Run from any project folder:

```bash
ai claude          # Run an agent CLI (claude, codex, agy, grok, pi)
ai                 # Open a bash shell inside the container
```

* **Windows:** Run `ai <command>` in Command Prompt or PowerShell.
* **macOS / Linux:** Run `./ai.cmd <command>` (or `alias ai="/path/to/ai.cmd"`).

---

## Commands

| Command | Action |
| :--- | :--- |
| `ai [agent]` | Launch an agent or open an interactive container shell. |
| `ai update` | Pull the latest container image and agent CLIs. |
| `ai build` | Build the container image locally from `Dockerfile`. |
| `ai export [file] [--clean]` | Backup your session/auth volume to `.tar.gz` (`--clean` strips secrets). |
| `ai import <file.tar.gz>` | Restore a session/auth archive into your local volume. |
| `ai sync [push\|pull] <host>` | Stream your session/auth volume to/from another machine over SSH. |
| `ai -- <command>` | Run any custom command inside the container. |

---

## Configuration

Configure behavior via environment variables:

| Variable | Default | Description |
| :--- | :--- | :--- |
| `AI_ENV` | *(empty)* | Space-separated list of extra host environment variables to forward into the container. |
| `AI_ARGS` | *(empty)* | Pass extra engine flags (e.g. `--gpus all`, `-p 3000:3000`, `--env-file .env`). |
| `AI_NETWORK` | `host` | Network mode. Set to `bridge` or `none` for network isolation. |
| `AI_ALLOW_HOME` | *(empty)* | Prevents accidental execution from `$HOME`, `%USERPROFILE%`, or `/`. Set to `1` to override. |
| `AI_CLIS` | `claude codex agy grok pi` | Select which CLIs to install when building (`none` for base toolchain). |
| `AI_IMAGE` | `ghcr.io/jjjakob502/ai.cmd:latest` | Override the container image. |
| `AI_ENGINE` | *(auto)* | Force `podman` or `docker` (auto-detects Podman first). |

---

## Host Services & MCPs

* **Linux:** Reach local dev servers and MCPs at `http://localhost:<port>`.
* **macOS / Windows:** Reach host services at `http://host.docker.internal:<port>`.

---

## Global Install

* **macOS / Linux:** Add an alias in `~/.bashrc` or `~`.`zshrc`:
  ```bash
  alias ai="/path/to/ai.cmd"
  ```
* **Windows:** Add the repository folder to your user `PATH`.
