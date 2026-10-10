#!/usr/bin/env python3
"""Exercise saved selections through the public installer entry point."""
import os
from pathlib import Path
import stat
import subprocess
import tempfile

REPO = Path(__file__).resolve().parents[1]

with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    env = dict(os.environ, XDG_CONFIG_HOME=str(root / "config"),
               XDG_DATA_HOME=str(root / "data"),
               TEST_ROOT=str(root), JAVA_VERSION="25", PYTHON_VERSION="3.13",
               NODE_MAJOR_VERSION="22", GO_VERSION="1.27")
    state = root / "config/devready/installed.state"

    def run(script, *, succeeds=True):
        result = subprocess.run(
            ["bash", "-c", 'source "$1/devready"\n' + script,
             "state-test", str(REPO)], env=env, stdin=subprocess.DEVNULL,
            text=True, capture_output=True, cwd=root)
        assert (result.returncode == 0) == succeeds, result.stdout + result.stderr
        return result.stdout + result.stderr

    assert "explicit" in run("parse_args --yes", succeeds=False).lower()
    run("main --yes --dry-run", succeeds=False)
    assert not state.exists()
    run("parse_args --yes --components go,c,cpp")
    run("parse_args --yes --profile minimal")
    assert "saved" in run("main --doctor", succeeds=False).lower()
    run("main --components tools --auth --dry-run", succeeds=False)

    # Provisioning is isolated here; main still resolves options, validates commands,
    # captures actual command output, and publishes the successful selection.
    provision = r'''
detect_os() { OS=Linux; }
require_sudo() { SUDO=""; }
detect_pkg_manager() { PKG_MANAGER=apt; }
run_pkg_update_once() { :; }
install_system_pkg() { :; }
ensure_build_tools() { :; }
ensure_go() { :; }
ensure_node() { :; }
ensure_pnpm() { :; }
ensure_tools() { :; }
configure_project() { :; }
git() { printf 'git version 2.43.0\n'; }
curl() { printf 'curl 8.5.0\n'; }
gh() { printf 'gh version 2.45.0\n'; }
mise() { printf '2026.9.0\n'; }
go() { printf 'go version go1.27.1 linux/amd64\n'; }
cc() { printf 'cc test 14.2\n'; }
c++() { printf 'c++ test 14.2\n'; }
cmake() { printf 'cmake version 3.28.3\n'; }
node() { printf '22.22.3\n'; }
pnpm() { printf '10.32.0\n'; }
codex() { printf 'codex-cli 0.158.0\n'; }
'''
    run(provision + 'main --components go,c,cpp,codex --headless --yes')
    assert state.exists(), 'New installs must save their selection under devready'
    before = state.read_bytes()
    modified = state.stat().st_mtime_ns
    assert stat.S_IMODE(state.stat().st_mode) == 0o600
    assert b"GO_VERSION=1.27.1\n" in before
    assert b"NODE_MAJOR_VERSION=22.22.3\n" in before
    assert b"version.cc=cc test 14.2\n" in before
    assert b"version.codex=codex-cli 0.158.0\n" in before
    run(r'''
parse_args --doctor
[[ "$COMPONENTS" == go,c,cpp,codex,node && "$NODE_TOOLING" == false ]]
[[ "$GO_VERSION" == 1.27.1 && "$NODE_MAJOR_VERSION" == 22.22.3 ]]
[[ "$HEADLESS" == true && "$DOCTOR_AUTH" == false ]]
[[ -z "$PROJECT_DIR" && -z "$SERVICES" && -z "$JAVA_VERSION" && -z "$PYTHON_VERSION" ]]
parse_args --doctor --components claude
[[ "$COMPONENTS" == claude ]]
''')
    run(provision + 'main --components go,c,cpp,codex --headless --yes')
    assert state.read_bytes() == before and state.stat().st_mtime_ns == modified
    run('main --components claude --dry-run')
    assert state.read_bytes() == before
    run(provision + 'ensure_go() { return 1; }; main --components go --yes', succeeds=False)
    run(provision + 'go() { return 1; }; main --components go --yes', succeeds=False)
    assert state.read_bytes() == before, "Failed runs must retain the successful record"
    assert not list(state.parent.glob('.installed.*')), "Failed writes must clean up"

    # Existing installations keep their saved selection and tool directory.
    legacy_config = root / 'config/d-environment'
    state.parent.rename(legacy_config)
    legacy_tools = root / 'data/d-environment'
    legacy_tools.mkdir(parents=True)
    run(r'''
parse_args --doctor
[[ "$GO_VERSION" == 1.27.1 && "$COMPONENTS" == go,c,cpp,codex,node ]]
[[ "$CONFIG_DIR" == "$TEST_ROOT/config/d-environment" ]]
[[ "$TOOLS_DIR" == "$TEST_ROOT/data/d-environment" ]]
''')
    assert not state.parent.exists(), 'Doctor must not migrate files'
    run(provision + 'main --components go,c,cpp,codex --headless --yes')
    assert (legacy_config / 'installed.state').read_bytes() == before
    assert not state.exists(), 'Reuse the existing configuration on repeat installs'

    # Explicitly existing DevReady directories take precedence over legacy data.
    state.parent.mkdir()
    state.write_bytes(before.replace(b'GO_VERSION=1.27.1', b'GO_VERSION=1.27.2'))
    state.chmod(0o600)
    (root / 'data/devready').mkdir()
    run(r'''
parse_args --doctor
[[ "$GO_VERSION" == 1.27.2 && "$TOOLS_DIR" == "$TEST_ROOT/data/devready" ]]
''')
    state.write_bytes(before)

    env['D_ENV_BIN_DIR'] = str(root / 'old-bin')
    run('[[ "$LOCAL_BIN" == "$TEST_ROOT/old-bin" ]]')
    env['DEVREADY_BIN_DIR'] = str(root / 'new-bin')
    run('[[ "$LOCAL_BIN" == "$TEST_ROOT/new-bin" ]]')
    del env['D_ENV_BIN_DIR'], env['DEVREADY_BIN_DIR']

    # Paths and shell metacharacters remain literal, including newlines/backslashes.
    project = root / 'literal $(touch INJECTED) `touch INJECTED` \\ project\nnext\n'
    project.mkdir()
    env["TEST_PROJECT"] = str(project)
    run(provision + r'''
parse_args --components go --yes
PROJECT_DIR="$TEST_PROJECT"
save_installed_state
parse_args --doctor
[[ "$PROJECT_DIR" == "$TEST_PROJECT" ]]
''')
    assert not (root / 'INJECTED').exists()
    project.rmdir()
    run('parse_args --doctor')  # Doctor, rather than the parser, reports missing projects.
    run('parse_args --doctor --headless', succeeds=False)
    for corrupt in (b'FORMAT=99\n', before + b'COMPONENTS=go\n',
                    before + b'PATH=/tmp\n', before.replace(b'NODE_TOOLING=false', b'NODE_TOOLING=maybe'),
                    before.replace(b'GO_VERSION=1.27.1', b'GO_VERSION='),
                    b'$(touch INJECTED)\n'):
        state.write_bytes(corrupt)
        assert 'invalid' in run('parse_args --doctor', succeeds=False).lower()
        assert state.read_bytes() == corrupt
        assert not (root / 'INJECTED').exists()

    # A fresh login shell must discover installed runtimes without inheriting the
    # installer's PATH. Redirect startup-file writes into the fixture directory.
    data = root / 'data'
    shims = data / 'mise/shims'
    shims.mkdir(parents=True)
    go = shims / 'go'
    go.write_text('#!/bin/sh\nprintf "fresh shell runtime\\n"\n')
    go.chmod(0o755)
    env['XDG_DATA_HOME'] = str(data)
    run(r'''
LOCAL_BIN="$TEST_ROOT/bin"
mise() { :; }
append_shell_line() {
  local file="$TEST_ROOT/${1##*/}"
  printf '%s\n' "$2" >> "$file"
}
ensure_mise
''')
    fresh_env = dict(env, PATH='/usr/bin:/bin')
    fresh = subprocess.run(['bash', '--noprofile', '--norc', '-c',
                            'source "$TEST_ROOT/.profile"; command -v go'],
                           env=fresh_env, text=True, capture_output=True)
    assert fresh.returncode == 0 and fresh.stdout.strip() == str(go), fresh.stdout + fresh.stderr

print('Unattended selection, saved versions, literal data, failure recovery, and repeat-run checks passed.')
