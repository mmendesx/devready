#!/usr/bin/env bash
# Stub commands are called indirectly by the sourced installer and doctor.
# shellcheck disable=SC2317,SC2329
set -euo pipefail

test_node="$(node -p 'process.execPath')"
source "$(dirname "${BASH_SOURCE[0]}")/devready"

test_dir="$(mktemp -d)"
trap 'rm -rf "${test_dir}"' EXIT
export SETUP_TEST_DIR="${test_dir}" SETUP_TEST_LOG="${test_dir}/calls"
export PNPM_HOME="${test_dir}/pnpm" XDG_DATA_HOME="${test_dir}/data"
export XDG_CONFIG_HOME="${test_dir}/config" TMPDIR="${test_dir}/tmp"
mkdir -p "${test_dir}/bin" "${TMPDIR}" "${test_dir}/configuration"
for tool in cat chmod cp dirname env grep mkdir mktemp rm sh cmp awk uname ln; do
  ln -s "$(command -v "${tool}")" "${test_dir}/bin/${tool}"
done
ln -s "$test_node" "${test_dir}/bin/node"
export PATH="${test_dir}/bin"
CONFIG_DIR="${test_dir}/configuration"
LOCAL_BIN="${test_dir}/bin"
LAYA_VENV_DIR="${test_dir}/laya/.venv"
LAYA_CONFIG_DIR="${test_dir}/laya/config"
unset SSH_CONNECTION SSH_TTY

record() { printf '%s\n' "$*" >> "${SETUP_TEST_LOG}"; }
install_system_pkg() { record "package $*"; }
curl() {
  record "curl $*"
  if [[ "$2" == "https://get.pnpm.io/install.sh" ]]; then
    cat <<'EOF'
mkdir -p "$PNPM_HOME/bin"
cp "$SETUP_TEST_DIR/pnpm-stub" "$PNPM_HOME/bin/pnpm"
chmod +x "$PNPM_HOME/bin/pnpm"
EOF
  else
    [[ "${font_download_fails:-false}" == "false" ]] || return 1
    : > "$4"
  fi
}
cat > "${test_dir}/pnpm-stub" <<'EOF'
#!/bin/sh
printf 'pnpm %s\n' "$*" >> "$SETUP_TEST_LOG"
if [ "$3" = list ]; then printf '[]\n'; fi
EOF

parse_args --dry-run --components go,c,cpp
[[ "$COMPONENTS" == go,c,cpp && "$NODE_TOOLING" == false ]]
mkdir -p "$test_dir/go-project"
printf 'module example.com/app\n\ngo 1.27\n' > "$test_dir/go-project/go.mod"
parse_args --dry-run --components tools --project "$test_dir/go-project"
selected go
selected node && exit 1
parse_args --dry-run --components codex
selected node
selected python && exit 1
[[ "${NODE_TOOLING}" == false ]]
parse_args --components claude --dry-run
selected node && exit 1
parse_args --components node --dry-run
[[ "${NODE_TOOLING}" == true ]]
parse_args --dry-run --profile headless
selected fonts && exit 1
selected copilot && exit 1
[[ "${HEADLESS}" == true ]]
if parse_args --dry-run --components copilot; then
  printf 'Only Codex and Claude should be available as agent CLIs.\n' >&2
  exit 1
fi
if parse_args --dry-run --components typo; then exit 1; fi
if parse_args --dry-run --profile typo; then exit 1; fi
if parse_args --dry-run --profile headless --editor code; then exit 1; fi
if parse_args --dry-run --services postgres; then exit 1; fi
if parse_args --profile minimal < /dev/null; then exit 1; fi
parse_args --dry-run --components fonts,fonts,tools --headless
[[ "${COMPONENTS}" == tools ]]
: > "${SETUP_TEST_LOG}"
main --dry-run --components tools
[[ ! -s "${SETUP_TEST_LOG}" ]]

