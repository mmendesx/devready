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

version_matches() {
  local expected="$1" actual
  shift
  actual="$("$@" 2>&1)" || return 1
  printf '%s\n' "${actual}"
  [[ "${actual}" == "${expected}" || "${actual}" == "${expected}."* ]]
}

java_version() { javac -version 2>&1 | awk '{print $2}'; }

run_doctor() {
  DOCTOR_FAILURES=0
  local -x MISE_AUTO_INSTALL=false MISE_NOT_FOUND_AUTO_INSTALL=false MISE_AUTO_UPDATE=false MISE_OFFLINE=true MISE_NO_HOOKS=true
  local -x COREPACK_ENABLE_NETWORK=0 NG_CLI_ANALYTICS=false PYTHONDONTWRITEBYTECODE=1
  local tool python_path wrapper
  for tool in git curl gh; do doctor_check "${tool} on PATH" "Rerun setup." command -v "${tool}"; done
  doctor_check 'GitHub authentication' 'Run gh auth login.' gh auth status
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
  if selected docker; then
    doctor_check 'Docker daemon access' 'Start Docker Desktop/Engine or select a working Docker context; check user permissions.' docker info
    doctor_check 'Docker Compose' 'Install the Docker Compose plugin.' docker compose version
    doctor_check 'Docker Buildx' 'Install the Docker Buildx plugin.' docker buildx version
  fi
  for tool in codex claude copilot; do
    if selected "${tool}"; then doctor_check "${tool}" "Rerun the ${tool} component." "${tool}" --version; fi
  done
  if selected codex; then doctor_check 'Codex authentication' 'Run codex login.' codex login status; fi
  if selected claude; then doctor_check 'Claude authentication' 'Run claude auth login.' claude auth status; fi
  if selected tools; then
    for tool in rg fd fzf jq tmux shellcheck; do doctor_check "${tool} on PATH" 'Rerun the tools component.' command -v "${tool}"; done
    doctor_check 'RTK (Rust Token Killer)' 'Rerun the tools component; check for an unrelated rtk executable on PATH.' rtk gain --help
  fi
  if selected lsp; then
    doctor_check 'Bash language server' 'Rerun the lsp component.' command -v bash-language-server
    if [[ "${NODE_TOOLING}" == true ]]; then doctor_check 'TypeScript language server' 'Rerun the lsp component.' command -v typescript-language-server; fi
    if selected python; then doctor_check Pyright 'Rerun the lsp component.' command -v pyright-langserver; fi
    if selected java; then doctor_check 'Eclipse JDT LS' 'Rerun the lsp component.' command -v jdtls; fi
  fi
  if selected laya; then
    wrapper="$(dirname "${LAYA_VENV_DIR}")/bin/laya-jev-mcp"
    doctor_check 'Laya MCP handshake/tool discovery (no model downloads)' 'Rerun the laya component; check its virtual environment.' \
      "${LAYA_VENV_DIR}/bin/python" "${REPO_ROOT}/scripts/check-mcp.py" "${wrapper}"
    if selected codex; then doctor_check 'Laya registered in Codex' 'Rerun with codex,laya selected.' codex mcp get laya-jev; fi
    if selected claude; then doctor_check 'Laya registered in Claude' 'Rerun with claude,laya selected.' claude mcp get laya-jev; fi
  fi
  if [[ -n "${PROJECT_DIR}" ]]; then
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
  printf '\nDoctor: %s problem(s).\n' "${DOCTOR_FAILURES}"
  [[ "${DOCTOR_FAILURES}" -eq 0 ]]
}
