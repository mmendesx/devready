# DevReady

A selectable development environment installer for Linux and macOS. Uses **pnpm**, **mise** for Java, Node, and Go, and **uv** for Python. C and C++ use the platform compiler and CMake. Desktop setup uses **JetBrainsMono Nerd Font Mono**, Powerlevel10k, and Dracula colors.

## Quick start

Clone this repository, then run from its directory:

```bash
# Select the tools you want to install.
./devready

# Inspect an explicit selection without changing the machine.
./devready --components node,tools,shell,fonts --dry-run

# Install that selection without the checklist.
./devready --components node,tools,shell,fonts --yes

# Check the last successful installation after reopening your shell.
./devready --doctor

# Also check GitHub and selected agent logins.
./devready --doctor --auth
```

Run as your normal user. Linux needs sudo for system packages; `--yes` requires an existing sudo session or passwordless sudo and an explicit `--components` selection (or legacy `--profile`). Bare `--yes` fails before making changes. On macOS, install Homebrew and the Xcode Command Line Tools first. Supported package managers are apt, dnf/yum, pacman, and Homebrew; CI runs isolated checks on Ubuntu and macOS and a real Go/C/C++ installation on Ubuntu 24.04. Other distributions need their usual package repositories enabled.

Running without options opens the tool checklist directly, with everything unchecked. Use **Up/Down** to move, **Space** to toggle a tool, and **Enter** to continue with the selection. Press **a** to select all or clear all, or **q/Esc** to cancel before installation. Select at least one tool; required dependencies are added automatically. The checklist uses Bash and needs no extra packages. It also opens when you supply project, editor, service, or headless options without an explicit tool selection. `--yes`, `--dry-run`, and `--doctor` skip the checklist.

## Tool selection

Use `--components` to select tools on the command line. Dependencies are added automatically: Codex and skills need Node/pnpm; Laya needs Python; language servers need their runtimes. Node added only as a dependency does not install Angular/TypeScript development tools.

```bash
./devready --components node,tools,shell,fonts --yes
./devready --components codex,claude,laya --headless --yes
./devready --components java,python,docker,tools,lsp,shell --headless --yes
./devready --components go,c,cpp,lsp --yes
```

Available components: `java`, `python`, `node`, `go`, `c`, `cpp`, `docker`, `tools`, `lsp`, `shell`, `fonts`, `codex`, `claude`, `laya`, `superpowers`, `ponytail`, `ui-taste`.

Existing scripts can still use `--profile` presets. Interactive setup does not ask for a profile.