OS=Linux PKG_MANAGER=dnf
ensure_mise() { :; }
mise() {
  if [[ "$1" == where ]]; then printf '%s/runtime\n' "${test_dir}"; else record "mise $*"; fi
}
ensure_node
ensure_node
[[ "$(grep -c 'mise use --global --pin node@22' "${SETUP_TEST_LOG}")" == 2 ]]

(
  GO_VERSION=1.26.8 ensure_go
  grep -qx 'mise use --global --pin go@1.26.8' "$SETUP_TEST_LOG"
  [[ "$PATH" == "$test_dir/runtime/bin:"* ]]
  parse_args --dry-run --components go,c,cpp --project "$test_dir/go-project" --editor code
  python3() { record "python3 $*"; }
  configure_project
  grep -Fqx "mise use --path $test_dir/go-project/mise.toml --pin go@$GO_VERSION" "$SETUP_TEST_LOG"
  grep -Fq -- '--components go,c,cpp,python,fonts' "$SETUP_TEST_LOG"
)

# New language choices must reach real provisioning through main.
for manager in apt dnf yum pacman brew; do
  for language in go c cpp; do
    (
      : > "$SETUP_TEST_LOG"
      PKG_MANAGER="$manager"
      detect_os() { OS=Linux; }
      detect_pkg_manager() { :; }
      require_sudo() { SUDO=""; }
      run_pkg_update_once() { :; }
      xcode-select() { :; }
      cc() { :; }
      c++() { :; }
      cmake() { :; }
      go() { :; }
      save_installed_state() { :; } # State publication is covered by check-state.py.
      main --components "$language" --yes
      if [[ "$language" == go ]]; then
        grep -qx "mise use --global --pin go@$GO_VERSION" "$SETUP_TEST_LOG"
        if grep -qx 'package cmake' "$SETUP_TEST_LOG"; then exit 1; fi
        if grep -Eq '^package (build-essential|gcc|gcc-c\+\+|base-devel|pkg-config)$' "$SETUP_TEST_LOG"; then
          printf 'Selecting Go alone must not install C/C++ build tools.\n' >&2
          exit 1
        fi
      else
        grep -qx 'package cmake' "$SETUP_TEST_LOG"
        if grep -q '^mise ' "$SETUP_TEST_LOG"; then exit 1; fi
        case "$manager" in
          apt) grep -qx 'package build-essential' "$SETUP_TEST_LOG" ;;
          dnf|yum) grep -qx 'package gcc-c++' "$SETUP_TEST_LOG" ;;
          pacman) grep -qx 'package base-devel' "$SETUP_TEST_LOG" ;;
          brew) grep -qx 'package pkg-config' "$SETUP_TEST_LOG" ;;
        esac
      fi
    )
  done
done

ensure_pnpm
ensure_pnpm
[[ "$(command -v pnpm)" == "${PNPM_HOME}/bin/pnpm" ]]
[[ ":${PATH}:" == *":${PNPM_HOME}:"* ]]
[[ "$(grep -c 'curl .*get.pnpm.io/install.sh' "${SETUP_TEST_LOG}")" == 1 ]]
(
  unset PNPM_HOME
  OS=Darwin
  pnpm() { :; }
  ensure_pnpm
  [[ "${PNPM_HOME}" == "${HOME}/Library/pnpm" ]] || { printf 'macOS must use the native pnpm home.\n' >&2; exit 1; }
  [[ ":${PATH}:" == *":${PNPM_HOME}/bin:"* ]] || exit 1
)
install_pnpm_global_if_missing missing-test-command typescript
install_pnpm_global_if_missing sh should-not-install
COMPONENTS=codex EDITOR=none
install_skill_if_missing https://uizze.sh/ uizze
grep -qx 'pnpm add --global typescript' "${SETUP_TEST_LOG}"
grep -qx 'pnpm dlx skills list --global --agent codex --json' "${SETUP_TEST_LOG}"
grep -Fqx 'pnpm dlx skills add https://uizze.sh/ --global --agent codex --skill * --yes' "${SETUP_TEST_LOG}"
grep -q 'should-not-install' "${SETUP_TEST_LOG}" && exit 1
grep -Eq '(^|[^[:alnum:]_])(npm|npx)([^[:alnum:]_]|$)' "${REPO_ROOT}/devready" && exit 1

