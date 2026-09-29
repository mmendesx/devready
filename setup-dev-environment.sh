#!/usr/bin/env bash
# Shell fragments must expand in the user's next shell, not during setup.
# shellcheck disable=SC2016
set -euo pipefail

JAVA_VERSION="${JAVA_VERSION:-25}"
PYTHON_VERSION="${PYTHON_VERSION:-3.13}"
NODE_MAJOR_VERSION="${NODE_MAJOR_VERSION:-22}"
LAYA_REPO_URL="${LAYA_REPO_URL:-https://github.com/NandhaKishorM/laya.git}"
LAYA_VENV_DIR="${LAYA_VENV_DIR:-$HOME/.laya-jev/.venv}"
LAYA_CONFIG_DIR="${LAYA_CONFIG_DIR:-$HOME/.config/laya}"
OMZ_DIR="${OMZ_DIR:-$HOME/.oh-my-zsh}"
OMZ_THEME="${OMZ_THEME:-powerlevel10k/powerlevel10k}"
ZSH_SET_DEFAULT="${ZSH_SET_DEFAULT:-true}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLS_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/d-environment"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/d-environment"
LOCAL_BIN="${D_ENV_BIN_DIR:-$HOME/.local/bin}"
export PATH="${LOCAL_BIN}:${XDG_DATA_HOME:-$HOME/.local/share}/mise/shims:${PATH}"

source "${REPO_ROOT}/lib/options.sh"

log() { printf '\n[INFO] %s\n' "$*"; }
warn() { printf '\n[WARN] %s\n' "$*" >&2; }
err() { printf '\n[ERROR] %s\n' "$*" >&2; }

require_sudo() {
  if [[ "${EUID}" -ne 0 ]]; then
    if ! command -v sudo >/dev/null 2>&1; then
      err "This script requires sudo for system package installation."
      exit 1
    fi
    if [[ "${ASSUME_YES:-false}" == true ]]; then
      sudo -n true || { err "Run sudo -v first, then retry --yes."; exit 1; }
      SUDO="sudo -n"
    else
      SUDO="sudo"
    fi
  else
    SUDO=""
  fi
}

detect_os() {
  OS="$(uname -s)"
  ARCH="$(uname -m)"

  case "${OS}" in
    Linux|Darwin) ;;
    *)
      err "Unsupported OS: ${OS}. Supported: Linux, macOS"
      exit 1
      ;;
  esac

  log "Detected OS: ${OS} (${ARCH})"
}

detect_pkg_manager() {
  PKG_MANAGER=""
  if [[ "${OS}" == "Linux" ]]; then
    if command -v apt-get >/dev/null 2>&1; then
      PKG_MANAGER="apt"
    elif command -v dnf >/dev/null 2>&1; then
      PKG_MANAGER="dnf"
    elif command -v yum >/dev/null 2>&1; then
      PKG_MANAGER="yum"
    elif command -v pacman >/dev/null 2>&1; then
      PKG_MANAGER="pacman"
    else
      err "No supported Linux package manager found (apt/dnf/yum/pacman)."
      exit 1
    fi
  elif [[ "${OS}" == "Darwin" ]]; then
    if command -v brew >/dev/null 2>&1; then
      PKG_MANAGER="brew"
    else
      err "Homebrew is required on macOS. Install it first: https://brew.sh"
      exit 1
    fi
  fi

  log "Using package manager: ${PKG_MANAGER}"
}

run_pkg_update_once() {
  if [[ "${OS}" == "Linux" ]]; then
    case "${PKG_MANAGER}" in
      apt) ${SUDO} apt-get update ;;
      dnf) ${SUDO} dnf makecache ;;
      yum) ${SUDO} yum makecache ;;
      pacman) ${SUDO} pacman -Syu --noconfirm ;;
    esac
  elif [[ "${OS}" == "Darwin" ]]; then
    brew update
  fi
}

