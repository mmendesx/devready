# d-environment

All-in-one script to install dependencies required for a development environment.

## What it sets up

- Java (default target: 25, configurable with `JAVA_VERSION`)
- Spring Boot CLI (when supported by package manager)
- TypeScript
- Python 3.x (default target: `3.12`, configurable with `PYTHON_VERSION`)
- Angular CLI
- Codex CLI
- Claude CLI
- Copilot (GitHub CLI extension)
- LSPs (`typescript-language-server`, `bash-language-server`, `pyright`)
- JEV (Laya) via `JEV_INSTALL_URL` hook
- Docker

## Usage

```bash
cd /home/runner/work/d-environment/d-environment
./setup-dev-environment.sh
```

### Optional overrides

```bash
JAVA_VERSION=25 PYTHON_VERSION=3.12 NODE_MAJOR_VERSION=22 ./setup-dev-environment.sh
```

### JEV (Laya)

If you have an installer URL/script for JEV, run with:

```bash
JEV_INSTALL_URL="https://example.com/jev/install.sh" ./setup-dev-environment.sh
```

## Validations included

- Detects supported OS (`Linux`, `macOS`) and architecture
- Detects package manager (`apt`, `dnf`, `yum`, `pacman`, `brew`)
- Skips packages/tools that are already installed
- Verifies required commands after installation and fails fast if core tools are missing