# Skills-only selections target installed assistants, or the shared skills directory.
(
  parse_args --components superpowers,ponytail,ui-taste --yes
  [[ "$COMPONENTS" == superpowers,ponytail,ui-taste,node && "$EDITOR" == none ]]
  : > "${SETUP_TEST_LOG}"
  install_skill_if_missing https://uizze.sh/ uizze
  grep -Fqx 'pnpm dlx skills list --global --agent universal --json' "${SETUP_TEST_LOG}"
  grep -Fqx 'pnpm dlx skills add https://uizze.sh/ --global --agent universal --skill * --yes' "${SETUP_TEST_LOG}"
  [[ "$(grep -c '^pnpm ' "${SETUP_TEST_LOG}")" == 2 ]]
  (
    pnpm() {
      record "pnpm $*"
      printf '[{"name":"uizze","path":"%s/.agents/skills/uizze","agents":[]}]\n' "$HOME"
    }
    : > "${SETUP_TEST_LOG}"
    install_skill_if_missing https://uizze.sh/ uizze
    grep -Fqx 'pnpm dlx skills list --global --agent universal --json' "${SETUP_TEST_LOG}"
    [[ "$(grep -c '^pnpm ' "${SETUP_TEST_LOG}")" == 1 ]]
  )
  (
    pnpm() {
      record "pnpm $*"
      if [[ "$3" == list ]]; then
        printf '[{"name":"uizze","path":"%s/agents/skills/uizze","agents":["Universal"]}]\n' "$XDG_CONFIG_HOME"
      fi
    }
    : > "${SETUP_TEST_LOG}"
    install_skill_if_missing https://uizze.sh/ uizze
    grep -Fqx 'pnpm dlx skills add https://uizze.sh/ --global --agent universal --skill * --yes' "${SETUP_TEST_LOG}"
  )

  for pair in codex:codex claude:claude-code copilot:github-copilot cursor-agent:cursor cursor:cursor gemini:gemini-cli opencode:opencode; do
    binary="${test_dir}/bin/${pair%%:*}"
    printf '#!/bin/sh\nexit 0\n' > "$binary"
    chmod +x "$binary"
    : > "${SETUP_TEST_LOG}"
    install_skill_if_missing https://uizze.sh/ uizze
    grep -Fqx "pnpm dlx skills list --global --agent ${pair#*:} --json" "${SETUP_TEST_LOG}"
    grep -Fqx "pnpm dlx skills add https://uizze.sh/ --global --agent ${pair#*:} --skill * --yes" "${SETUP_TEST_LOG}"
    [[ "$(grep -c '^pnpm ' "${SETUP_TEST_LOG}")" == 2 ]]
    rm "$binary"
  done

  # Several detected assistants receive skills; Cursor aliases share one destination.
  codex() { :; }
  claude() { :; }
  cursor() { :; }
  cursor-agent() { :; }
  : > "${SETUP_TEST_LOG}"
  install_skill_if_missing https://uizze.sh/ uizze
  [[ "$(grep -c '^pnpm dlx skills add ' "${SETUP_TEST_LOG}")" == 3 ]]

  # Explicit destinations take precedence over other installed assistants.
  parse_args --components codex,ui-taste --yes
  : > "${SETUP_TEST_LOG}"
  install_skill_if_missing https://uizze.sh/ uizze
  grep -Fqx 'pnpm dlx skills add https://uizze.sh/ --global --agent codex --skill * --yes' "${SETUP_TEST_LOG}"
  [[ "$(grep -c '^pnpm dlx skills add ' "${SETUP_TEST_LOG}")" == 1 ]]

  # Canonical skills must not suppress the separate links Claude needs.
  (
    parse_args --components codex,claude,ui-taste --yes
    pnpm() {
      record "pnpm $*"
      if [[ "$3" == list ]]; then
        printf '[{"name":"uizze","path":"%s/.agents/skills/uizze","agents":["Codex"],"source":"uizze"}]\n' "$HOME"
      fi
    }
    : > "${SETUP_TEST_LOG}"
    install_skill_if_missing https://uizze.sh/ uizze
    grep -Fqx 'pnpm dlx skills add https://uizze.sh/ --global --agent claude-code --skill * --yes' "${SETUP_TEST_LOG}"
    [[ "$(grep -c '^pnpm dlx skills add ' "${SETUP_TEST_LOG}")" == 1 ]]
  )

  # Detection still respects skills that are already installed.
  parse_args --components ui-taste --yes
  pnpm() {
    record "pnpm $*"
    printf '[{"name":"uizze","path":"%s/.agents/skills/uizze","agents":["Codex","Claude Code","Cursor"]}]\n' "$HOME"
  }
  : > "${SETUP_TEST_LOG}"
  install_skill_if_missing https://uizze.sh/ uizze
  [[ "$(grep -c '^pnpm dlx skills list ' "${SETUP_TEST_LOG}")" == 3 ]]
  if grep -q '^pnpm dlx skills add ' "${SETUP_TEST_LOG}"; then exit 1; fi
)