install_system_pkg() {
  local package="$1"
  if is_pkg_installed "${package}"; then
    log "Package already installed: ${package}"
    return
  fi

  case "${PKG_MANAGER}" in
    apt) ${SUDO} apt-get install -y "${package}" ;;
    dnf) ${SUDO} dnf install -y "${package}" ;;
    yum) ${SUDO} yum install -y "${package}" ;;
    pacman) ${SUDO} pacman -S --noconfirm "${package}" ;;
    brew) brew install "${package}" ;;
    *)
      err "Unsupported package manager: ${PKG_MANAGER}"
      exit 1
      ;;
  esac
}

is_pkg_installed() {
  local package="$1"
  case "${PKG_MANAGER}" in
    apt) dpkg-query -W -f='${Status}' "${package}" 2>/dev/null | grep -qx 'install ok installed' ;;
    dnf|yum) rpm -q "${package}" >/dev/null 2>&1 ;;
    pacman) pacman -Q "${package}" >/dev/null 2>&1 ;;
    brew) brew list --formula "${package}" >/dev/null 2>&1 ;;
    *) return 1 ;;
  esac
}

ensure_cmd() {
  local cmd="$1"
  local install_hint="$2"
  if command -v "${cmd}" >/dev/null 2>&1; then
    log "Already available: ${cmd}"
  else
    err "Missing command '${cmd}'. ${install_hint}"
    exit 1
  fi
}

append_shell_line() {
  local file="$1" line="$2"
  mkdir -p "$(dirname "${file}")"
  if [[ -f "${file}" ]] && grep -Fqx "${line}" "${file}"; then return; fi
  backup_file "${file}"
  printf '\n%s\n' "${line}" >> "${file}"
}

backup_file() {
  if [[ -f "$1" && ! -e "$1.d-environment.bak" ]]; then
    cp -p "$1" "$1.d-environment.bak"
  fi
}

ensure_mise() {
  mkdir -p "${LOCAL_BIN}"
  if ! command -v mise >/dev/null 2>&1; then
    curl -fsSL https://mise.run | MISE_INSTALL_PATH="${LOCAL_BIN}/mise" sh
  fi
  ensure_cmd mise "Install mise from https://mise.jdx.dev"
  append_shell_line "${HOME}/.profile" 'export PATH="$HOME/.local/bin:$PATH"'
  append_shell_line "${HOME}/.bashrc" 'export PATH="$HOME/.local/bin:$PATH"'
  append_shell_line "${HOME}/.zshrc" 'export PATH="$HOME/.local/bin:$PATH"'
  append_shell_line "${HOME}/.bashrc" 'eval "$(mise activate bash)"'
  append_shell_line "${HOME}/.zshrc" 'eval "$(mise activate zsh)"'
}

ensure_java() {
  ensure_mise
  MISE_YES=1 mise use --global --pin "java@${JAVA_VERSION}"
  export JAVA_HOME
  JAVA_HOME="$(mise where "java@${JAVA_VERSION}")"
  export PATH="${JAVA_HOME}/bin:${PATH}"
  if [[ "${PKG_MANAGER}" == brew ]]; then
    install_system_pkg spring-io/tap/spring-boot
  fi
}

ensure_python() {
  if ! command -v uv >/dev/null 2>&1; then
    curl -LsSf https://astral.sh/uv/install.sh | UV_INSTALL_DIR="${LOCAL_BIN}" UV_NO_MODIFY_PATH=1 sh
  fi
  uv python install --default "${PYTHON_VERSION}"
  local python_path exact_version
  python_path="$(uv python find --managed-python "${PYTHON_VERSION}")"
  exact_version="$("${python_path}" -c 'import platform; print(platform.python_version())')"
  uv python pin --global "${exact_version}"
  PATH="$(dirname "${python_path}"):${PATH}"
  append_shell_line "${HOME}/.profile" 'export PATH="$HOME/.local/bin:$PATH"'
  append_shell_line "${HOME}/.bashrc" 'export PATH="$HOME/.local/bin:$PATH"'
  append_shell_line "${HOME}/.zshrc" 'export PATH="$HOME/.local/bin:$PATH"'
}

