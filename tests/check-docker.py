#!/usr/bin/env python3
"""Run Docker diagnostics against isolated CLI responses; never contact a daemon."""
import os
from pathlib import Path
import subprocess
import tempfile

REPO = Path(__file__).resolve().parents[1]
SCRIPT = r'''
source "$1/devready"
detect_os() { OS="$TEST_OS"; }
git() { :; }
curl() { :; }
gh() { :; }
id() {
  case "$*" in
    -un) printf 'tester\n' ;;
    -u) printf '1000\n' ;;
    -nG) printf '%s\n' "$TEST_SESSION_GROUPS" ;;
    '-nG tester') printf '%s\n' "$TEST_ACCOUNT_GROUPS" ;;
    *) printf 'unexpected id: %s\n' "$*" >> "$TEST_CALLS"; return 99 ;;
  esac
}
stat() {
  if [[ "$*" == '-c %G /var/run/docker.sock' || "$*" == '-c %G /run/docker.sock' ]]; then
    printf '%s\n' "$TEST_SOCKET_GROUP"
  else printf 'unexpected stat: %s\n' "$*" >> "$TEST_CALLS"; return 99; fi
}
systemctl() {
  if [[ "$*" == 'is-active docker' ]]; then
    printf '%s\n' "$TEST_SERVICE"
    [[ "$TEST_SERVICE" == active ]]
  else printf 'unexpected systemctl: %s\n' "$*" >> "$TEST_CALLS"; return 99; fi
}
docker() {
  case "$*" in
    'info --format {{.ServerVersion}}')
      if [[ "$TEST_CONNECTED" == true ]]; then printf '29.8.1\n'; else printf '%s\n' "$TEST_ERROR" >&2; return 1; fi ;;
    'context show') printf '%s\n' "$TEST_CONTEXT" ;;
    'context inspect --format {{.Endpoints.docker.Host}} '* ) printf '%s\n' "$TEST_ENDPOINT" ;;
    'compose version') [[ "$TEST_PLUGINS" != missing ]] ;;
    'buildx version') [[ "$TEST_PLUGINS" != missing ]] ;;
    *) printf 'unexpected docker: %s\n' "$*" >> "$TEST_CALLS"; return 99 ;;
  esac
}
sudo() { printf 'unexpected sudo\n' >> "$TEST_CALLS"; return 99; }
newgrp() { printf 'unexpected newgrp\n' >> "$TEST_CALLS"; return 99; }
usermod() { printf 'unexpected usermod\n' >> "$TEST_CALLS"; return 99; }
open() { printf 'unexpected open\n' >> "$TEST_CALLS"; return 99; }
if [[ "$TEST_MISSING" == true ]]; then unset -f docker; PATH="$TEST_EMPTY_PATH"; fi
main --doctor --components docker
'''