# Laya provisioning installs global guidance only for the selected CLI clients.
(
  mkdir -p "${LAYA_VENV_DIR}/bin"
  for tool in python laya-mcp-server laya-serve; do
    printf '#!/bin/sh\nexit 0\n' > "${LAYA_VENV_DIR}/bin/${tool}"
    chmod +x "${LAYA_VENV_DIR}/bin/${tool}"
  done
  backup_file() { :; }
  codex() { record "codex $*"; }
  claude() { [[ "$*" != 'mcp get laya-jev' ]] || return 1; record "claude $*"; }
  python3() { record "python3 $*"; }
  for selection in laya laya,codex laya,claude; do
    : > "${SETUP_TEST_LOG}"
    parse_args --components "${selection}" --headless --yes
    ensure_laya_jev_middleware
    if selected codex; then
      grep -Fqx "python3 ${REPO_ROOT}/scripts/configure-project.py --jev-instructions ${CODEX_HOME:-$HOME/.codex}/AGENTS.md" "${SETUP_TEST_LOG}"
    elif selected claude; then
      grep -Fqx "python3 ${REPO_ROOT}/scripts/configure-project.py --jev-instructions ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/CLAUDE.md" "${SETUP_TEST_LOG}"
    else
      [[ ! -s "${SETUP_TEST_LOG}" ]]
    fi
  done
)

# Language servers use the selected languages and reuse existing installations.
for manager in apt dnf yum pacman brew; do
  (
    : > "$SETUP_TEST_LOG"
    PKG_MANAGER="$manager"
    parse_args --dry-run --components go,c,cpp,lsp
    install_system_pkg() {
      record "package $*"
      local server_path="$LOCAL_BIN/clangd"
      if [[ "$1" == llvm ]]; then server_path="$test_dir/llvm/bin/clangd"; fi
      mkdir -p "$(dirname "$server_path")"
      printf '#!/bin/sh\nexit 0\n' > "$server_path"
      chmod +x "$server_path"
    }
    brew() { [[ "$*" == '--prefix llvm' ]] && printf '%s/llvm\n' "$test_dir"; }
    go() {
      [[ "$*" == 'install golang.org/x/tools/gopls@latest' && "$GOBIN" == "$LOCAL_BIN" ]]
      record "go $*"
      printf '#!/bin/sh\nexit 0\n' > "$GOBIN/gopls"
      chmod +x "$GOBIN/gopls"
    }
    ensure_tools
    ensure_tools
    [[ "$(grep -c '^go install ' "$SETUP_TEST_LOG")" == 1 ]]
    [[ "$(grep -c '^package ' "$SETUP_TEST_LOG")" == 1 ]]
    case "$manager" in
      apt) grep -qx 'package clangd' "$SETUP_TEST_LOG" ;;
      dnf|yum) grep -qx 'package clang-tools-extra' "$SETUP_TEST_LOG" ;;
      pacman) grep -qx 'package clang' "$SETUP_TEST_LOG" ;;
      brew) grep -qx 'package llvm' "$SETUP_TEST_LOG" ;;
    esac
    "$LOCAL_BIN/clangd" --version
    rm "$LOCAL_BIN/clangd" "$LOCAL_BIN/gopls"
    go() { return 1; }
    if ensure_tools; then printf 'Failed gopls installation must fail setup.\n' >&2; exit 1; fi
  )
