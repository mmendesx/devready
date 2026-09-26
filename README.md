# d-environment

A selectable development environment installer for Linux and macOS. Uses **pnpm**, **mise** for Java and Node, and **uv** for Python. Desktop setup uses **JetBrainsMono Nerd Font Mono**, Powerlevel10k, and Dracula colors.

## Quick start

Clone this repository, then run from its directory:

```bash
# Inspect a selection without changing the machine.
bash setup-dev-environment.sh --profile backend --dry-run

# Interactively select a profile and components.
bash setup-dev-environment.sh

# Install a desktop environment using the selected defaults.
bash setup-dev-environment.sh --profile desktop --yes

# Check the same selection after reopening your shell.
bash setup-dev-environment.sh --profile desktop --doctor
```

Run as your normal user. Linux needs sudo for system packages; `--yes` requires an existing sudo session or passwordless sudo. On macOS, install Homebrew and the Xcode Command Line Tools first. Supported package managers are apt, dnf/yum, pacman, and Homebrew; CI exercises Ubuntu and macOS. Other distributions need their usual package repositories enabled.

## Profiles and components

| Profile | Includes |
| --- | --- |
| `minimal` | Git/GitHub CLI and terminal utilities |
| `backend` | Java, Python, Docker, language servers, terminal utilities, shell and fonts |
| `frontend` | Node, pnpm, TypeScript, Angular CLI, language servers, terminal utilities, shell and fonts |
| `ai` | Python, Codex, Claude Code, Copilot CLI, Laya, skills and terminal utilities |
| `desktop` / `full` | All components; `full` is the default |
| `headless` | All components except fonts and terminal colors; no editor integration |

Use `--components` to replace a profile's selection. Dependencies are added automatically: Codex and skills need Node/pnpm; Laya needs Python; language servers need their runtimes. Node added only as a dependency does not install Angular/TypeScript development tools.

```bash
bash setup-dev-environment.sh --components node,tools,shell,fonts --yes
bash setup-dev-environment.sh --components codex,claude,laya --headless --yes
bash setup-dev-environment.sh --profile backend --headless --yes
```

Available components: `java`, `python`, `node`, `docker`, `tools`, `lsp`, `shell`, `fonts`, `codex`, `claude`, `copilot`, `laya`, `superpowers`, `ponytail`, `ui-taste`.

