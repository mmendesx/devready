#!/usr/bin/env bash
set -euo pipefail

# Required versions (override with env vars if needed)
JAVA_VERSION="${JAVA_VERSION:-25}"
PYTHON_VERSION="${PYTHON_VERSION:-3.1}"
NODE_MAJOR_VERSION="${NODE_MAJOR_VERSION:-22}"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() { printf '\n[INFO] %s\n' "$*"; }
warn() { printf '\n[WARN] %s\n' "$*" >&2; }
err() { printf '\n[ERROR] %s\n' "$*" >&2; }

require_sudo() {
  if [[ "${EUID}" -ne 0 ]]; then
    if ! command -v sudo >/dev/null 2>&1; then
      err "This script requires sudo for system package installation."
      exit 1
    fi
    SUDO="sudo"
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
      pacman) ${SUDO} pacman -Sy ;;
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
    apt) dpkg -s "${package}" >/dev/null 2>&1 ;;
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

ensure_java() {
  if command -v java >/dev/null 2>&1 && java -version 2>&1 | grep -q "\"${JAVA_VERSION}"; then
    log "Java ${JAVA_VERSION} already installed"
    return
  fi

  log "Installing Java ${JAVA_VERSION}"
  case "${PKG_MANAGER}" in
    apt)
      install_system_pkg "openjdk-${JAVA_VERSION}-jdk" || {
        warn "openjdk-${JAVA_VERSION}-jdk not available via apt."
      }
      ;;
    dnf|yum)
      install_system_pkg "java-${JAVA_VERSION}-openjdk-devel" || {
        warn "java-${JAVA_VERSION}-openjdk-devel not available via ${PKG_MANAGER}."
      }
      ;;
    pacman)
      install_system_pkg "jdk-openjdk" ;;
    brew)
      brew install "openjdk@${JAVA_VERSION}" || warn "openjdk@${JAVA_VERSION} not available in Homebrew." ;;
  esac

  if ! command -v java >/dev/null 2>&1; then
    warn "Java ${JAVA_VERSION} could not be installed automatically on this system."
  fi
}

ensure_python() {
  if command -v python3 >/dev/null 2>&1 && python3 --version 2>&1 | grep -Eiq "Python 3\\.(1[0-9]|[2-9][0-9])"; then
    log "Python 3.x already installed"
    return
  fi

  log "Installing Python ${PYTHON_VERSION}"
  case "${PKG_MANAGER}" in
    apt)
      install_system_pkg "python${PYTHON_VERSION}" || install_system_pkg "python3"
      install_system_pkg "python3-venv" || true
      install_system_pkg "python3-pip" || true
      ;;
    dnf|yum)
      install_system_pkg "python${PYTHON_VERSION}" || install_system_pkg "python3"
      install_system_pkg "python3-pip" || true
      ;;
    pacman)
      install_system_pkg "python"
      install_system_pkg "python-pip" || true
      ;;
    brew)
      brew install "python@${PYTHON_VERSION}" || brew install python
      ;;
  esac
}

ensure_node() {
  if command -v node >/dev/null 2>&1 && command -v npm >/dev/null 2>&1; then
    log "Node.js and npm already installed"
    return
  fi

  log "Installing Node.js"
  case "${PKG_MANAGER}" in
    apt)
      install_system_pkg "curl"
      curl -fsSL https://deb.nodesource.com/setup_${NODE_MAJOR_VERSION}.x | ${SUDO} -E bash -
      install_system_pkg "nodejs"
      ;;
    dnf|yum)
      install_system_pkg "nodejs"
      install_system_pkg "npm"
      ;;
    pacman)
      install_system_pkg "nodejs"
      install_system_pkg "npm"
      ;;
    brew)
      brew install node
      ;;
  esac
}

ensure_docker() {
  if command -v docker >/dev/null 2>&1; then
    log "Docker already installed"
    return
  fi

  log "Installing Docker"
  case "${PKG_MANAGER}" in
    apt)
      install_system_pkg "docker.io"
      ;;
    dnf|yum)
      install_system_pkg "docker"
      ;;
    pacman)
      install_system_pkg "docker"
      ;;
    brew)
      brew install --cask docker
      ;;
  esac
}

install_npm_global_if_missing() {
  local bin_name="$1"
  local pkg_name="$2"

  if command -v "${bin_name}" >/dev/null 2>&1; then
    log "Already available: ${bin_name}"
    return
  fi

  log "Installing npm package: ${pkg_name}"
  npm install -g "${pkg_name}"
}