ensure_node() {
  ensure_mise
  MISE_YES=1 mise use --global --pin "node@${NODE_MAJOR_VERSION}"
  PATH="$(mise where "node@${NODE_MAJOR_VERSION}")/bin:${PATH}"
}

ensure_pnpm() {
  local pnpm_home="${XDG_DATA_HOME:-$HOME/.local/share}/pnpm"
  if [[ "${OS}" == Darwin ]]; then pnpm_home="${HOME}/Library/pnpm"; fi
  export PNPM_HOME="${PNPM_HOME:-${pnpm_home}}"
  export PATH="${PNPM_HOME}/bin:${PNPM_HOME}:${PATH}"
  if ! command -v pnpm >/dev/null 2>&1; then
    curl -fsSL https://get.pnpm.io/install.sh | env SHELL="${SHELL:-/bin/bash}" sh -
  fi
  ensure_cmd pnpm "Install pnpm from https://pnpm.io/installation"
  SHELL="${SHELL:-/bin/bash}" pnpm setup
  if command -v zsh >/dev/null 2>&1; then SHELL="$(command -v zsh)" pnpm setup; fi
}

ensure_build_tools() {
  local package
  case "${PKG_MANAGER}" in
    apt) install_system_pkg build-essential; install_system_pkg pkg-config; install_system_pkg libssl-dev; install_system_pkg libffi-dev ;;
    dnf|yum) for package in gcc gcc-c++ make pkgconf-pkg-config openssl-devel libffi-devel; do install_system_pkg "${package}"; done ;;
    pacman) install_system_pkg base-devel; install_system_pkg openssl; install_system_pkg libffi ;;
    brew)
      if ! xcode-select -p >/dev/null 2>&1; then
        err "Install Xcode Command Line Tools with xcode-select --install, then rerun setup."
        return 1
      fi
      install_system_pkg pkg-config
      ;;
  esac
}

ensure_rtk() {
  if ! command -v rtk >/dev/null 2>&1; then
    if [[ "${PKG_MANAGER}" == brew ]]; then
      install_system_pkg rtk || return 1
    else
      curl -fsSL https://raw.githubusercontent.com/rtk-ai/rtk/master/install.sh | RTK_INSTALL_DIR="${LOCAL_BIN}" sh || return 1
    fi
  fi
  if ! rtk --version || ! rtk gain --help >/dev/null 2>&1; then
    err "Expected RTK (Rust Token Killer, rtk-ai/rtk). Check the rtk executable on PATH."
    return 1
  fi
  if [[ "${PKG_MANAGER}" != brew ]]; then
    local file
    for file in "${HOME}/.profile" "${HOME}/.bashrc" "${HOME}/.zshrc"; do
      append_shell_line "${file}" 'export PATH="$HOME/.local/bin:$PATH"'
    done
  fi
}

ensure_terminal_tools() {
  local package
  for package in ripgrep fzf jq tmux shellcheck; do install_system_pkg "${package}"; done
  if [[ "${PKG_MANAGER}" == apt ]]; then
    install_system_pkg fd-find
    mkdir -p "${LOCAL_BIN}"
    if ! command -v fd >/dev/null 2>&1; then ln -s "$(command -v fdfind)" "${LOCAL_BIN}/fd"; fi
  else
    install_system_pkg fd
  fi
  ensure_rtk
}

