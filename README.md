# d-environment

All-in-one script to install dependencies required for a development environment.

## What it sets up

- Java (default target: 25, configurable with `JAVA_VERSION`)
- Spring Boot CLI (when supported by package manager)
- TypeScript
- Python 3.x (default target: `3.1`, configurable with `PYTHON_VERSION`)
- Angular CLI
- Codex CLI
- Claude CLI
- Copilot (GitHub CLI extension)
- LSPs (`typescript-language-server`, `bash-language-server`, `pyright`, Eclipse JDT Language Server)
- Laya JEV middleware from `https://github.com/NandhaKishorM/laya` (MCP + HTTP server wrappers)
- Plugins/skills: `superpowers`, `ponytail`, and `UI taste` (`https://uizze.sh/`)
- Oh My Zsh with `powerlevel10k` and `Dracula` theme (default: `dracula/dracula`)
- Docker

## Usage

```bash
cd /home/runner/work/d-environment/d-environment
./setup-dev-environment.sh
```

### Optional overrides

```bash
JAVA_VERSION=25 PYTHON_VERSION=3.1 NODE_MAJOR_VERSION=22 ./setup-dev-environment.sh
```

### JEV (Laya) middleware for AI agents

The setup script installs Laya from the open-source reference repository and configures middleware wrappers:

- `~/.laya-jev/.venv` (virtual environment)
- `~/.laya-jev/bin/laya-jev-mcp` (stdio MCP wrapper)
- `~/.laya-jev/bin/laya-jev-serve` (HTTP middleware wrapper)
- `~/.config/laya/mcp-server.json` (MCP server config template)

To override defaults:

```bash
LAYA_REPO_URL="https://github.com/NandhaKishorM/laya.git" \
LAYA_VENV_DIR="$HOME/.laya-jev/.venv" \
LAYA_CONFIG_DIR="$HOME/.config/laya" \
./setup-dev-environment.sh
```

### Shell setup (OMZ + powerlevel10k + Dracula)

The script installs:

- Oh My Zsh (`~/.oh-my-zsh` by default)
- `powerlevel10k` theme under `~/.oh-my-zsh/custom/themes/powerlevel10k`
- `dracula` theme under `~/.oh-my-zsh/custom/themes/dracula`

Default `~/.zshrc` theme is set to `dracula/dracula`.  
To override:

```bash
OMZ_DIR="$HOME/.oh-my-zsh" OMZ_THEME="powerlevel10k/powerlevel10k" ./setup-dev-environment.sh
```

## Validations included

- Detects supported OS (`Linux`, `macOS`) and architecture
- Detects package manager (`apt`, `dnf`, `yum`, `pacman`, `brew`)
- Skips packages/tools that are already installed
- Verifies required commands after installation and fails fast if core tools are missing
