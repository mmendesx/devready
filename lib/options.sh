#!/usr/bin/env bash

usage() {
  cat <<'EOF'
DevReady — choose your tools and prepare your development environment.

Usage: ./devready [options]

  --components LIST    Choose tools with a comma-separated selection:
                       java,python,node,go,c,cpp,docker,tools,lsp,shell,fonts,
                       codex,claude,laya,superpowers,ponytail,ui-taste
  --profile NAME       Legacy preset: minimal, backend, frontend, ai,
                       desktop/full, headless
  --headless           Skip fonts, terminal colors, and editor integration
  --editor NAME        code or cursor (requires --project)
  --project PATH       Configure an existing project's tooling and workspace
  --services LIST      postgres,redis (requires --project; never starts services)
  --yes                Unattended install; requires --components or --profile
  --doctor             Read-only checks; defaults to the last successful install
  --auth               Also check account logins (requires --doctor)
  --dry-run            Show resolved selections without installing anything
  --help               Show this help

Without options: select tools directly with arrows and Space. All tools
start unchecked. Enter continues; q or Esc cancels before installation.

Runtime overrides: JAVA_VERSION=25 PYTHON_VERSION=3.13 NODE_MAJOR_VERSION=22
                   GO_VERSION=1.27
EOF
}

selected() { [[ ",${COMPONENTS}," == *",$1,"* ]]; }
add_component() { selected "$1" || COMPONENTS="${COMPONENTS:+${COMPONENTS},}$1"; }

known_component() {
  case "$1" in
    java|python|node|go|c|cpp|docker|tools|lsp|shell|fonts|codex|claude|laya|superpowers|ponytail|ui-taste) return 0 ;;
    *) return 1 ;;
  esac
}

profile_components() {
  case "$1" in
    minimal) printf 'tools' ;;
    backend) printf 'java,python,docker,tools,lsp,shell,fonts' ;;
    frontend) printf 'node,tools,lsp,shell,fonts' ;;
    ai) printf 'python,codex,claude,laya,superpowers,ponytail,ui-taste,tools' ;;
    full|desktop|headless) printf 'java,python,node,go,c,cpp,docker,tools,lsp,shell,fonts,codex,claude,laya,superpowers,ponytail,ui-taste' ;;
    *) err "Unknown profile: $1"; return 1 ;;
  esac
}

skills_have_destination() {
  local COMPONENTS="$1"
  if selected superpowers || selected ponytail || selected ui-taste; then
    selected codex || selected claude || [[ "${EDITOR}" != none ]]
  fi
}

choose_components() {
  local item key mark pointer result line message=""
  local cursor=0 offset=0 index count picked end rendered=0 terminal_rows terminal_columns page_size
  local choices=(
    "java|Java (JDK ${JAVA_VERSION})"
    "python|Python ${PYTHON_VERSION} + uv"
    "node|Node.js ${NODE_MAJOR_VERSION} + pnpm, TypeScript, Angular"
    "go|Go ${GO_VERSION} + standard build, format, and test tools"
    'c|C (system compiler + CMake)'
    'cpp|C++ (system compiler + CMake)'
    'docker|Docker Engine/Desktop + Compose + Buildx'
    'tools|Terminal tools (ripgrep, fd, fzf, jq, tmux, ShellCheck, RTK)'
    'lsp|Language servers'
    'shell|Zsh + Oh My Zsh + Powerlevel10k'
    'fonts|JetBrainsMono Nerd Font Mono + Dracula'
    'codex|Codex CLI'
    'claude|Claude Code'
    'laya|Laya MCP'
    'superpowers|Superpowers skills'
    'ponytail|Ponytail skills'
    'ui-taste|UI Taste skills'
  )
  local ids=() labels=() checked=() lines=()
  for item in "${choices[@]}"; do
    if [[ "${item%%|*}" == fonts && "${HEADLESS}" == true ]]; then continue; fi
    ids+=("${item%%|*}")
    labels+=("${item#*|}")
    checked+=(0)
  done
  count="${#ids[@]}"
  read -r terminal_rows terminal_columns < <(stty size 2>/dev/null) || { terminal_rows=24; terminal_columns=80; }
  [[ "${terminal_rows:-0}" -gt 0 ]] || terminal_rows=24
  [[ "${terminal_columns:-0}" -gt 1 ]] || terminal_columns=80
  page_size=$((terminal_rows - 5))
  [[ "${page_size}" -gt 0 ]] || page_size=1

  while true; do
    result="" picked=0
    for ((index=0; index<count; index++)); do
      if [[ "${checked[index]}" == 1 ]]; then
        result="${result:+${result},}${ids[index]}"
        picked=$((picked + 1))
      fi
    done
    if ((cursor < offset)); then offset="${cursor}"; fi
    if ((cursor >= offset + page_size)); then offset=$((cursor - page_size + 1)); fi
    end=$((offset + page_size))
    if ((end > count)); then end="${count}"; fi
    lines=("Choose tools (${picked} selected; showing $((offset + 1))-${end} of ${count})")
    for ((index=offset; index<end; index++)); do
      pointer=' ' mark=' '
      if ((index == cursor)); then pointer='>'; fi
      if [[ "${checked[index]}" == 1 ]]; then mark=x; fi
      lines+=("${pointer} [${mark}] ${labels[index]}")
    done
    lines+=('Up/Down move | Space toggle | a all/none' 'Enter: continue | q/Esc: cancel'
      "${message:-Dependencies are added automatically.}")
    {
      if ((rendered > 0)); then printf '\033[%sA' "${rendered}"; fi
      for line in "${lines[@]}"; do
        printf '\r\033[2K%.*s\n' "$((terminal_columns - 1))" "${line}"
      done
    } >&2
    rendered="${#lines[@]}"
    if ! IFS= read -rsn1 key; then printf 'Selection cancelled.\n' >&2; return 1; fi
    if [[ "${key}" == $'\033' ]]; then
      IFS= read -rsn2 -t 1 key || key='q'
      case "${key}" in
        '[A'|OA) key=k ;;
        '[B'|OB) key=j ;;
        '['*|O*) continue ;;
        *) key=q ;;
      esac
    fi
    message=""
    case "${key}" in
      k) cursor=$(((cursor + count - 1) % count)) ;;
      j) cursor=$(((cursor + 1) % count)) ;;
      ' ') checked[cursor]=$((1 - checked[cursor])) ;;
      a)
        mark=1
        if ((picked == count)); then mark=0; fi
        for ((index=0; index<count; index++)); do checked[index]="${mark}"; done
        ;;
      ''|$'\r')
        if [[ -z "${result}" ]]; then
          message='Select at least one tool, or press q to cancel.'
        elif ! skills_have_destination "${result}"; then
          message='Skills need Codex or Claude Code as a destination.'
        else
          printf '%s\n' "${result}"
          return 0
        fi
        ;;
      q|Q|$'\004') printf 'Selection cancelled.\n' >&2; return 1 ;;
    esac
  done
}

