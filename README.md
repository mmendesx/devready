# d-environment

All-in-one script to install dependencies required for a development environment.

## What it sets up

- Java (default target: 25, configurable with `JAVA_VERSION`)
- Spring Boot CLI (when supported by package manager)
- Node.js and pnpm for JavaScript packages and CLI tools
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
- JetBrains Mono Nerd Font Mono as the default monospace/terminal font
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

### JavaScript package manager

The script installs [pnpm using its standalone installer](https://pnpm.io/installation/), reuses it when already available, and runs `pnpm setup` to configure the shell. Global CLI packages use `pnpm add --global`; skills use `pnpm dlx skills`.

`PNPM_HOME` defaults to `${XDG_DATA_HOME:-$HOME/.local/share}/pnpm`. Its executable directories are available during setup and in new Zsh sessions.

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
- Sets Zsh as default shell (via `chsh`) when possible

Default `~/.zshrc` theme is set to `dracula/dracula`.  
To override:

```bash
OMZ_DIR="$HOME/.oh-my-zsh" OMZ_THEME="powerlevel10k/powerlevel10k" ./setup-dev-environment.sh
```

Disable default-shell change:

```bash
ZSH_SET_DEFAULT=false ./setup-dev-environment.sh
```

### Default font

The script installs **JetBrainsMono Nerd Font Mono**, including the icons used by shell themes:

- Linux: downloads the Nerd Fonts release when the font is missing, refreshes the font cache, and configures the user's Fontconfig `monospace` default. In a GNOME desktop session, it also updates the monospace font and default GNOME Terminal profile, preserving the desktop font size.
- macOS: installs the [Homebrew font cask](https://formulae.brew.sh/cask/font-jetbrains-mono-nerd-font) and sets Terminal's default and startup profiles to the font, preserving their sizes.

Other terminals and editors with their own explicit font settings must select `JetBrainsMono Nerd Font Mono` in their preferences. Over SSH, install and select the font on the **client computer**; a remote server cannot change the client terminal's font. macOS Terminal automation is skipped over SSH and reports a manual step if automation permission is unavailable.

## Validations included

- Detects supported OS (`Linux`, `macOS`) and architecture
- Detects package manager (`apt`, `dnf`, `yum`, `pacman`, `brew`)
- Skips packages/tools that are already installed
- Verifies required commands after installation and fails fast if core tools are missing

Run the isolated smoke check (no packages are installed or personal settings changed):

```bash
bash test-setup-dev-environment.sh
```