with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    calls = root / 'unexpected-calls'
    baseline = dict(os.environ, XDG_CONFIG_HOME=str(root / 'config'),
                    TEST_CALLS=str(calls), TEST_EMPTY_PATH=str(root / 'empty'),
                    TEST_OS='Linux', TEST_CONNECTED='false', TEST_PLUGINS='', TEST_MISSING='false',
                    TEST_CONTEXT='default', TEST_ENDPOINT='unix:///var/run/docker.sock',
                    TEST_ERROR='permission denied while trying to connect to the docker API at unix:///var/run/docker.sock',
                    TEST_SESSION_GROUPS='tester sudo', TEST_ACCOUNT_GROUPS='tester sudo docker',
                    TEST_SOCKET_GROUP='docker', TEST_SERVICE='active')
    for name in ('DOCKER_HOST', 'DOCKER_CONTEXT', 'XDG_RUNTIME_DIR'):
        baseline.pop(name, None)

    def check(*expected, absent=(), succeeds=False, **overrides):
        result = subprocess.run(['bash', '-c', SCRIPT, 'docker-check', str(REPO)],
                                env=dict(baseline, **overrides), text=True, capture_output=True)
        output = result.stdout + result.stderr
        assert (result.returncode == 0) == succeeds, output
        for value in expected:
            assert value in output, (value, output)
        for value in absent:
            assert value not in output, (value, output)
        assert not calls.exists(), calls.read_text() if calls.exists() else ''
        return output

    check('already in the docker group', 'newgrp docker', 'log out',
          './devready --doctor --components docker', 'Installation: 1 problem(s).',
          absent=('usermod', 'systemctl start'))
    check('sudo usermod -aG docker', 'root-level', 'log out',
          TEST_ACCOUNT_GROUPS='tester sudo', absent=('already in the docker group',))
    check('socket permissions', 'ls -l /var/run/docker.sock',
          TEST_SESSION_GROUPS='tester sudo docker', absent=('usermod', 'newgrp docker'))
    check('socket permissions', TEST_SOCKET_GROUP='other', absent=('usermod', 'newgrp docker'))
    check('sudo systemctl start docker', TEST_SERVICE='inactive',
          TEST_ERROR='Cannot connect to the Docker daemon at unix:///var/run/docker.sock.', absent=('usermod',))
    check('journalctl -u docker', TEST_SERVICE='active',
          TEST_ERROR='Cannot connect to the Docker daemon at unix:///var/run/docker.sock.', absent=('systemctl start',))
    check('service manager', TEST_SERVICE='',
          TEST_ERROR='Cannot connect to the Docker daemon at unix:///var/run/docker.sock.', absent=('sudo systemctl start',))
    check('systemctl --user start docker', TEST_CONTEXT='rootless',
          TEST_ENDPOINT='unix:///run/user/1000/docker.sock', TEST_ERROR='connection refused',
          absent=('usermod', 'sudo systemctl'))
    check('open -a Docker', TEST_OS='Darwin', TEST_CONTEXT='desktop-linux',
          TEST_ENDPOINT='unix:///Users/tester/.docker/run/docker.sock', TEST_ERROR='connection refused',
          absent=('usermod', 'systemctl start'))
    check('Docker Desktop', TEST_CONTEXT='desktop-linux',
          TEST_ENDPOINT='unix:///home/tester/.docker/desktop/docker.sock', TEST_ERROR='connection refused',
          absent=('usermod', 'sudo systemctl'))
    check('remote', 'docker context ls', TEST_CONTEXT='remote', TEST_ENDPOINT='ssh://builder',
          TEST_ERROR='Permission denied (publickey).', absent=('usermod', 'newgrp docker', 'systemctl start'))
    check('remote', 'DOCKER_HOST', TEST_ENDPOINT='unix:///var/run/docker.sock',
          DOCKER_HOST='tcp://builder:2376', TEST_ERROR='x509: certificate has expired',
          absent=('usermod', 'systemctl start'))
    check('remote', 'DOCKER_CONTEXT', TEST_CONTEXT='remote', TEST_ENDPOINT='ssh://builder',
          DOCKER_CONTEXT='remote', DOCKER_HOST='unix:///var/run/docker.sock',
          TEST_ERROR='connection refused', absent=('sudo systemctl',))
    check('remote', 'DOCKER_HOST', TEST_ENDPOINT='tcp://localhost:2376',
          DOCKER_HOST='tcp://localhost:2376', absent=('usermod', 'newgrp docker'))
    check('custom', 'docker context ls', TEST_CONTEXT='colima',
          TEST_ENDPOINT='unix:///Users/tester/.colima/default/docker.sock', TEST_OS='Darwin',
          TEST_ERROR='connection refused', absent=('open -a Docker', 'usermod'))
    check('API version is too old', TEST_ERROR='client API version is too old',
          absent=('usermod', 'systemctl start', 'newgrp docker'))
    check('[OK] Docker daemon access', 'Installation: 0 problem(s).',
          TEST_CONNECTED='true', succeeds=True, absent=('newgrp docker',))
    check('[FAIL] Docker Compose', '[FAIL] Docker Buildx', 'Installation: 2 problem(s).',
          TEST_CONNECTED='true', TEST_PLUGINS='missing')
    check('[FAIL] Docker CLI', './devready --components docker', 'Installation: 1 problem(s).',
          TEST_MISSING='true', absent=('[FAIL] Docker Compose', '[FAIL] Docker Buildx'))

print('Docker diagnosis, session refresh, endpoint selection, platform remedies, and read-only checks passed.')
