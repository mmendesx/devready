#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/setup-dev-environment.sh"

test_dir="$(mktemp -d)"
trap 'rm -rf "${test_dir}"' EXIT
export SETUP_TEST_DIR="${test_dir}" SETUP_TEST_LOG="${test_dir}/calls"
export PNPM_HOME="${test_dir}/pnpm" XDG_DATA_HOME="${test_dir}/data"
export XDG_CONFIG_HOME="${test_dir}/config" TMPDIR="${test_dir}/tmp"
mkdir -p "${test_dir}/bin" "${TMPDIR}" "${test_dir}/configuration"
for tool in cat chmod cp dirname env grep mkdir mktemp rm sh cmp awk uname; do
  ln -s "$(command -v "${tool}")" "${test_dir}/bin/${tool}"
done
export PATH="${test_dir}/bin"
CONFIG_DIR="${test_dir}/configuration"
LOCAL_BIN="${test_dir}/bin"
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
EOF

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
[[ "${HEADLESS}" == true ]]
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

ensure_pnpm
ensure_pnpm
[[ "$(command -v pnpm)" == "${PNPM_HOME}/bin/pnpm" ]]
[[ ":${PATH}:" == *":${PNPM_HOME}:"* ]]
[[ "$(grep -c 'curl .*get.pnpm.io/install.sh' "${SETUP_TEST_LOG}")" == 1 ]]
install_pnpm_global_if_missing missing-test-command typescript
install_pnpm_global_if_missing sh should-not-install
COMPONENTS=codex EDITOR=none
install_skill_if_missing https://uizze.sh/ uizze
grep -qx 'pnpm add --global typescript' "${SETUP_TEST_LOG}"
grep -qx 'pnpm dlx skills list --global --agent codex' "${SETUP_TEST_LOG}"
grep -Fqx 'pnpm dlx skills add https://uizze.sh/ --global --agent codex --skill * --yes' "${SETUP_TEST_LOG}"
grep -q 'should-not-install' "${SETUP_TEST_LOG}" && exit 1
grep -Eq '(^|[^[:alnum:]_])(npm|npx)([^[:alnum:]_]|$)' "${REPO_ROOT}/setup-dev-environment.sh" && exit 1

fc-match() {
  if [[ -f "${XDG_DATA_HOME}/fonts/JetBrainsMono/JetBrainsMonoNerdFontMono-Regular.ttf" ]]; then
    printf 'JetBrainsMono Nerd Font Mono'
  else
    printf 'DejaVu Sans Mono'
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
[[ -z "$(compgen -G "${TMPDIR}/d-environment-font.*")" ]]

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
grep -qx 'keep this line' "${test_dir}/shellrc.d-environment.bak"

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
parse_args --doctor --components tools
git() { :; }
gh() { [[ "${auth_fails:-false}" == false ]]; }
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
if run_doctor; then printf 'Doctor must fail for missing authentication.\n' >&2; exit 1; fi
[[ "${DOCTOR_FAILURES}" == 1 ]]
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

printf '\nProfile, pnpm, font, RTK, Docker plugins, repeat-run, and read-only doctor checks passed.\n'