ensure_jdtls() {
  if command -v jdtls >/dev/null 2>&1; then
    log "Eclipse JDT Language Server already installed"
    return
  fi

  log "Installing Eclipse JDT Language Server"
  case "${PKG_MANAGER}" in
    apt)
      install_system_pkg "eclipse-jdtls" || install_system_pkg "jdtls" || true
      ;;
    dnf|yum)
      install_system_pkg "java-21-openjdk-headless" || true
      ;;
    pacman)
      install_system_pkg "jdtls" || true
      ;;
    brew)
      brew install jdtls || true
      ;;
  esac

  if ! command -v jdtls >/dev/null 2>&1; then
    install_npm_global_if_missing "jdtls" "@vscjava/java-language-server"
  fi
}

install_skill_if_missing() {
  local skill_ref="$1"
  local match_pattern="$2"

  if ! command -v npx >/dev/null 2>&1; then
    warn "npx not found; skipping skill installation for ${skill_ref}."
    return
  fi

  if npx --yes skills list 2>/dev/null | grep -Eiq "${match_pattern}"; then
    log "Skill already installed: ${skill_ref}"
    return
  fi

  log "Installing skill: ${skill_ref}"
  npx --yes skills add "${skill_ref}" || warn "Failed to install skill: ${skill_ref}"
}

ensure_tools() {
  # Spring Boot CLI
  if command -v spring >/dev/null 2>&1; then
    log "Spring Boot CLI already installed"
  else
    case "${PKG_MANAGER}" in
      brew)
        brew install springboot
        ;;
      *)
        warn "Spring Boot CLI auto-install is only configured for Homebrew. Skipping CLI install."
        ;;
    esac
  fi

  # TypeScript + Angular CLI
  install_npm_global_if_missing "tsc" "typescript"
  install_npm_global_if_missing "ng" "@angular/cli"

  # LSPs
  install_npm_global_if_missing "typescript-language-server" "typescript-language-server"
  install_npm_global_if_missing "bash-language-server" "bash-language-server"
  install_npm_global_if_missing "pyright-langserver" "pyright"
  ensure_jdtls

  # Codex / Claude / Copilot CLIs
  install_npm_global_if_missing "codex" "@openai/codex"
  install_npm_global_if_missing "claude" "@anthropic-ai/claude-code"

  if command -v gh >/dev/null 2>&1; then
    if gh extension list | grep -q 'github/gh-copilot'; then
      log "GitHub Copilot GH extension already installed"
    else
      gh extension install github/gh-copilot || warn "Failed to install gh-copilot extension."
    fi
  else
    warn "GitHub CLI (gh) not found; cannot install gh-copilot extension automatically."
  fi

  # JEV (Laya) middleware: no universal public installer, so support explicit URL hook.
  if command -v jev >/dev/null 2>&1; then
    log "JEV already available"
  elif [[ -n "${JEV_INSTALL_URL:-}" ]]; then
    log "Installing JEV from JEV_INSTALL_URL"
    curl -fsSL "${JEV_INSTALL_URL}" | bash
  else
    warn "JEV not installed. Set JEV_INSTALL_URL to enable automatic installation."
  fi

  # Requested skills/plugins
  install_skill_if_missing "superpowers" "superpowers"
  install_skill_if_missing "ponytail" "ponytail"
  install_skill_if_missing "https://uizze.sh/" "uizze|ui[[:space:]-]*taste"
}

validate_core_tools() {
  log "Validating core toolchain"
  ensure_cmd java "Install Java ${JAVA_VERSION}"
  ensure_cmd python3 "Install Python ${PYTHON_VERSION}"
  ensure_cmd node "Install Node.js"
  ensure_cmd npm "Install npm"
  ensure_cmd docker "Install Docker"
  ensure_cmd tsc "Install TypeScript"
  ensure_cmd ng "Install Angular CLI"

  if ! command -v spring >/dev/null 2>&1; then
    warn "spring CLI is not installed. Spring Boot projects can still run via Maven/Gradle wrappers."
  fi

  # Best-effort optional validations
  for maybe in codex claude typescript-language-server bash-language-server pyright-langserver jdtls; do
    if command -v "${maybe}" >/dev/null 2>&1; then
      log "Validated: ${maybe}"
    else
      warn "Optional tool not installed: ${maybe}"
    fi
  done
}

main() {
  detect_os
  require_sudo
  detect_pkg_manager
  run_pkg_update_once

  # Core build/runtime dependencies
  install_system_pkg curl
  install_system_pkg git
  install_system_pkg unzip || true
  install_system_pkg ca-certificates || true

  if [[ "${PKG_MANAGER}" != "brew" ]]; then
    install_system_pkg gh || warn "GitHub CLI package not available in this distro"
  else
    brew install gh || true
  fi

  ensure_java
  ensure_python
  ensure_node
  ensure_docker
  ensure_tools
  validate_core_tools

  log "Setup finished."
}

main "$@"
