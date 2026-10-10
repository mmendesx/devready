#!/usr/bin/env bash

doctor_check() {
  local label="$1" remedy="$2"
  shift 2
  if "$@" >/dev/null 2>&1; then
    printf '[OK] %s\n' "${label}"
  else
    printf '[FAIL] %s — %s\n' "${label}" "${remedy}"
    DOCTOR_FAILURES=$((DOCTOR_FAILURES + 1))
  fi
}

doctor_auth_check() {
  local label="$1" remedy="$2"
  shift 2
  if "$@" >/dev/null 2>&1; then
    printf '[AUTH OK] %s\n' "${label}"
  else
    printf '[AUTH NEEDED] %s — %s\n' "${label}" "${remedy}"
    AUTH_FAILURES=$((AUTH_FAILURES + 1))
  fi
}

monospace_uses_jetbrains_mono() {
  local font_file
  font_file="$(fc-match -f '%{file}' monospace)" || return 1
  [[ -n "${font_file}" ]] || return 1
  [[ "$(fc-scan -f '%{family[0]}' "${font_file}")" == 'JetBrainsMono Nerd Font Mono' ]]
}

docker_remedy() {
  local failure="$1" context endpoint socket_group session_groups account_groups service_state
  context="$(docker context show 2>/dev/null || true)"
  if [[ -n "${DOCKER_CONTEXT:-}" ]]; then
    context="${DOCKER_CONTEXT}"
    endpoint="$(docker context inspect --format '{{.Endpoints.docker.Host}}' "${context}" 2>/dev/null || true)"
  elif [[ -n "${DOCKER_HOST:-}" ]]; then
    endpoint="${DOCKER_HOST}"
  else
    endpoint="$(docker context inspect --format '{{.Endpoints.docker.Host}}' "${context}" 2>/dev/null || true)"
  fi
  printf '  Context: %s\n  Endpoint: %s\n  Docker says: %s\n' "${context:-unknown}" "${endpoint:-unknown}" "${failure#$'\n'}"
  if [[ -n "${DOCKER_CONTEXT:-}" ]]; then
    printf '  DOCKER_CONTEXT overrides the saved context and DOCKER_HOST. If unintended: unset DOCKER_CONTEXT\n'
  elif [[ -n "${DOCKER_HOST:-}" ]]; then
    printf '  DOCKER_HOST overrides the saved context. If unintended: unset DOCKER_HOST\n'
  fi

  if [[ "${endpoint}" == ssh://* || "${endpoint}" == tcp://* || "${endpoint}" == http://* || "${endpoint}" == https://* ]]; then
    printf '  Check the remote daemon, network connection, and SSH/TLS credentials. Inspect available connections:\n    docker context ls\n'
  elif [[ "${OS}" == Linux && ( "${endpoint}" == unix:///var/run/docker.sock || "${endpoint}" == unix:///run/docker.sock ) ]]; then
    if [[ "${failure}" == *'ermission denied'* ]]; then
      socket_group="$(stat -c '%G' "${endpoint#unix://}" 2>/dev/null || true)"
      session_groups="$(id -nG 2>/dev/null || true)"
      account_groups="$(id -nG "$(id -un)" 2>/dev/null || true)"
      if [[ "${socket_group}" == docker && " ${session_groups} " != *' docker '* ]]; then
        if [[ " ${account_groups} " == *' docker '* ]]; then
          printf '  Your account is already in the docker group, but this session is not.\n'
          printf '  Please log out completely and log back in, including your IDE/terminal session.\n'
          printf '  For a new shell with the existing membership active, run:\n    newgrp docker\n'
        else
          printf '  Your account does not have access to the Docker socket. The docker group grants root-level access.\n'
          printf '  To grant that access, run:\n'
          # The command must expand in the user's shell when they run it.
          # shellcheck disable=SC2016
          printf '    %s\n' 'sudo usermod -aG docker "$(id -un)"'
          printf '  Then log out completely and log back in.\n'
        fi
      else
        printf '  Check socket permissions and any sandbox restrictions; group membership alone does not explain this failure:\n    ls -l %q\n' "${endpoint#unix://}"
      fi
    elif [[ "${failure}" == *'Cannot connect'* || "${failure}" == *'cannot connect'* || "${failure}" == *'connection refused'* || "${failure}" == *'no such file or directory'* ]]; then
      service_state="$(systemctl is-active docker 2>/dev/null || true)"
      case "${service_state}" in
        inactive|failed) printf '  The Docker service is %s. Start it with:\n    sudo systemctl start docker\n' "${service_state}" ;;
        active) printf '  The Docker service is active, but its socket is unreachable. Inspect the service logs:\n    sudo journalctl -u docker --no-pager -n 50\n' ;;
        *) printf '  Start Docker Engine using this machine\047s service manager, then check the socket above.\n' ;;
      esac
    else
      printf '  Inspect the Docker error above and the client/server versions:\n    docker version\n'
    fi
  elif [[ "${endpoint}" == unix://* && "${OS}" == Linux && \
      ( "${context}" == rootless || "${endpoint}" == "unix://${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/docker.sock" ) ]]; then
    printf '  The rootless Docker endpoint is unavailable. Check and start its user service:\n    systemctl --user status docker\n    systemctl --user start docker\n'
  elif [[ "${endpoint}" == unix://* && ( "${context}" == desktop-linux || \
      "${endpoint}" == */.docker/run/docker.sock || "${endpoint}" == */.docker/desktop/docker.sock || \
      ( "${OS}" == Darwin && "${HEADLESS}" == false && "${endpoint}" == unix:///var/run/docker.sock ) ) ]]; then
    printf '  Start Docker Desktop and wait until its engine is running.\n'
    if [[ "${OS}" == Darwin ]]; then printf '    open -a Docker\n'; fi
  else
    printf '  Check the selected custom connection and start the Docker runtime that owns it:\n    docker context ls\n'
  fi
  printf '  Verify the connection, then rerun the Docker checks:\n    docker info\n    ./devready --doctor --components docker\n'
}

doctor_docker() {
  local failure
  if ! command -v docker >/dev/null 2>&1; then
    printf '[FAIL] Docker CLI — Install it with: ./devready --components docker --yes\n'
    DOCTOR_FAILURES=$((DOCTOR_FAILURES + 1))
    return
  fi
  if failure="$(docker info --format '{{.ServerVersion}}' 2>&1)"; then
    printf '[OK] Docker daemon access\n'
  else
    printf '[FAIL] Docker daemon access\n'
    DOCTOR_FAILURES=$((DOCTOR_FAILURES + 1))
    docker_remedy "${failure}"
  fi
  doctor_check 'Docker Compose' 'Install the Docker Compose plugin: https://docs.docker.com/compose/install/' docker compose version
  doctor_check 'Docker Buildx' 'Install the Docker Buildx plugin: https://github.com/docker/buildx#installing' docker buildx version
}

run_doctor() {
  DOCTOR_FAILURES=0 AUTH_FAILURES=0
  local -x MISE_AUTO_INSTALL=false MISE_NOT_FOUND_AUTO_INSTALL=false MISE_AUTO_UPDATE=false MISE_OFFLINE=true MISE_NO_HOOKS=true
  local -x COREPACK_ENABLE_NETWORK=0 NG_CLI_ANALYTICS=false PYTHONDONTWRITEBYTECODE=1 GOTOOLCHAIN=local
  local tool python_path wrapper
  for tool in git curl gh; do doctor_check "${tool} on PATH" "Rerun setup." command -v "${tool}"; done
  if selected fonts && [[ "${OS}" == Linux ]]; then
    doctor_check 'JetBrainsMono Nerd Font Mono installed' 'Rerun the fonts component.' \
      fc-list -q 'JetBrainsMono Nerd Font Mono'
    if fc-list -q 'JetBrainsMono Nerd Font Mono'; then
      doctor_check 'Linux monospace font selection' 'Run fc-cache -r, then rerun the fonts component and reopen your terminal.' \
        monospace_uses_jetbrains_mono
    fi
  fi
  if selected shell; then
    doctor_check 'Zsh on PATH' 'Rerun the shell component.' command -v zsh
    doctor_check 'Oh My Zsh loader' 'Rerun the shell component to repair the incomplete installation.' \
      test -r "${OMZ_DIR}/oh-my-zsh.sh"
  fi
  if selected java; then
    doctor_check "Java ${JAVA_VERSION}" "Run mise use --global --pin java@${JAVA_VERSION}." version_matches "${JAVA_VERSION}" java_version
  fi
  if selected node; then
    doctor_check "Node ${NODE_MAJOR_VERSION}" "Run mise use --global --pin node@${NODE_MAJOR_VERSION}." version_matches "${NODE_MAJOR_VERSION}" node -p process.versions.node
    doctor_check pnpm 'Rerun the node component and reopen your shell.' sh -c 'cd / && pnpm --version'
    if [[ "${NODE_TOOLING}" == true ]]; then
      doctor_check TypeScript 'Run pnpm add --global typescript.' tsc --version
      doctor_check Angular 'Run pnpm add --global @angular/cli.' ng version
    fi
  fi
  if selected python; then
    doctor_check uv 'Rerun the python component.' uv --version
    python_path="$(uv python find --no-python-downloads --managed-python "${PYTHON_VERSION}" 2>/dev/null || true)"
    doctor_check "Python ${PYTHON_VERSION}" "Run uv python install ${PYTHON_VERSION}." \
      version_matches "${PYTHON_VERSION}" "${python_path}" -c 'import platform; print(platform.python_version())'
  fi
  if selected go; then
    doctor_check "Go ${GO_VERSION}" "Run mise use --global --pin go@${GO_VERSION}." version_matches "${GO_VERSION}" go_version
    doctor_check gofmt 'Rerun the go component.' command -v gofmt
  fi
  if selected c; then doctor_check 'C compiler' 'Rerun the c component.' cc --version; fi
  if selected cpp; then doctor_check 'C++ compiler' 'Rerun the cpp component.' c++ --version; fi
  if selected c || selected cpp; then doctor_check CMake 'Rerun the c or cpp component.' cmake --version; fi
  if selected docker; then doctor_docker; fi
  for tool in codex claude; do
    if selected "${tool}"; then doctor_check "${tool}" "Rerun the ${tool} component." "${tool}" --version; fi
  done
  if selected tools; then
    for tool in rg fd fzf jq tmux shellcheck; do doctor_check "${tool} on PATH" 'Rerun the tools component.' command -v "${tool}"; done
    doctor_check 'RTK (Rust Token Killer)' 'Rerun the tools component; check for an unrelated rtk executable on PATH.' rtk gain --help
  fi
  if selected lsp; then
    doctor_check 'Bash language server' 'Rerun the lsp component.' command -v bash-language-server
    if [[ "${NODE_TOOLING}" == true ]]; then doctor_check 'TypeScript language server' 'Rerun the lsp component.' command -v typescript-language-server; fi
    if selected python; then doctor_check Pyright 'Rerun the lsp component.' command -v pyright-langserver; fi
    if selected java; then doctor_check 'Eclipse JDT LS' 'Rerun the lsp component.' command -v jdtls; fi
    if selected go; then doctor_check gopls 'Rerun with go,lsp selected.' gopls version; fi
    if selected c || selected cpp; then doctor_check clangd 'Rerun with c,lsp or cpp,lsp selected.' clangd --version; fi
  fi
  if selected laya; then
    wrapper="$(dirname "${LAYA_VENV_DIR}")/bin/laya-jev-mcp"
    doctor_check 'Laya MCP handshake/tool discovery (no model downloads)' 'Rerun the laya component; check its virtual environment.' \
      "${LAYA_VENV_DIR}/bin/python" "${REPO_ROOT}/scripts/check-mcp.py" "${wrapper}"
    if selected codex; then doctor_check 'Laya registered in Codex' 'Rerun with codex,laya selected.' codex mcp get laya-jev; fi
    if selected claude; then doctor_check 'Laya registered in Claude' 'Rerun with claude,laya selected.' claude mcp get laya-jev; fi
  fi
  if [[ -n "${PROJECT_DIR}" ]]; then
    doctor_check 'Project directory' 'Restore the project, or pass an explicit selection to doctor.' test -d "${PROJECT_DIR}"
    if [[ -f "${PROJECT_DIR}/pom.xml" ]]; then
      doctor_check 'Maven wrapper' 'Generate and commit the Maven wrapper for this project.' test -x "${PROJECT_DIR}/mvnw"
    elif [[ -f "${PROJECT_DIR}/build.gradle" || -f "${PROJECT_DIR}/build.gradle.kts" ]]; then
      doctor_check 'Gradle wrapper' 'Generate and commit the Gradle wrapper for this project.' test -x "${PROJECT_DIR}/gradlew"
    fi
    if [[ -f "${PROJECT_DIR}/package.json" ]]; then
      doctor_check 'Project ESLint' 'Rerun with --project or run pnpm install in the project.' "${PROJECT_DIR}/node_modules/.bin/eslint" --version
      doctor_check 'Project Prettier' 'Rerun with --project or run pnpm install in the project.' "${PROJECT_DIR}/node_modules/.bin/prettier" --version
    fi
    if [[ -f "${PROJECT_DIR}/pyproject.toml" ]]; then
      doctor_check 'Project Ruff' 'Run uv sync --dev in the project.' "${PROJECT_DIR}/.venv/bin/ruff" --version
      doctor_check 'Project pytest' 'Run uv sync --dev in the project.' "${PROJECT_DIR}/.venv/bin/python" -c 'import pytest'
    fi
    if [[ "${EDITOR}" != none ]]; then
      doctor_check 'Editor workspace' 'Rerun with --editor and --project.' test -f "${PROJECT_DIR}/development.code-workspace"
    fi
  fi
  printf '\nInstallation: %s problem(s).\n' "${DOCTOR_FAILURES}"
  if [[ "${DOCTOR_AUTH}" == true ]]; then
    doctor_auth_check GitHub 'Run gh auth login.' gh auth status
    if selected codex; then doctor_auth_check Codex 'Run codex login.' codex login status; fi
    if selected claude; then doctor_auth_check Claude 'Run claude auth login.' claude auth status; fi
    printf 'Authentication: %s account(s) need attention.\n' "${AUTH_FAILURES}"
  fi
  [[ "${DOCTOR_FAILURES}" -eq 0 && "${AUTH_FAILURES}" -eq 0 ]]
}