Terminal utilities are ripgrep (`rg`), `fd`, `fzf`, `jq`, `tmux`, ShellCheck, and [RTK (Rust Token Killer)](https://github.com/rtk-ai/rtk). Language servers are Bash, TypeScript, Pyright, Eclipse JDT LS, [gopls](https://go.dev/gopls/) for Go, and [clangd](https://clangd.llvm.org/installation) for C/C++, according to the selected languages. Java, Python, Node, C, and C++ selections also install native build prerequisites. macOS Java setup includes the Spring Boot CLI.

Go includes its standard build, formatting, test, and module tools. Select `c` as well for Go projects that use cgo. C and C++ are separate checklist choices (`c` and `cpp`); both use shared compiler/build packages and CMake. Linux uses the distribution's GCC/G++ toolchain, while macOS uses Clang from the Xcode Command Line Tools. Add `lsp` to install the matching language servers. C/C++ compiler versions follow the platform packages.

RTK is included in the `tools` component. Setup uses Homebrew on macOS and RTK's official installer on Linux, reuses an existing installation, and checks that the token-saving CLI is available. Use commands such as `rtk git status` and `rtk gain`; to enable Claude Code's automatic command rewriting, run `rtk init --global`.

## Runtime versions

Defaults are Java 25, Python 3.13, Node 22, and Go 1.27. Override them when invoking setup:

```bash
JAVA_VERSION=21 PYTHON_VERSION=3.12 NODE_MAJOR_VERSION=24 GO_VERSION=1.26 \
  ./devready --components java,python,node,go --yes
```

mise saves resolved Java/Node/Go versions in its global configuration. uv installs managed Python and pins its resolved version globally. Shell startup files receive the required PATH/activation lines. Re-running setup resolves the requested version ranges again; use exact versions to retain a specific patch release.

After a successful install, `${XDG_CONFIG_HOME:-~/.config}/devready/installed.state` records the resolved selection, project/editor/service options, exact runtime versions, and core CLI/compiler version output. It describes the **last successful run**, not every tool ever installed on the machine. The file is owner-readable/writable, contains literal escaped data, and is replaced atomically. Failed runs preserve the previous record; previews and doctor do not write it. This is an installation record, not a dependency lockfile or an automatic replay command.

DevReady was previously named **d-environment**. The old `bash setup-dev-environment.sh` launcher still accepts the same options. Existing `d-environment` configuration and data directories are reused when the corresponding `devready` directory does not exist; no files are moved. `DEVREADY_BIN_DIR` is the binary-location override, with `D_ENV_BIN_DIR` retained as a fallback.

## Configure an existing project

`--project` detects `package.json`, `pyproject.toml`, `go.mod`, and Maven/Gradle manifests. It adds the required runtimes and applies project tooling:

- JavaScript/TypeScript: pnpm lockfile, pinned package manager, missing ESLint/Prettier dependencies, and a starter ESLint config when none exists.
- Python: a managed `.venv`, `.python-version`, uv lockfile, Ruff, and pytest.
- Java: a project mise pin. Doctor checks for an executable Maven/Gradle wrapper; it does not guess the project's build-tool version or generate a wrapper.
- Go: a project mise pin, the Go editor extension, and test/vet tasks when an editor is selected. Existing `go.mod` and `go.sum` files are preserved.
- C/C++: select `c` and/or `cpp` explicitly. Editor integration adds clangd formatting/completion support. An existing `CMakeLists.txt` also enables CMake editor tools and configure/build tasks that generate `build/compile_commands.json` when run.

Existing lint configurations and declared JavaScript dependency versions are preserved. Review generated manifests and lockfiles before committing, especially when moving a project from another package manager.

```bash
./devready --components node,tools,lsp,shell,fonts \
  --project /path/to/app --editor code --yes

./devready --components java,python,docker,tools,lsp,shell,fonts \
  --project /path/to/api --editor cursor --services postgres,redis --yes

./devready --components go,c,cpp,lsp \
  --project /path/to/native-app --editor code --yes
```

Install the selected editor and its `code` or `cursor` command first. Setup creates `development.code-workspace` and installs relevant language, formatting, debugger, EditorConfig, and Dracula extensions. Open **that workspace** to use its font, formatting, test tasks, and debug configurations. It preserves unrelated workspace settings/tasks and leaves the editor's user `settings.json` alone. Existing JSON files must be valid JSON.

`--project` also works without an editor. It adds Python/uv because the project configuration helper runs in Python, including for non-Python projects. `--editor` and `--services` require `--project`; editor integration cannot be combined with `--headless`.

## Local PostgreSQL and Redis

`--services postgres`, `--services redis`, or `--services postgres,redis` copies `compose.dev.yaml` into the project. PostgreSQL 17 and Redis 7 use persistent Docker volumes, health checks, and ports bound to `127.0.0.1` only. No reverse proxy is installed.

Setup creates an ignored, owner-readable `.env.devready` with a random PostgreSQL password. It preserves existing Compose and environment files and **does not start services**. In the project directory, use the generated editor tasks or:

```bash
docker compose --env-file .env.devready -f compose.dev.yaml \
  --profile postgres --profile redis up -d --wait

docker compose --env-file .env.devready -f compose.dev.yaml \
  --profile postgres --profile redis down
```

Select only the profiles you need. Override `POSTGRES_PORT`/`REDIS_PORT` in `.env.devready` if ports are occupied. `down` preserves data; adding `--volumes` deletes it.

Projects with an existing `.env.d-environment` keep using that file and its credentials. For those projects, use `.env.d-environment` in the commands above; the generated editor tasks and setup output already select the existing file.

Desktop macOS installs Docker Desktop when Docker is absent. Headless macOS installs Docker CLI, Compose, and Buildx and requires a working remote Docker context. Linux installs/enables Docker Engine where supported. Doctor reports unavailable daemons or insufficient Docker permissions; setup does not automatically add users to the Docker group.

For a Docker problem, run `./devready --doctor --components docker`. Doctor shows the active context, endpoint, Docker's error, and the relevant next steps: refreshing an existing group membership, granting socket access, starting a stopped service or Docker Desktop, checking rootless Docker, or inspecting a remote connection. `DOCKER_CONTEXT` and `DOCKER_HOST` overrides are identified; Compose and Buildx are checked separately.

On Linux, an account can already belong to the `docker` group while its current session still lacks access. In that case, log out completely and log back in, including the IDE/terminal session, or run `newgrp docker` to open a child shell with the existing membership active. Then run `docker info` and repeat doctor. Opening another terminal inside the same login session may retain the old groups. Adding a user to the `docker` group grants root-level access, so doctor only prints that command when applicable; it never changes groups, socket permissions, contexts, or service state. See [Docker's Linux post-installation guidance](https://docs.docker.com/engine/install/linux-postinstall/).

## Shell and fonts

The shell component installs Oh My Zsh and activates Powerlevel10k with its lean preset. It repairs an incomplete Oh My Zsh directory while preserving existing custom plugins and themes. It can make Zsh the login shell; set `ZSH_SET_DEFAULT=false` to skip that change. Existing `.p10k.zsh` is preserved.

The font component installs **JetBrainsMono Nerd Font Mono**. On macOS, it applies the font and Dracula profile to Terminal's default/startup settings, preserving font size; macOS may request Terminal automation permission. On Linux, it sets the fontconfig monospace preference and, in a GNOME session, configures the desktop/Terminal font and Dracula palette.

Other terminal emulators need their own font/theme selection. Over SSH, select the font on the **client** computer. `--headless` skips font and terminal-color changes.

On Linux, `fc-match` can report the requested family while selecting an unrelated fallback file. Setup checks installed fonts with `fc-list`, and doctor inspects the actual file selected for monospace text. If that check fails despite the font being installed, run `fc-cache -r` to rebuild the font cache, rerun the fonts component, and reopen your terminal. Font cache files from incompatible fontconfig versions can cause this mismatch.

## AI tools and Laya MCP

The available CLI agents are **Codex** and **Claude Code**. Codex uses pnpm; Claude Code uses its native installer. Skills are installed for selected Codex/Claude/editor destinations using the skills CLI; choose a destination when selecting a skills component.

[Laya](https://github.com/NandhaKishorM/laya) runs in its own uv virtual environment. Setup creates `~/.laya-jev/bin/laya-jev-mcp` and `laya-jev-serve`, then validates an actual MCP initialization and tool discovery before registering `laya-jev` in the selected Codex, Claude, Cursor, or VS Code clients.

The check disables model downloads and uses `LAYA_PRELOAD=0`. Normal MCP calls may download models when needed. Laya is exposed as MCP tools; provider requests are not automatically routed through it. Sign in to the selected AI tools and run `gh auth login` yourself.

## Doctor and repeat runs

Run `--doctor` to check the saved selection and exact runtime versions from the last successful installation. It checks commands, Docker connectivity/plugins, language servers, Laya's MCP handshake, project lint tools, Java wrappers, and the editor workspace. It returns nonzero if an installation check fails and prints a suggested remedy. A missing login does not fail this default check.

Add `--auth` to check GitHub and selected Codex/Claude logins. Authentication results and failure counts are reported separately; with this flag, an authentication failure also returns nonzero. Doctor never signs you in automatically.

To check another selection, or an installation made before saved records were introduced, pass `--components` (or `--profile`) plus the desired project and runtime overrides explicitly. For example: `GO_VERSION=1.27 ./devready --doctor --components go,c,cpp`. Project/editor/service/headless overrides require an explicit selection. With no saved record and no explicit selection, doctor reports how to proceed instead of assuming a full installation.

Doctor does not install packages, repair settings, start containers, run project tests, or download Laya models. Runtime auto-installation is disabled during checks, including Go toolchain downloads. Opt-in authentication checks can contact the relevant service.

Setup reuses installed commands, avoids duplicate shell lines, and backs up changed shell/client/workspace configuration once as `*.devready.bak`. Existing `*.d-environment.bak` backups are retained as the original backups. Repeat runs preserve project credentials, existing lint configs, and unrelated MCP servers. A first run still requires network access, and upstream installers/package repositories can fail; setup then exits with an error.

## Development checks

Run from this repository:

```bash
shellcheck -x devready setup-dev-environment.sh lib/*.sh test-devready.sh tests/*.sh
bash test-devready.sh
python3 tests/check-state.py
python3 tests/check-docker.py
python3 tests/check-interactive.py
python3 tests/check-config.py

python3 -m venv /tmp/devready-mcp-check
/tmp/devready-mcp-check/bin/python -m pip install 'mcp==2.2.0'
/tmp/devready-mcp-check/bin/python tests/check-mcp.py
```

GitHub Actions runs these checks on Ubuntu and macOS and validates both Compose profiles on Ubuntu. Shell tests mock system changes; Python checks exercise saved state, generated project/client files, terminal interaction, and the real MCP SDK against a local fixture server.

A separate Ubuntu 24.04 container job starts without developer toolchains, installs Go/C/C++ as a normal user with sudo, builds and runs programs from a fresh login shell, runs doctor without credentials, and repeats setup while checking that saved state and shell/mise configuration stay unchanged. Run the same integration test locally with Docker:

```bash
docker build --file tests/ubuntu.Dockerfile --tag devready-smoke .
docker run --rm devready-smoke
```

This test needs network access and a working Docker daemon. It does not validate GUI/font rendering, every tool combination, a complete macOS installation, or model inference. The smoke script is intended for its disposable image, not direct execution on your workstation.