done

fc-match() {
  if [[ "$2" == '%{file}' ]]; then
    if [[ "${font_cache_broken:-false}" == true ]]; then
      printf '/fonts/OpenDyslexic-Bold.woff'
    else
      printf '%s/fonts/JetBrainsMono/JetBrainsMonoNerdFontMono-Regular.ttf' "${XDG_DATA_HOME}"
    fi
    return
  fi
  # Some Linux fallback matches echo the requested family even when absent.
  printf 'JetBrainsMono Nerd Font Mono'
}
fc-scan() {
  if [[ "$3" == */JetBrainsMonoNerdFontMono-Regular.ttf && -f "$3" ]]; then
    printf 'JetBrainsMono Nerd Font Mono'
  else
    printf OpenDyslexic
  fi
}
fc-list() {
  [[ -f "${XDG_DATA_HOME}/fonts/JetBrainsMono/JetBrainsMonoNerdFontMono-Regular.ttf" ]] || return 1
  if [[ "$1" != -q ]]; then
    printf 'JetBrainsMono Nerd Font Mono\n'
  fi
}
fc-cache() { record "fc-cache $*"; }
unzip() {
  record "unzip $*"
  [[ "$3" == 'JetBrainsMonoNerdFontMono-*.ttf' ]]
  : > "$5/JetBrainsMonoNerdFontMono-Regular.ttf"
}
gsettings() {
  record "gsettings $*"
  case "$*" in
    list-schemas) printf '%s\n' org.gnome.desktop.interface org.gnome.Terminal.ProfilesList ;;
    'get org.gnome.desktop.interface monospace-font-name') printf "'Monospace 13'\n" ;;
    'get org.gnome.Terminal.ProfilesList default') printf "'test-profile'\n" ;;
  esac
}
export DBUS_SESSION_BUS_ADDRESS=test
ensure_jetbrains_mono_font
[[ -f "${XDG_DATA_HOME}/fonts/JetBrainsMono/JetBrainsMonoNerdFontMono-Regular.ttf" ]] || {
  printf 'A fallback match must not prevent installing the missing font.\n' >&2
  exit 1
}
font_config="${XDG_CONFIG_HOME}/fontconfig/conf.d/60-jetbrains-mono-nerd.conf"
cp "${font_config}" "${test_dir}/font-config-before"
ensure_jetbrains_mono_font
cmp "${font_config}" "${test_dir}/font-config-before"
[[ "$(grep -c 'curl .*JetBrainsMono.zip' "${SETUP_TEST_LOG}")" == 1 ]]
grep -q '<family>JetBrainsMono Nerd Font Mono</family>' "${font_config}"
grep -qx 'gsettings set org.gnome.desktop.interface monospace-font-name JetBrainsMono Nerd Font Mono 13' "${SETUP_TEST_LOG}"
grep -q 'test-profile/ use-system-font true' "${SETUP_TEST_LOG}"

unset DBUS_SESSION_BUS_ADDRESS
: > "${SETUP_TEST_LOG}"
SSH_CONNECTION='test' ensure_jetbrains_mono_font
grep -q gsettings "${SETUP_TEST_LOG}" && exit 1
rm "${XDG_DATA_HOME}/fonts/JetBrainsMono/JetBrainsMonoNerdFontMono-Regular.ttf"
font_download_fails=true
if ensure_jetbrains_mono_font; then
  printf 'Failed font downloads must fail setup.\n' >&2
  exit 1
