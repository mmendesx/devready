#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/setup-dev-environment.sh"

test_dir="$(mktemp -d)"
trap 'rm -rf "${test_dir}"' EXIT
export SETUP_TEST_DIR="${test_dir}" SETUP_TEST_LOG="${test_dir}/calls"
export PNPM_HOME="${test_dir}/pnpm" XDG_DATA_HOME="${test_dir}/data"
export XDG_CONFIG_HOME="${test_dir}/config" TMPDIR="${test_dir}/tmp"
mkdir -p "${test_dir}/bin" "${TMPDIR}"
for tool in cat chmod cp dirname env grep mkdir mktemp rm sh cmp; do
  ln -s "$(command -v "${tool}")" "${test_dir}/bin/${tool}"
done
export PATH="${test_dir}/bin"
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

OS=Linux PKG_MANAGER=dnf
ensure_node
grep -qx 'package nodejs' "${SETUP_TEST_LOG}"
ensure_pnpm
ensure_pnpm
[[ "$(command -v pnpm)" == "${PNPM_HOME}/bin/pnpm" ]]
[[ ":${PATH}:" == *":${PNPM_HOME}:"* ]]
[[ "$(grep -c 'curl .*get.pnpm.io/install.sh' "${SETUP_TEST_LOG}")" == 1 ]]
install_pnpm_global_if_missing missing-test-command typescript
install_pnpm_global_if_missing sh should-not-install
install_skill_if_missing https://uizze.sh/ uizze
grep -qx 'pnpm add --global typescript' "${SETUP_TEST_LOG}"
grep -qx 'pnpm dlx skills list' "${SETUP_TEST_LOG}"
grep -qx 'pnpm dlx skills add https://uizze.sh/' "${SETUP_TEST_LOG}"
! grep -q 'should-not-install' "${SETUP_TEST_LOG}"
! grep -Eq '(^|[^[:alnum:]_])(npm|npx)([^[:alnum:]_]|$)' "${REPO_ROOT}/setup-dev-environment.sh"

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
SSH_CONNECTION=test ensure_jetbrains_mono_font
! grep -q gsettings "${SETUP_TEST_LOG}"
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
osascript() { record "osascript $*"; }
OS=Darwin
: > "${SETUP_TEST_LOG}"
ensure_jetbrains_mono_font
ensure_jetbrains_mono_font
[[ "$(grep -c '^brew install --cask font-jetbrains-mono-nerd-font$' "${SETUP_TEST_LOG}")" == 1 ]]
grep -q 'default settings to "JetBrainsMonoNFM-Regular"' "${SETUP_TEST_LOG}"
grep -q 'startup settings to "JetBrainsMonoNFM-Regular"' "${SETUP_TEST_LOG}"
: > "${SETUP_TEST_LOG}"
SSH_CONNECTION=test ensure_jetbrains_mono_font
! grep -q osascript "${SETUP_TEST_LOG}"

printf '\npnpm and font smoke checks passed.\n'