ensure_docker() {
  if [[ "${PKG_MANAGER}" == brew ]]; then
    if [[ "${HEADLESS}" == true ]]; then
      install_system_pkg docker
      warn "Headless macOS needs a Docker context connected to an existing engine."
    elif ! command -v docker >/dev/null 2>&1; then
      brew install --cask docker-desktop
    fi
    local plugin
    for plugin in compose buildx; do
      if ! docker "${plugin}" version >/dev/null 2>&1; then
        install_system_pkg "docker-${plugin}"
        if ! docker "${plugin}" version >/dev/null 2>&1; then
          mkdir -p "${HOME}/.docker/cli-plugins"
          ln -s "$(brew --prefix)/opt/docker-${plugin}/bin/docker-${plugin}" "${HOME}/.docker/cli-plugins/docker-${plugin}"
        fi
      fi
    done
  elif [[ "${PKG_MANAGER}" == pacman ]]; then
    install_system_pkg docker
    install_system_pkg docker-compose
    install_system_pkg docker-buildx
  else
    if ! command -v docker >/dev/null 2>&1; then
      curl -fsSL https://get.docker.com | ${SUDO} sh
    fi
    if ! docker compose version >/dev/null 2>&1; then
      install_system_pkg docker-compose-plugin || install_system_pkg docker-compose-v2
    fi
    if ! docker buildx version >/dev/null 2>&1; then
      install_system_pkg docker-buildx-plugin || install_system_pkg docker-buildx
    fi
  fi
  ensure_cmd docker "Install Docker Engine or Docker Desktop"
  docker compose version
  docker buildx version
  if [[ "${OS}" == Linux ]] && command -v systemctl >/dev/null 2>&1; then
    ${SUDO} systemctl enable --now docker
  fi
}

install_pnpm_global_if_missing() {
  local bin_name="$1"
  local pkg_name="$2"

  if command -v "${bin_name}" >/dev/null 2>&1; then
    log "Already available: ${bin_name}"
    return
  fi

  log "Installing pnpm package: ${pkg_name}"
  pnpm add --global "${pkg_name}"
}

ensure_jdtls() {
  if command -v jdtls >/dev/null 2>&1; then return; fi
  if [[ "${PKG_MANAGER}" == brew ]]; then
    install_system_pkg jdtls
    return
  fi
  local archive download_dir
  download_dir="$(mktemp -d)"
  archive="$(curl -fsSL https://download.eclipse.org/jdtls/snapshots/latest.txt)"
  if [[ ! "${archive}" =~ ^jdt-language-server-[a-zA-Z0-9.-]+\.tar\.gz$ ]]; then
    rm -rf "${download_dir}"
    err "Eclipse returned an invalid JDT LS archive name."
    return 1
  fi
  mkdir -p "${TOOLS_DIR}/jdtls" "${LOCAL_BIN}"
  if ! curl -fsSL "https://download.eclipse.org/jdtls/snapshots/${archive}" -o "${download_dir}/jdtls.tar.gz" ||
      ! tar -xzf "${download_dir}/jdtls.tar.gz" -C "${TOOLS_DIR}/jdtls"; then
    rm -rf "${download_dir}"
    return 1
  fi
  rm -rf "${download_dir}"
  ln -s "${TOOLS_DIR}/jdtls/bin/jdtls" "${LOCAL_BIN}/jdtls"
}

install_skill_if_missing() {
  local skill_ref="$1" match_pattern="$2" agent
  local agents=()
  if selected codex; then agents+=(codex); fi
  if selected claude; then agents+=(claude-code); fi
  if [[ "${EDITOR}" == cursor ]]; then agents+=(cursor); fi
  if [[ "${EDITOR}" == code ]]; then agents+=(github-copilot); fi
  for agent in "${agents[@]}"; do
    if ! pnpm dlx skills list --global --agent "${agent}" 2>/dev/null | grep -Ei "${match_pattern}" >/dev/null; then
      pnpm dlx skills add "${skill_ref}" --global --agent "${agent}" --skill '*' --yes
    fi
  done
}

update_or_append_shell_var() {
  local file="$1"
  local key="$2"
  local value="$3"
  local tmp_file
  tmp_file="$(mktemp /tmp/d-environment-zshrc.XXXXXX)"

  if [[ -f "${file}" ]]; then
    awk -v key="${key}" -v value="${value}" '
      BEGIN { updated=0 }
      $0 ~ "^" key "=" {
        print key "=\"" value "\""
        updated=1
        next
      }
      { print }
      END {
        if (!updated) {
          print key "=\"" value "\""
        }
      }
    ' "${file}" > "${tmp_file}"
  else
    printf '%s="%s"\n' "${key}" "${value}" > "${tmp_file}"
  fi

  mv "${tmp_file}" "${file}"
}