fi
[[ -z "$(compgen -G "${TMPDIR}/devready-font.*")" ]]

brew() {
  record "brew $*"
  if [[ "$1" == list ]]; then
    [[ "${font_cask_present:-false}" == true ]]
  else
    font_cask_present=true
  fi
}
osascript() { record "osascript $*"; cat >> "${SETUP_TEST_LOG}"; }
: > "${CONFIG_DIR}/Dracula.terminal"
OS=Darwin
: > "${SETUP_TEST_LOG}"
ensure_jetbrains_mono_font
ensure_jetbrains_mono_font
[[ "$(grep -c '^brew install --cask font-jetbrains-mono-nerd-font$' "${SETUP_TEST_LOG}")" == 1 ]]
grep -q 'set font name of settings set "Dracula" to "JetBrainsMonoNFM-Regular"' "${SETUP_TEST_LOG}"
grep -q 'set startup settings to settings set "Dracula"' "${SETUP_TEST_LOG}"
: > "${SETUP_TEST_LOG}"
SSH_CONNECTION='test' ensure_jetbrains_mono_font
grep -q osascript "${SETUP_TEST_LOG}" && exit 1

printf 'keep this line\n' > "${test_dir}/shellrc"
append_shell_line "${test_dir}/shellrc" 'export TEST_SETTING=1'
append_shell_line "${test_dir}/shellrc" 'export TEST_SETTING=1'
[[ "$(grep -c TEST_SETTING "${test_dir}/shellrc")" == 1 ]]
grep -qx 'keep this line' "${test_dir}/shellrc.devready.bak"
printf 'updated settings\n' > "${test_dir}/old-shellrc"
printf 'original settings\n' > "${test_dir}/old-shellrc.d-environment.bak"
append_shell_line "${test_dir}/old-shellrc" 'export TEST_SETTING=1'
grep -qx 'original settings' "${test_dir}/old-shellrc.d-environment.bak"
[[ ! -e "${test_dir}/old-shellrc.devready.bak" ]]

# A themes-only directory is not an installed Oh My Zsh checkout.
mkdir -p "${test_dir}/omz/custom/themes/powerlevel10k/.git"
printf 'keep custom settings\n' > "${test_dir}/omz/custom/example.zsh"
printf 'keep theme git objects\n' > "${test_dir}/omz/custom/themes/powerlevel10k/.git/theme.pack"
chmod 444 "${test_dir}/omz/custom/themes/powerlevel10k/.git/theme.pack"
for iteration in 1 2; do
  (
    # These settings are deliberately isolated to this installation attempt.
    # shellcheck disable=SC2030
    OS=Linux OMZ_DIR="${test_dir}/omz"
    zsh() { :; }
    curl() {
      record omz-download
      cat <<'EOF'
mkdir -p "$ZSH/custom"
printf 'installed\n' > "$ZSH/oh-my-zsh.sh"
printf 'default\n' > "$ZSH/custom/example.zsh"
EOF
    }
    backup_file() { :; }
    # Stop before editing real shell files; this case checks the installation.
    update_or_append_shell_var() { exit 0; }
    ensure_omz_with_themes
  )
  [[ -f "${test_dir}/omz/oh-my-zsh.sh" ]] || {
    printf 'Oh My Zsh pass %s: an existing custom directory must not prevent installation.\n' "${iteration}" >&2
    exit 1
  }
done
[[ "$(grep -c '^omz-download$' "${SETUP_TEST_LOG}")" == 1 ]]
grep -qx 'keep custom settings' "${test_dir}/omz/custom/example.zsh"

cat > "${test_dir}/rtk-stub" <<'EOF'
#!/bin/sh
case "$*" in
  --version) printf 'rtk test\n' ;;
  'gain --help') exit 0 ;;
  *) exit 1 ;;