Terminal utilities are ripgrep (`rg`), `fd`, `fzf`, `jq`, `tmux`, ShellCheck, and [RTK (Rust Token Killer)](https://github.com/rtk-ai/rtk). Language servers are Bash, TypeScript, Pyright, and Eclipse JDT LS, according to the selected languages. Language selections also install native build prerequisites. macOS Java setup includes the Spring Boot CLI.

RTK is included in the `tools` component and every standard profile. Setup uses Homebrew on macOS and RTK's official installer on Linux, reuses an existing installation, and checks that the token-saving CLI is available. Use commands such as `rtk git status` and `rtk gain`; to enable Claude Code's automatic command rewriting, run `rtk init --global`.

## Runtime versions

Defaults are Java 25, Python 3.13, and Node 22. Override them when invoking setup:

```bash
JAVA_VERSION=21 PYTHON_VERSION=3.12 NODE_MAJOR_VERSION=24 \
  bash setup-dev-environment.sh --profile backend --yes
```

mise saves resolved Java/Node versions in its global configuration. uv installs managed Python and pins its resolved version globally. Shell startup files receive the required PATH/activation lines. Re-running setup resolves the requested version ranges again; use exact versions to retain a specific patch release.

## Configure an existing project

`--project` detects `package.json`, `pyproject.toml`, and Maven/Gradle manifests. It adds the required runtimes and applies project tooling:

- JavaScript/TypeScript: pnpm lockfile, pinned package manager, missing ESLint/Prettier dependencies, and a starter ESLint config when none exists.
- Python: a managed `.venv`, `.python-version`, uv lockfile, Ruff, and pytest.
- Java: a project mise pin. Doctor checks for an executable Maven/Gradle wrapper; it does not guess the project's build-tool version or generate a wrapper.

Existing lint configurations and declared JavaScript dependency versions are preserved. Review generated manifests and lockfiles before committing, especially when moving a project from another package manager.

```bash
bash setup-dev-environment.sh --profile frontend \
  --project /path/to/app --editor code --yes

bash setup-dev-environment.sh --profile backend \
  --project /path/to/api --editor cursor --services postgres,redis --yes
```

Install the selected editor and its `code` or `cursor` command first. Setup creates `development.code-workspace` and installs relevant language, formatting, debugger, EditorConfig, and Dracula extensions. Open **that workspace** to use its font, formatting, test tasks, and debug configurations. It preserves unrelated workspace settings/tasks and leaves the editor's user `settings.json` alone. Existing JSON files must be valid JSON.

`--project` also works without an editor. `--editor` and `--services` require `--project`; editor integration cannot be combined with `--headless`.

## Local PostgreSQL and Redis

`--services postgres`, `--services redis`, or `--services postgres,redis` copies `compose.dev.yaml` into the project. PostgreSQL 17 and Redis 7 use persistent Docker volumes, health checks, and ports bound to `127.0.0.1` only. No reverse proxy is installed.

Setup creates an ignored, owner-readable `.env.d-environment` with a random PostgreSQL password. It preserves existing Compose and environment files and **does not start services**. In the project directory, use the generated editor tasks or:

```bash
docker compose --env-file .env.d-environment -f compose.dev.yaml \
  --profile postgres --profile redis up -d --wait

docker compose --env-file .env.d-environment -f compose.dev.yaml \
  --profile postgres --profile redis down
```

Select only the profiles you need. Override `POSTGRES_PORT`/`REDIS_PORT` in `.env.d-environment` if ports are occupied. `down` preserves data; adding `--volumes` deletes it.

Desktop macOS installs Docker Desktop when Docker is absent. Headless macOS installs Docker CLI, Compose, and Buildx and requires a working remote Docker context. Linux installs/enables Docker Engine where supported. Doctor reports unavailable daemons or insufficient Docker permissions; setup does not automatically add users to the Docker group.

## Shell and fonts

The shell component installs Oh My Zsh and activates Powerlevel10k with its lean preset. It can make Zsh the login shell; set `ZSH_SET_DEFAULT=false` to skip that change. Existing `.p10k.zsh` is preserved.

The font component installs **JetBrainsMono Nerd Font Mono**. On macOS, it applies the font and Dracula profile to Terminal's default/startup settings, preserving font size; macOS may request Terminal automation permission. On Linux, it sets the fontconfig monospace preference and, in a GNOME session, configures the desktop/Terminal font and Dracula palette.

Other terminal emulators need their own font/theme selection. Over SSH, select the font on the **client** computer. `--headless` skips font and terminal-color changes.

## AI tools and Laya MCP

Codex uses pnpm; Claude Code and the current standalone GitHub Copilot CLI use their native installers. The retired `gh-copilot` extension is not installed. Skills are installed for selected Codex/Claude/editor destinations using the skills CLI; choose a destination when selecting a skills component.

[Laya](https://github.com/NandhaKishorM/laya) runs in its own uv virtual environment. Setup creates `~/.laya-jev/bin/laya-jev-mcp` and `laya-jev-serve`, then validates an actual MCP initialization and tool discovery before registering `laya-jev` in the selected Codex, Claude, Copilot, Cursor, or VS Code clients.

The check disables model downloads and uses `LAYA_PRELOAD=0`. Normal MCP calls may download models when needed. Laya is exposed as MCP tools; provider requests are not automatically routed through it. Sign in to the selected AI tools and run `gh auth login` yourself.

## Doctor and repeat runs

Run `--doctor` with the **same profile/components, project, and version overrides** used for installation. It checks selected runtime versions and commands, GitHub/Codex/Claude authentication, Docker connectivity/plugins, language servers, Laya's MCP handshake, project lint tools, Java wrappers, and the editor workspace. It returns nonzero if a check fails and prints a suggested remedy.

Doctor does not install packages, repair settings, start containers, run project tests, or download Laya models. Runtime auto-installation is disabled during checks. Authentication checks can contact the relevant service.

Setup reuses installed commands, avoids duplicate shell lines, and backs up changed shell/client/workspace configuration once as `*.d-environment.bak`. Repeat runs preserve project credentials, existing lint configs, and unrelated MCP servers. A first run still requires network access, and upstream installers/package repositories can fail; setup then exits with an error.

## Development checks

Run from this repository:

```bash
shellcheck -x setup-dev-environment.sh lib/*.sh test-setup-dev-environment.sh
bash test-setup-dev-environment.sh
python3 tests/check-config.py

python3 -m venv /tmp/d-environment-mcp-check
/tmp/d-environment-mcp-check/bin/python -m pip install 'mcp==2.2.0'
/tmp/d-environment-mcp-check/bin/python tests/check-mcp.py
```

GitHub Actions runs these checks on Ubuntu and macOS and validates both Compose profiles on Ubuntu. Shell tests mock system changes; Python checks exercise generated project/client files and the real MCP SDK against a local fixture server. They do not provision a complete machine or run model inference.