ensure_omz_with_themes() {
  local zsh_custom zshrc zsh_path current_shell

  if ! command -v zsh >/dev/null 2>&1; then
    log "Installing zsh"
    install_system_pkg zsh || {
      err "Failed to install zsh automatically."
      return 1
    }
  fi

  if [[ ! -d "${OMZ_DIR}" ]]; then
    log "Installing Oh My Zsh"
    curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh | \
      env RUNZSH=no CHSH=no KEEP_ZSHRC=yes ZSH="${OMZ_DIR}" sh || {
        err "Failed to install Oh My Zsh."
        return 1
      }
  else
    log "Oh My Zsh already installed: ${OMZ_DIR}"
  fi

  zsh_custom="${ZSH_CUSTOM:-${OMZ_DIR}/custom}"
  mkdir -p "${zsh_custom}/themes"

  if [[ ! -d "${zsh_custom}/themes/powerlevel10k/.git" ]]; then
    log "Installing powerlevel10k theme"
    git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "${zsh_custom}/themes/powerlevel10k"
  else
    log "powerlevel10k already installed"
  fi


  zshrc="${HOME}/.zshrc"
  backup_file "${zshrc}"
  update_or_append_shell_var "${zshrc}" "ZSH" "${OMZ_DIR}"
  update_or_append_shell_var "${zshrc}" "ZSH_THEME" "${OMZ_THEME}"

  if ! grep -q 'source \$ZSH/oh-my-zsh.sh' "${zshrc}" 2>/dev/null; then
    printf '\nsource $ZSH/oh-my-zsh.sh\n' >> "${zshrc}"
  fi

  zsh_path="$(command -v zsh || true)"
  if command -v pnpm >/dev/null 2>&1; then SHELL="${zsh_path}" pnpm setup; fi
  if [[ ! -f "${HOME}/.p10k.zsh" ]]; then
    cp "${zsh_custom}/themes/powerlevel10k/config/p10k-lean.zsh" "${HOME}/.p10k.zsh"
  fi
  append_shell_line "${zshrc}" '[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh'
  if [[ "${OS}" == Darwin ]]; then
    current_shell="$(dscl . -read "/Users/${USER}" UserShell | awk '{print $2}')"
  else
    current_shell="$(getent passwd "${USER}" | cut -d: -f7)"
  fi
  if [[ "${ZSH_SET_DEFAULT}" == "true" && -n "${zsh_path}" ]]; then
    if [[ "${current_shell}" == "${zsh_path}" ]]; then
      log "Zsh is already the default shell (${zsh_path})"
    elif command -v chsh >/dev/null 2>&1; then
      log "Setting Zsh as default shell for ${USER}"
      if [[ "${ASSUME_YES}" == true ]]; then
        if [[ "${EUID}" -eq 0 ]]; then
          chsh -s "${zsh_path}" "${USER}"
        else
          sudo -n chsh -s "${zsh_path}" "${USER}" || warn "Run chsh -s ${zsh_path} after setup."
        fi
      else
        chsh -s "${zsh_path}" "${USER}" || warn "Could not set default shell automatically. Run: chsh -s ${zsh_path} ${USER}"
      fi
    else
      warn "chsh command not found. Set shell manually: chsh -s ${zsh_path} ${USER}"
    fi
  fi
}

