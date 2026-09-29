#!/usr/bin/env bash
# Run only inside tests/ubuntu.Dockerfile: this installs real system packages.
set -euo pipefail

[[ "$(id -un)" == setup-test && "${HOME}" == /home/setup-test ]]
for tool in go cc c++ cmake mise; do
  if command -v "${tool}"; then
    printf 'Expected a clean image without %s.\n' "${tool}" >&2
    exit 1
  fi
done

state_file="${HOME}/.config/devready/installed.state"
if ./devready --yes; then
  printf 'Unattended setup must require a selection.\n' >&2
  exit 1
fi
[[ ! -e "${state_file}" ]]
./devready --components go,c,cpp --headless --yes
[[ -f "${state_file}" && "$(stat -c %a "${state_file}")" == 600 ]]

smoke_dir="$(mktemp -d)"
trap 'rm -rf "${smoke_dir}"' EXIT
export DEVREADY_SMOKE_DIR="${smoke_dir}"
cat > "${smoke_dir}/main.go" <<'EOF'
package main
import "fmt"
func main() { fmt.Println("go works") }
EOF
cat > "${smoke_dir}/main.c" <<'EOF'
#include <stdio.h>
int main(void) { puts("c works"); return 0; }
EOF
cat > "${smoke_dir}/main.cpp" <<'EOF'
#include <iostream>
int main() { std::cout << "cpp works\n"; }
EOF
cat > "${smoke_dir}/CMakeLists.txt" <<'EOF'
cmake_minimum_required(VERSION 3.16)
project(installer_smoke LANGUAGES C CXX)
add_executable(c-smoke main.c)
add_executable(cpp-smoke main.cpp)
EOF

# A new shell must find the runtimes through startup files, without inheriting
# the PATH used inside the installer process. No GitHub or agent login exists.
# shellcheck disable=SC2016
env PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin bash --login -c '
  set -euo pipefail
  export GOTOOLCHAIN=local
  go version
  go build -o "$DEVREADY_SMOKE_DIR/go-smoke" "$DEVREADY_SMOKE_DIR/main.go"
  [[ "$("$DEVREADY_SMOKE_DIR/go-smoke")" == "go works" ]]
  cmake -S "$DEVREADY_SMOKE_DIR" -B "$DEVREADY_SMOKE_DIR/build"
  cmake --build "$DEVREADY_SMOKE_DIR/build"
  [[ "$("$DEVREADY_SMOKE_DIR/build/c-smoke")" == "c works" ]]
  [[ "$("$DEVREADY_SMOKE_DIR/build/cpp-smoke")" == "cpp works" ]]
'

sha256sum "${state_file}" "${HOME}/.profile" "${HOME}/.bashrc" \
  "${HOME}/.zshrc" "${HOME}/.config/mise/config.toml" > "${smoke_dir}/before.sha256"
./devready --doctor
sha256sum --check "${smoke_dir}/before.sha256"
./devready --components go,c,cpp --headless --yes
sha256sum --check "${smoke_dir}/before.sha256"
./devready --doctor
printf '\nClean Ubuntu install, fresh-shell builds, saved-selection doctor, and repeat install passed.\n'