esac
EOF
(
  : > "${SETUP_TEST_LOG}"
  PKG_MANAGER=dnf
  append_shell_line() { record "shell $*"; }
  curl() {
    record "curl $*"
    [[ "$2" == https://raw.githubusercontent.com/rtk-ai/rtk/master/install.sh ]] || return 1
    cat <<'EOF'
cp "$SETUP_TEST_DIR/rtk-stub" "$RTK_INSTALL_DIR/rtk"
chmod +x "$RTK_INSTALL_DIR/rtk"
EOF
  }
  ensure_terminal_tools
  ensure_terminal_tools
  [[ "$(grep -c '^curl .*rtk/master/install.sh$' "${SETUP_TEST_LOG}")" == 1 ]]
  grep -Fq "export PATH=\"\$HOME/.local/bin:\$PATH\"" "${SETUP_TEST_LOG}"
  rm "${LOCAL_BIN}/rtk"
  hash -r
  curl() { record failed-rtk-download; return 1; }
  if ensure_rtk; then printf 'Failed RTK downloads must fail setup.\n' >&2; exit 1; fi
  grep -qx failed-rtk-download "${SETUP_TEST_LOG}"
  [[ ! -e "${LOCAL_BIN}/rtk" ]]
)
(
  : > "${SETUP_TEST_LOG}"
  PKG_MANAGER=brew
  install_system_pkg() {
    record "package $*"
    if [[ "$1" == rtk ]]; then
      cp "${test_dir}/rtk-stub" "${LOCAL_BIN}/rtk"
      chmod +x "${LOCAL_BIN}/rtk"
    fi
  }
  ensure_terminal_tools
  ensure_terminal_tools
  [[ "$(grep -c '^package rtk$' "${SETUP_TEST_LOG}")" == 1 ]]
  rm "${LOCAL_BIN}/rtk"
  rtk() { [[ "$*" == --version ]]; }
  if ensure_rtk; then printf 'An unrelated rtk binary must fail validation.\n' >&2; exit 1; fi
)

source "${REPO_ROOT}/lib/doctor.sh"
(
  parse_args --doctor --components go,c,cpp
  git() { :; }
  gh() { :; }
  go() {
    [[ "$GOTOOLCHAIN" == local ]] || return 1
    printf 'go version go%s linux/amd64\n' "$GO_VERSION"
  }
  gofmt() { :; }
  cc() { :; }
  c++() { :; }
  cmake() { :; }
  run_doctor
  parse_args --doctor --components go,c,cpp,lsp
  node() { printf '%s.0.0\n' "$NODE_MAJOR_VERSION"; }
  bash-language-server() { :; }
  gopls() { :; }
  clangd() { :; }
  run_doctor
  gopls() { return 1; }
  clangd() { return 1; }
  if run_doctor; then printf 'Doctor must catch unusable Go/C/C++ language servers.\n' >&2; exit 1; fi
  [[ "$DOCTOR_FAILURES" == 2 ]]
  parse_args --doctor --components go,c,cpp
  go() { printf 'go version go1.0.0 linux/amd64\n'; }
  if run_doctor; then printf 'Doctor must catch an incorrect Go version.\n' >&2; exit 1; fi
  [[ "$DOCTOR_FAILURES" == 1 ]]
  parse_args --doctor --components c
  cc() { return 1; }
  if run_doctor; then printf 'Doctor must catch a broken C compiler.\n' >&2; exit 1; fi
  [[ "$DOCTOR_FAILURES" == 1 ]]
  parse_args --doctor --components cpp
  c++() { return 1; }
  if run_doctor; then printf 'Doctor must catch a broken C++ compiler.\n' >&2; exit 1; fi
  [[ "$DOCTOR_FAILURES" == 1 ]]
)
(
  parse_args --doctor --components fonts
  OS=Linux
  git() { :; }
  gh() { :; }
  if run_doctor; then printf 'Doctor must detect a missing font despite a fallback match.\n' >&2; exit 1; fi
  [[ "${DOCTOR_FAILURES}" == 1 ]]
  : > "${XDG_DATA_HOME}/fonts/JetBrainsMono/JetBrainsMonoNerdFontMono-Regular.ttf"
  run_doctor
  font_cache_broken=true
  if run_doctor; then printf 'Doctor must detect a cache that selects the wrong font file.\n' >&2; exit 1; fi
  [[ "${DOCTOR_FAILURES}" == 1 ]]
)
(
  parse_args --doctor --components shell
  OMZ_DIR="${test_dir}/missing-omz"
  git() { :; }
  gh() { :; }
  zsh() { :; }
  if run_doctor; then printf 'Doctor must detect an incomplete Oh My Zsh installation.\n' >&2; exit 1; fi
  [[ "${DOCTOR_FAILURES}" == 1 ]]
  mkdir -p "${OMZ_DIR}"
  : > "${OMZ_DIR}/oh-my-zsh.sh"
  run_doctor
)
parse_args --doctor --components tools
git() { :; }
gh() { record "gh $*"; [[ "${auth_fails:-false}" == false ]]; }
rg() { :; }
fd() { :; }
fzf() { :; }
jq() { :; }
tmux() { :; }
shellcheck() { :; }
rtk() { [[ "$*" == --version || "${rtk_fails:-false}" == false ]]; }
: > "${SETUP_TEST_LOG}"
run_doctor
[[ ! -s "${SETUP_TEST_LOG}" ]]
auth_fails=true
run_doctor
[[ ! -s "${SETUP_TEST_LOG}" ]]
parse_args --doctor --auth --components tools
if run_doctor; then printf 'Opt-in authentication checks must detect missing login.\n' >&2; exit 1; fi
[[ "${DOCTOR_FAILURES}" == 0 && "${AUTH_FAILURES}" == 1 ]]
grep -qx 'gh auth status' "${SETUP_TEST_LOG}"
(
  codex() { if [[ "$*" == --version ]]; then return; fi; record "codex $*"; return 1; }
  claude() { if [[ "$*" == --version ]]; then return; fi; record "claude $*"; return 1; }
  node() { printf '%s.0.0\n' "$NODE_MAJOR_VERSION"; }
  parse_args --doctor --components codex,claude
  : > "${SETUP_TEST_LOG}"
  run_doctor
  if grep -Eq '^(gh auth|codex login|claude auth)' "${SETUP_TEST_LOG}"; then
    printf 'Default doctor must not query account logins.\n' >&2; exit 1
  fi
  parse_args --doctor --auth --components codex,claude
  if run_doctor; then printf 'All selected agent logins must be checked with --auth.\n' >&2; exit 1; fi
  [[ "${DOCTOR_FAILURES}" == 0 && "${AUTH_FAILURES}" == 3 ]]
  grep -qx 'codex login status' "${SETUP_TEST_LOG}"
  grep -qx 'claude auth status' "${SETUP_TEST_LOG}"
)
parse_args --doctor --components tools
auth_fails=false rtk_fails=true
if run_doctor; then printf 'Doctor must fail for an unusable RTK binary.\n' >&2; exit 1; fi
[[ "${DOCTOR_FAILURES}" == 1 ]]
version_matches 22 printf '22.20.0'
if version_matches 22 printf '20.20.0'; then exit 1; fi
(
  : > "${SETUP_TEST_LOG}"
  OS=Darwin PKG_MANAGER=brew HEADLESS=false
  install_system_pkg() { record "pkg $*"; }
  docker() { grep -qx "pkg docker-$1" "${SETUP_TEST_LOG}"; }
  brew() { record "unexpected brew $*"; return 1; }
  ensure_docker
  ensure_docker
  [[ "$(grep -c '^pkg docker-compose$' "${SETUP_TEST_LOG}")" -eq 1 ]]
  [[ "$(grep -c '^pkg docker-buildx$' "${SETUP_TEST_LOG}")" -eq 1 ]]
  grep -q 'unexpected brew' "${SETUP_TEST_LOG}" && exit 1
  true
)

printf '\nSelection, language toolchains, pnpm, font, RTK, Docker plugins, repeat-run, and read-only doctor checks passed.\n'
