#!/usr/bin/env bash

usage() {
  cat <<'EOF'
Usage: ./setup-dev-environment.sh [options]

  --profile NAME       minimal, backend, frontend, ai, desktop/full, headless
  --components LIST    Replace the profile with a comma-separated selection:
                       java,python,node,docker,tools,lsp,shell,fonts,
                       codex,claude,copilot,laya,superpowers,ponytail,ui-taste
  --headless           Skip fonts, terminal colors, and editor integration
  --editor NAME        code or cursor (requires --project)
  --project PATH       Configure an existing project's tooling and workspace
  --services LIST      postgres,redis (requires --project; never starts services)
  --yes                Unattended installation; use sudo's noninteractive mode
  --doctor             Read-only checks for the selected environment
  --dry-run            Show resolved selections without installing anything
  --help               Show this help

Runtime overrides: JAVA_VERSION=25 PYTHON_VERSION=3.13 NODE_MAJOR_VERSION=22
EOF
}

selected() { [[ ",${COMPONENTS}," == *",$1,"* ]]; }
add_component() { selected "$1" || COMPONENTS="${COMPONENTS:+${COMPONENTS},}$1"; }

profile_components() {
  case "$1" in
    minimal) printf 'tools' ;;
    backend) printf 'java,python,docker,tools,lsp,shell,fonts' ;;
    frontend) printf 'node,tools,lsp,shell,fonts' ;;
    ai) printf 'python,codex,claude,copilot,laya,superpowers,ponytail,ui-taste,tools' ;;
    full|desktop|headless) printf 'java,python,node,docker,tools,lsp,shell,fonts,codex,claude,copilot,laya,superpowers,ponytail,ui-taste' ;;
    *) err "Unknown profile: $1"; return 1 ;;
  esac
}

parse_args() {
  PROFILE=full COMPONENTS="" HEADLESS=false EDITOR=none PROJECT_DIR="" SERVICES=""
  ASSUME_YES=false MODE=install NODE_TOOLING=false
  local custom_components="" explicit=false item
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --profile|--components|--editor|--project|--services)
        if [[ $# -lt 2 || -z "$2" || "$2" == --* ]]; then
          err "Missing value for $1"; return 1
        fi
        case "$1" in
          --profile) PROFILE="$2" ;;
          --components) custom_components="$2" ;;
          --editor) EDITOR="$2" ;;
          --project) PROJECT_DIR="$2" ;;
          --services) SERVICES="$2" ;;
        esac
        explicit=true
        shift 2 ;;
      --headless) HEADLESS=true; shift ;;
      --yes) ASSUME_YES=true; shift ;;
      --doctor) MODE=doctor; shift ;;
      --dry-run) MODE=dry-run; shift ;;
      --help|-h) MODE=help; return ;;
      *) err "Unknown option: $1"; return 1 ;;
    esac
  done

  if [[ "${MODE}" == install && "${ASSUME_YES}" == false ]]; then
    if [[ ! -t 0 ]]; then
      err "Noninteractive installation requires --yes. Use --dry-run to preview."
      return 1
    fi
    if [[ "${explicit}" == false ]]; then
      printf 'Profile [full/minimal/backend/frontend/ai/desktop/headless] (full): '
      read -r item
      PROFILE="${item:-full}"
      COMPONENTS="$(profile_components "${PROFILE}")" || return 1
      printf 'Components [%s] (Enter keeps this selection): ' "${COMPONENTS}"
      read -r custom_components
    fi
  fi

  COMPONENTS="$(profile_components "${PROFILE}")" || return 1
  COMPONENTS="${custom_components:-${COMPONENTS}}"
  [[ "${PROFILE}" != headless ]] || HEADLESS=true
  if [[ "${COMPONENTS}" == ,* || "${COMPONENTS}" == *, || "${COMPONENTS}" == *,,* ]]; then
    err "Components must be a comma-separated list without empty entries."; return 1
  fi
  local entries=()
  IFS=',' read -r -a entries <<< "${COMPONENTS}"
  COMPONENTS=""
  for item in "${entries[@]}"; do
    case "${item}" in
      java|python|node|docker|tools|lsp|shell|fonts|codex|claude|copilot|laya|superpowers|ponytail|ui-taste) ;;
      *) err "Unknown component: ${item}"; return 1 ;;
    esac
    if [[ "${HEADLESS}" == true && "${item}" == fonts ]]; then continue; fi
    add_component "${item}"
  done
  if selected node; then NODE_TOOLING=true; fi
  case "${EDITOR}" in code|cursor|none) ;; *) err "Editor must be code or cursor."; return 1 ;; esac
  case "${SERVICES}" in ''|postgres|redis|postgres,redis|redis,postgres) ;; *) err "Services must be postgres, redis, or postgres,redis."; return 1 ;; esac
  if [[ -n "${PROJECT_DIR}" ]]; then
    [[ -d "${PROJECT_DIR}" ]] || { err "Project directory does not exist: ${PROJECT_DIR}"; return 1; }
    PROJECT_DIR="$(cd "${PROJECT_DIR}" && pwd)"
    add_component python
  elif [[ "${EDITOR}" != none || -n "${SERVICES}" ]]; then
    err "--editor and --services require --project PATH."; return 1
  fi
  if [[ "${HEADLESS}" == true ]]; then
    [[ "${EDITOR}" == none ]] || { err "Editor integration is disabled in headless mode."; return 1; }
  fi
  [[ -n "${COMPONENTS}" ]] || { err "No components remain in the selection."; return 1; }
  if [[ "${EDITOR}" != none ]]; then add_component fonts; fi
  for item in codex lsp superpowers ponytail ui-taste; do
    if selected "${item}"; then add_component node; fi
  done
  if selected laya || { selected lsp && selected java; }; then add_component python; fi
  [[ -z "${SERVICES}" ]] || add_component docker
  if [[ -n "${PROJECT_DIR}" && -f "${PROJECT_DIR}/package.json" ]]; then add_component node; NODE_TOOLING=true; fi
  if [[ -n "${PROJECT_DIR}" ]] && { [[ -f "${PROJECT_DIR}/pom.xml" ]] || [[ -f "${PROJECT_DIR}/build.gradle" ]] || [[ -f "${PROJECT_DIR}/build.gradle.kts" ]]; }; then add_component java; fi
  if selected superpowers || selected ponytail || selected ui-taste; then
    if ! selected codex && ! selected claude && [[ "${EDITOR}" == none ]]; then
      err "Select codex, claude, or an editor as the destination for skills."; return 1
    fi
  fi
}

show_selection() {
  printf 'Profile: %s\nComponents: %s\nNode development tools: %s\nHeadless: %s\nEditor: %s\nProject: %s\nServices: %s\n' \
    "${PROFILE}" "${COMPONENTS}" "${NODE_TOOLING}" "${HEADLESS}" "${EDITOR}" "${PROJECT_DIR:-none}" "${SERVICES:-none}"
}
