#!/usr/bin/env bash

# Literal key/value data: never source or eval this file. Escaping keeps paths
# containing newlines and backslashes round-trippable without another runtime.
state_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\t'/\\t}"
  printf '%s' "${value}"
}

state_record() { printf '%s=%s\n' "$1" "$(state_escape "$2")"; }

java_version() { javac -version 2>&1 | awk '{print $2}'; }
go_version() { go version | awk '{sub(/^go/, "", $3); print $3}'; }

version_matches() {
  local expected="$1" actual
  shift
  actual="$("$@" 2>&1)" || return 1
  printf '%s\n' "${actual}"
  [[ "${actual}" == "${expected}" || "${actual}" == "${expected}."* ]]
}

state_version() {
  local key="$1" value
  shift
  value="$("$@" 2>&1)" || { err "Cannot record version: ${key}"; return 1; }
  [[ -n "${value}" ]] || { err "Empty version: ${key}"; return 1; }
  state_record "${key}" "${value}"
}

write_installed_state() {
  local key tool python_path
  local -x MISE_AUTO_INSTALL=false MISE_NOT_FOUND_AUTO_INSTALL=false MISE_OFFLINE=true GOTOOLCHAIN=local
  state_record FORMAT 1 || return 1
  for key in COMPONENTS NODE_TOOLING HEADLESS EDITOR PROJECT_DIR SERVICES; do
    state_record "${key}" "${!key}" || return 1
  done
  if selected java; then
    state_version JAVA_VERSION version_matches "${JAVA_VERSION}" java_version || return 1
  else state_record JAVA_VERSION ''; fi
  if selected python; then
    python_path="$(uv python find --no-python-downloads --managed-python "${PYTHON_VERSION}")" || return 1
    state_version PYTHON_VERSION version_matches "${PYTHON_VERSION}" "${python_path}" -c 'import platform; print(platform.python_version())' || return 1
  else state_record PYTHON_VERSION ''; fi
  if selected node; then
    state_version NODE_MAJOR_VERSION version_matches "${NODE_MAJOR_VERSION}" node -p process.versions.node || return 1
  else state_record NODE_MAJOR_VERSION ''; fi
  if selected go; then
    state_version GO_VERSION version_matches "${GO_VERSION}" go_version || return 1
  else state_record GO_VERSION ''; fi
  for tool in git curl gh; do state_version "version.${tool}" "${tool}" --version || return 1; done
  if selected java || selected node || selected go; then state_version version.mise mise --version || return 1; fi
  if selected python; then state_version version.uv uv --version || return 1; fi
  if selected node; then state_version version.pnpm pnpm --version || return 1; fi
  if selected c; then state_version version.cc cc --version || return 1; fi
  if selected cpp; then state_version version.c++ c++ --version || return 1; fi
  if selected c || selected cpp; then state_version version.cmake cmake --version || return 1; fi
  for tool in codex claude docker; do
    if selected "${tool}"; then state_version "version.${tool}" "${tool}" --version || return 1; fi
  done
  if selected tools; then
    for tool in rg fd fzf jq shellcheck rtk; do state_version "version.${tool}" "${tool}" --version || return 1; done
    state_version version.tmux tmux -V || return 1
  fi
  if selected shell; then state_version version.zsh zsh --version || return 1; fi
}

save_installed_state() {
  local temporary destination="${CONFIG_DIR}/installed.state"
  mkdir -p "${CONFIG_DIR}" || return 1
  temporary="$(mktemp "${CONFIG_DIR}/.installed.XXXXXX")" || return 1
  if ! write_installed_state > "${temporary}"; then
    rm -f "${temporary}"
    err 'Could not record installed versions; the previous successful selection was preserved.'
    return 1
  fi
  if cmp -s "${temporary}" "${destination}"; then
    rm -f "${temporary}"
  else
    mv -f "${temporary}" "${destination}" || { rm -f "${temporary}"; return 1; }
  fi
}

read_installed_state() {
  local line key value encoded seen='|' format='' component
  local entries=()
  while IFS= read -r line || [[ -n "${line}" ]]; do
    [[ "${line}" == *=* ]] || return 1
    key="${line%%=*}" encoded="${line#*=}"
    [[ "${seen}" != *"|${key}|"* ]] || return 1
    seen="${seen}${key}|"
    printf -v value '%b' "${encoded}"
    [[ "$(state_escape "${value}")" == "${encoded}" ]] || return 1
    case "${key}" in
      FORMAT) format="${value}" ;;
      COMPONENTS|NODE_TOOLING|HEADLESS|EDITOR|PROJECT_DIR|SERVICES|JAVA_VERSION|PYTHON_VERSION|NODE_MAJOR_VERSION|GO_VERSION)
        printf -v "${key}" '%s' "${value}" ;;
      version.*) [[ "${key}" =~ ^version\.[a-z][a-z0-9.+-]*$ && -n "${value}" ]] || return 1 ;;
      *) return 1 ;;
    esac
  done < "${CONFIG_DIR}/installed.state"
  [[ "${format}" == 1 ]] || return 1
  for key in COMPONENTS NODE_TOOLING HEADLESS EDITOR PROJECT_DIR SERVICES JAVA_VERSION PYTHON_VERSION NODE_MAJOR_VERSION GO_VERSION; do
    [[ "${seen}" == *"|${key}|"* ]] || return 1
  done
  [[ "${HEADLESS}" == true || "${HEADLESS}" == false ]] || return 1
  [[ "${NODE_TOOLING}" == true || "${NODE_TOOLING}" == false ]] || return 1
  case "${EDITOR}" in none|code|cursor) ;; *) return 1 ;; esac
  case "${SERVICES}" in ''|postgres|redis|postgres,redis|redis,postgres) ;; *) return 1 ;; esac
  [[ "${COMPONENTS}" =~ ^[a-z-]+(,[a-z-]+)*$ ]] || return 1
  IFS=',' read -r -a entries <<< "${COMPONENTS}"
  for component in "${entries[@]}"; do known_component "${component}" || return 1; done
  [[ "${NODE_TOOLING}" != true ]] || selected node || return 1
  for component in java python node go; do
    case "${component}" in
      java) key=JAVA_VERSION ;; python) key=PYTHON_VERSION ;;
      node) key=NODE_MAJOR_VERSION ;; go) key=GO_VERSION ;;
    esac
    if selected "${component}"; then
      [[ "${!key}" =~ ^[0-9][a-zA-Z0-9.+_-]*$ ]] || return 1
    fi
  done
}

load_installed_state() {
  if [[ ! -f "${CONFIG_DIR}/installed.state" ]]; then
    err 'No saved installation. Pass --components LIST to doctor, or complete an installation first.'
    return 1
  fi
  if ! read_installed_state; then
    err "Invalid saved installation: ${CONFIG_DIR}/installed.state. Pass --components LIST to check an explicit selection."
    return 1
  fi
}