ensure_jetbrains_mono_font() {
  local font_family="JetBrainsMono Nerd Font Mono"
  local font_dir font_config_dir archive schemas profile font_size

  log "Installing and configuring ${font_family}"
  if [[ "${OS}" == "Darwin" ]]; then
    if ! brew list --cask font-jetbrains-mono-nerd-font >/dev/null 2>&1; then
      brew install --cask font-jetbrains-mono-nerd-font
    fi
    if [[ -z "${SSH_CONNECTION:-}${SSH_TTY:-}" ]]; then
      mkdir -p "${CONFIG_DIR}"
      if [[ ! -f "${CONFIG_DIR}/Dracula.terminal" ]]; then
        curl -fsSL https://raw.githubusercontent.com/dracula/terminal-app/master/Dracula.terminal -o "${CONFIG_DIR}/Dracula.terminal"
      fi
      osascript - "${CONFIG_DIR}/Dracula.terminal" <<'APPLESCRIPT' || warn "Select Dracula and JetBrainsMono Nerd Font Mono in Terminal settings manually."
on run argv
  tell application "Terminal"
    set previousSize to font size of default settings
    if not (exists settings set "Dracula") then open (item 1 of argv)
    set font name of settings set "Dracula" to "JetBrainsMonoNFM-Regular"
    set font size of settings set "Dracula" to previousSize
    set default settings to settings set "Dracula"
    set startup settings to settings set "Dracula"
  end tell
end run
APPLESCRIPT
    fi
  else
    install_system_pkg fontconfig
    font_dir="${XDG_DATA_HOME:-$HOME/.local/share}/fonts/JetBrainsMono"
    mkdir -p "${font_dir}"
    if [[ "$(fc-match -f '%{family[0]}' "${font_family}")" != "${font_family}" ]]; then
      install_system_pkg unzip
      archive="$(mktemp "${TMPDIR:-/tmp}/d-environment-font.XXXXXX")"
      if ! curl -fsSL https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.zip -o "${archive}" ||
          ! unzip -oq "${archive}" 'JetBrainsMonoNerdFontMono-*.ttf' -d "${font_dir}"; then
        rm -f "${archive}"
        err "Could not install ${font_family}."
        return 1
      fi
      rm -f "${archive}"
    fi

    font_config_dir="${XDG_CONFIG_HOME:-$HOME/.config}/fontconfig/conf.d"
    mkdir -p "${font_config_dir}"
    cat > "${font_config_dir}/60-jetbrains-mono-nerd.conf" <<EOF
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<fontconfig>
  <alias binding="strong">
    <family>monospace</family>
    <prefer><family>${font_family}</family></prefer>
  </alias>
</fontconfig>
EOF
    fc-cache -f "${font_dir}"

    if command -v gsettings >/dev/null 2>&1 && [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
      schemas="$(gsettings list-schemas)"
      if grep -qx 'org.gnome.desktop.interface' <<< "${schemas}"; then
        font_size="$(gsettings get org.gnome.desktop.interface monospace-font-name)"
        font_size="${font_size##* }"
        gsettings set org.gnome.desktop.interface monospace-font-name "${font_family} ${font_size//\'/}" ||
          warn "Could not set the GNOME monospace font."
        if grep -qx 'org.gnome.Terminal.ProfilesList' <<< "${schemas}"; then
          profile="$(gsettings get org.gnome.Terminal.ProfilesList default)"
          profile="${profile//\'/}"
          if [[ -n "${profile}" ]]; then
            gsettings set "org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:${profile}/" use-system-font true ||
              warn "Could not set the GNOME Terminal default profile font."
            local profile_path="org.gnome.Terminal.Legacy.Profile:/org/gnome/terminal/legacy/profiles:/:${profile}/"
            gsettings set "${profile_path}" use-theme-colors false
            gsettings set "${profile_path}" background-color '#282a36'
            gsettings set "${profile_path}" foreground-color '#f8f8f2'
            gsettings set "${profile_path}" palette "['#21222c','#ff5555','#50fa7b','#f1fa8c','#bd93f9','#ff79c6','#8be9fd','#f8f8f2','#6272a4','#ff6e6e','#69ff94','#ffffa5','#d6acff','#ff92df','#a4ffff','#ffffff']"
          fi
        fi
      fi
    fi
  fi

  if [[ -n "${SSH_CONNECTION:-}${SSH_TTY:-}" ]]; then
    warn "SSH uses the client terminal's font; select ${font_family} on your local computer too."
  fi
}

ensure_laya_jev_middleware() {
  local laya_bin_dir
  laya_bin_dir="$(dirname "${LAYA_VENV_DIR}")/bin"
  mkdir -p "${laya_bin_dir}" "${LAYA_CONFIG_DIR}"
  if [[ ! -x "${LAYA_VENV_DIR}/bin/python" ]]; then
    uv venv --python "${PYTHON_VERSION}" "${LAYA_VENV_DIR}"
  fi
  if [[ ! -x "${LAYA_VENV_DIR}/bin/laya-mcp-server" || ! -x "${LAYA_VENV_DIR}/bin/laya-serve" ]]; then
    uv pip install --python "${LAYA_VENV_DIR}/bin/python" "laya[mcp,serve] @ git+${LAYA_REPO_URL}"
  fi
  printf '#!/usr/bin/env bash\nexport LAYA_PRELOAD="${LAYA_PRELOAD:-0}"\nexec %q "$@"\n' \
    "${LAYA_VENV_DIR}/bin/laya-mcp-server" > "${laya_bin_dir}/laya-jev-mcp"
  printf '#!/usr/bin/env bash\nexec %q "$@"\n' \
    "${LAYA_VENV_DIR}/bin/laya-serve" > "${laya_bin_dir}/laya-jev-serve"
  chmod +x "${laya_bin_dir}/laya-jev-mcp" "${laya_bin_dir}/laya-jev-serve"
  "${LAYA_VENV_DIR}/bin/python" "${REPO_ROOT}/scripts/check-mcp.py" "${laya_bin_dir}/laya-jev-mcp"

  if selected codex; then
    backup_file "${HOME}/.codex/config.toml"
    codex mcp add laya-jev -- "${laya_bin_dir}/laya-jev-mcp"
  fi
  if selected claude; then
    backup_file "${HOME}/.claude.json"
    if claude mcp get laya-jev >/dev/null 2>&1; then
      if claude mcp get laya-jev | grep -F "${laya_bin_dir}/laya-jev-mcp" >/dev/null; then
        log "Laya already registered in Claude"
      else
        claude mcp remove --scope user laya-jev
        claude mcp add --scope user laya-jev -- "${laya_bin_dir}/laya-jev-mcp"
      fi
    else
      claude mcp add --scope user laya-jev -- "${laya_bin_dir}/laya-jev-mcp"
    fi
  fi
  local target
  for target in copilot cursor; do
    if selected "${target}" || [[ "${EDITOR}" == "${target}" ]]; then
      python3 "${REPO_ROOT}/scripts/configure-project.py" --mcp-target "${target}" \
        --mcp-command "${laya_bin_dir}/laya-jev-mcp"
    fi
  done
  if [[ "${EDITOR}" == code ]]; then
    local server_json
    server_json="$(python3 -c 'import json,sys; print(json.dumps({"name":"laya-jev","command":sys.argv[1],"env":{"LAYA_PRELOAD":"0"}}))' "${laya_bin_dir}/laya-jev-mcp")"
    code --add-mcp "${server_json}"
  fi
}

ensure_tools() {
  if [[ "${NODE_TOOLING}" == true ]]; then
    install_pnpm_global_if_missing tsc typescript
    install_pnpm_global_if_missing ng @angular/cli
    NG_CLI_ANALYTICS=false ng config --global cli.packageManager pnpm
  fi
  if selected lsp; then
    install_pnpm_global_if_missing bash-language-server bash-language-server
    if [[ "${NODE_TOOLING}" == true ]]; then install_pnpm_global_if_missing typescript-language-server typescript-language-server; fi
    if selected python; then install_pnpm_global_if_missing pyright-langserver pyright; fi
    if selected java; then ensure_jdtls; fi
  fi
  if selected codex; then install_pnpm_global_if_missing codex @openai/codex; fi
  if selected claude && ! command -v claude >/dev/null 2>&1; then
    curl -fsSL https://claude.ai/install.sh | bash
  fi
  if selected copilot && ! command -v copilot >/dev/null 2>&1; then
    curl -fsSL https://gh.io/copilot-install | PREFIX="$(dirname "${LOCAL_BIN}")" bash
  fi
  if selected shell; then ensure_omz_with_themes; fi
  if selected fonts; then ensure_jetbrains_mono_font; fi
  if selected laya; then ensure_laya_jev_middleware; fi
  if selected superpowers; then install_skill_if_missing https://github.com/obra/superpowers superpowers; fi
  if selected ponytail; then install_skill_if_missing https://github.com/DietrichGebert/ponytail ponytail; fi
  if selected ui-taste; then install_skill_if_missing https://uizze.sh/ 'uizze|ui[[:space:]-]*taste'; fi
}

configure_project() {
  [[ -n "${PROJECT_DIR}" ]] || return 0
  local python_path exact_version missing
  local packages=()
  if [[ -f "${PROJECT_DIR}/package.json" ]]; then
    MISE_YES=1 mise use --path "${PROJECT_DIR}/mise.toml" --pin "node@${NODE_MAJOR_VERSION}"
    missing="$(python3 -c 'import json,sys; p=json.load(open(sys.argv[1])); deps={**p.get("dependencies",{}), **p.get("devDependencies",{})}; print(" ".join(n for n in ("eslint","prettier","typescript-eslint","eslint-config-prettier") if n not in deps))' "${PROJECT_DIR}/package.json")"
    if [[ -n "${missing}" ]]; then
      read -r -a packages <<< "${missing}"
      pnpm --dir "${PROJECT_DIR}" add --save-dev --save-exact "${packages[@]}"
    else
      pnpm --dir "${PROJECT_DIR}" install
    fi
    pnpm --dir "${PROJECT_DIR}" pkg set "packageManager=pnpm@$(pnpm --version)"
  fi
  if [[ -f "${PROJECT_DIR}/pyproject.toml" ]]; then
    python_path="$(uv python find --managed-python "${PYTHON_VERSION}")"
    exact_version="$("${python_path}" -c 'import platform; print(platform.python_version())')"
    uv python pin --project "${PROJECT_DIR}" "${exact_version}"
    uv add --project "${PROJECT_DIR}" --dev ruff pytest
  fi
  if [[ -f "${PROJECT_DIR}/pom.xml" || -f "${PROJECT_DIR}/build.gradle" || -f "${PROJECT_DIR}/build.gradle.kts" ]]; then
    MISE_YES=1 mise use --path "${PROJECT_DIR}/mise.toml" --pin "java@${JAVA_VERSION}"
  fi
  python3 "${REPO_ROOT}/scripts/configure-project.py" --project "${PROJECT_DIR}" \
    --editor "${EDITOR}" --services "${SERVICES}"
}

validate_core_tools() {
  local component
  for component in java python node docker codex claude copilot; do
    if selected "${component}"; then
      case "${component}" in
        python) ensure_cmd uv "Rerun the Python component" ;;
        *) ensure_cmd "${component}" "Rerun the ${component} component" ;;
      esac
    fi
  done
  if selected node; then ensure_cmd pnpm "Rerun the Node component"; fi
}

main() {
  parse_args "$@" || return 1
  if [[ "${MODE}" == help ]]; then usage; return; fi
  show_selection
  if [[ "${MODE}" == dry-run ]]; then return; fi
  detect_os
  if [[ "${MODE}" == doctor ]]; then
    source "${REPO_ROOT}/lib/doctor.sh"
    run_doctor
    return
  fi
  if [[ "${OS}" == Linux ]]; then require_sudo; else SUDO=""; fi
  detect_pkg_manager
  if [[ "${EDITOR}" != none ]]; then ensure_cmd "${EDITOR}" "Install the selected editor and enable its command-line launcher"; fi
  run_pkg_update_once
  install_system_pkg curl
  install_system_pkg git
  install_system_pkg unzip
  install_system_pkg ca-certificates
  install_system_pkg gh
  if selected java || selected python || selected node; then ensure_build_tools; fi
  if selected java; then ensure_java; fi
  if selected python; then ensure_python; fi
  if selected node; then ensure_node; ensure_pnpm; fi
  if selected tools; then ensure_terminal_tools; fi
  if selected docker; then ensure_docker; fi
  ensure_tools
  configure_project
  validate_core_tools
  log "Setup finished. Run --doctor with the same selection to check authentication and services."
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