parse_args() {
  PROFILE=full COMPONENTS="" HEADLESS=false EDITOR=none PROJECT_DIR="" SERVICES=""
  ASSUME_YES=false MODE=install NODE_TOOLING=false DOCTOR_AUTH=false
  local custom_components="" explicit=false custom_context=false item
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --profile|--components|--editor|--project|--services)
        if [[ $# -lt 2 || -z "$2" || "$2" == --* ]]; then
          err "Missing value for $1"; return 1
        fi
        case "$1" in
          --profile) PROFILE="$2"; explicit=true ;;
          --components) custom_components="$2"; explicit=true ;;
          --editor) EDITOR="$2"; custom_context=true ;;
          --project) PROJECT_DIR="$2"; custom_context=true ;;
          --services) SERVICES="$2"; custom_context=true ;;
        esac
        shift 2 ;;
      --headless) HEADLESS=true; custom_context=true; shift ;;
      --yes) ASSUME_YES=true; shift ;;
      --doctor) MODE=doctor; shift ;;
      --auth) DOCTOR_AUTH=true; shift ;;
      --dry-run) MODE=dry-run; shift ;;
      --help|-h) MODE=help; return ;;
      *) err "Unknown option: $1"; return 1 ;;
    esac
  done

  if [[ "${DOCTOR_AUTH}" == true && "${MODE}" != doctor ]]; then
    err '--auth requires --doctor.'; return 1
  fi
  if [[ "${ASSUME_YES}" == true && "${explicit}" == false && "${MODE}" != doctor ]]; then
    err 'Unattended installation requires an explicit --components LIST or --profile NAME.'; return 1
  fi
  if [[ "${MODE}" == doctor && "${explicit}" == false ]]; then
    if [[ "${custom_context}" == true ]]; then
      err 'Use --components with project, editor, service, or headless overrides; otherwise doctor uses the saved selection.'
      return 1
    fi
    load_installed_state
    return $?
  fi

  if [[ "${MODE}" == install && "${ASSUME_YES}" == false ]]; then
    if [[ ! -t 0 ]]; then
      err "Noninteractive installation requires --yes. Use --dry-run to preview."
      return 1
    fi
    if [[ "${explicit}" == false ]]; then
      custom_components="$(choose_components)" || return 1
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
    known_component "${item}" || { err "Unknown component: ${item}"; return 1; }
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
  if [[ -n "${PROJECT_DIR}" && -f "${PROJECT_DIR}/go.mod" ]]; then add_component go; fi
  if [[ -n "${PROJECT_DIR}" ]] && { [[ -f "${PROJECT_DIR}/pom.xml" ]] || [[ -f "${PROJECT_DIR}/build.gradle" ]] || [[ -f "${PROJECT_DIR}/build.gradle.kts" ]]; }; then add_component java; fi
  if ! skills_have_destination "${COMPONENTS}"; then
    err "Select codex, claude, or an editor as the destination for skills."; return 1
  fi
}

show_selection() {
  printf 'Components: %s\nNode development tools: %s\nHeadless: %s\nEditor: %s\nProject: %s\nServices: %s\n' \
    "${COMPONENTS}" "${NODE_TOOLING}" "${HEADLESS}" "${EDITOR}" "${PROJECT_DIR:-none}" "${SERVICES:-none}"
}
