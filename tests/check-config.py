#!/usr/bin/env python3
import importlib.util
import json
import os
from pathlib import Path
import stat
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("configure", Path(__file__).resolve().parents[1] / "scripts/configure-project.py")
configure = importlib.util.module_from_spec(spec)
spec.loader.exec_module(configure)

with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    project = root / "project with spaces"
    project.mkdir()
    (project / "package.json").write_text(json.dumps({"scripts": {"test": "test-command"}, "dependencies": {"@angular/core": "test"}}))
    (project / "pyproject.toml").write_text('[project]\nname = "example"\nversion = "0.1.0"\n')
    (project / "pom.xml").write_text("<project/>")
    (project / "development.code-workspace").write_text(json.dumps({"settings": {"editor.wordWrap": "on"}, "tasks": {"tasks": [{"label": "Custom", "command": "keep-me"}]}}))
    (project / ".gitignore").write_text("existing-rule\n")
    binary = root / "bin"
    binary.mkdir()
    for editor in ("code", "cursor"):
        launcher = binary / editor
        launcher.write_text("#!/bin/sh\nexit 0\n")
        launcher.chmod(0o755)
    os.environ["PATH"] = str(binary) + os.pathsep + os.environ["PATH"]

    # Selecting Laya distributes the same policy without losing existing guidance.
    instructions = root / "instruction project"
    instructions.mkdir()
    configure.configure_project(instructions, "none", "", "tools")
    assert not list(instructions.iterdir())
    agents = instructions / "AGENTS.md"
    agents.write_text("Keep the project's existing instructions.")
    agents.chmod(0o640)
    override = instructions / "AGENTS.override.md"
    override.write_text("Keep the active Codex override.\n")
    configure.configure_project(instructions, "none", "", "laya")
    instruction_paths = [instructions / name for name in (
        "AGENTS.md", "AGENTS.override.md", "CLAUDE.md", ".github/copilot-instructions.md",
    )]
    assert all(path.is_file() for path in instruction_paths), "Laya must install instructions for every project assistant"
    policy = (Path(__file__).resolve().parents[1] / "instructions/jev.md").read_text().strip()
    assert all(policy in path.read_text() for path in instruction_paths)
    assert agents.read_text().startswith("Keep the project's existing instructions.\n\n")
    assert override.read_text().startswith("Keep the active Codex override.\n")
    assert stat.S_IMODE(agents.stat().st_mode) == 0o640
    backup = agents.with_name("AGENTS.md.devready.bak")
    assert backup.read_text() == "Keep the project's existing instructions."
    snapshots = {path: (path.read_bytes(), path.stat().st_mtime_ns) for path in instruction_paths}
    configure.configure_project(instructions, "none", "", "laya")
    assert snapshots == {path: (path.read_bytes(), path.stat().st_mtime_ns) for path in instruction_paths}

    # Reruns upgrade only the managed block, preserving content on either side.
    agents.write_text(agents.read_text().replace(policy, "Old policy") + "\nKeep trailing guidance.\n")
    configure.configure_project(instructions, "none", "", "laya")
    assert policy in agents.read_text() and "Old policy" not in agents.read_text()
    assert agents.read_text().endswith("\nKeep trailing guidance.\n")
    assert backup.read_text() == "Keep the project's existing instructions."

    # A broken managed block must never consume unrelated instructions.
    for content in (
        "<!-- devready:jev:start -->\nKeep me.\n",
        "<!-- devready:jev:end -->\nKeep me.\n",
        "<!-- devready:jev:end --><!-- devready:jev:start -->",
        agents.read_text() + agents.read_text(),
    ):
        agents.write_text(content)
        try:
            configure.configure_project(instructions, "none", "", "laya")
        except ValueError:
            pass
        else:
            raise AssertionError("Malformed managed instructions must fail without overwriting the file")
        assert agents.read_text() == content

    # The standalone CLI also installs global instructions without project setup.
    for name in ("codex/AGENTS.md", "claude/CLAUDE.md"):
        target = root / "client instructions" / name
        subprocess.run([sys.executable, str(Path(configure.__file__)), "--jev-instructions", str(target)], check=True)
        assert policy in target.read_text()
    linked = root / "linked instructions.md"
    linked.symlink_to(target)
    target.write_text("Keep linked guidance.\n")
    configure.configure_jev_instructions(linked)
    assert linked.is_symlink() and policy in target.read_text()
    assert target.read_text().startswith("Keep linked guidance.\n")

    native = root / "native project"
    native.mkdir()
    go_module = "module example.com/app\n\ngo 1.27\n"
    (native / "go.mod").write_text(go_module)
    (native / "CMakeLists.txt").write_text("cmake_minimum_required(VERSION 3.16)\nproject(example C CXX)\n")
    configure.configure_project(native, "code", "")
    assert "golang.go" in json.loads((native / "development.code-workspace").read_text())["extensions"]["recommendations"]
    configure.configure_project(native, "code", "", "go,c,cpp")
    native_workspace = native / "development.code-workspace"
    native_before = native_workspace.read_bytes()
    native_data = json.loads(native_before)
    assert {"golang.go", "llvm-vs-code-extensions.vscode-clangd", "ms-vscode.cmake-tools"} <= set(native_data["extensions"]["recommendations"])
    assert native_data["settings"]["[go]"]["editor.defaultFormatter"] == "golang.go"
    assert native_data["settings"]["[c]"]["editor.defaultFormatter"] == "llvm-vs-code-extensions.vscode-clangd"
    assert native_data["settings"]["[cpp]"]["editor.defaultFormatter"] == "llvm-vs-code-extensions.vscode-clangd"
    native_tasks = {task["label"]: task for task in native_data["tasks"]["tasks"]}
    assert native_tasks["Go tests"]["args"] == ["test", "./..."]
    assert native_tasks["Go vet"]["args"] == ["vet", "./..."]
    assert native_tasks["CMake configure"]["args"] == ["-S", ".", "-B", "build", "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON"]
    configure.configure_project(native, "cursor", "", "go,c,cpp")
    assert native_workspace.read_bytes() == native_before
    assert (native / "go.mod").read_text() == go_module

    configure.configure_project(project, "code", "postgres,redis")
    workspace = project / "development.code-workspace"
    before = workspace.read_bytes()
    data = json.loads(before)
    assert data["settings"]["editor.wordWrap"] == "on"
    assert data["settings"]["terminal.integrated.fontFamily"] == "JetBrainsMono Nerd Font Mono"
    assert data["settings"]["npm.packageManager"] == "pnpm"
    assert data["tasks"]["tasks"][0]["command"] == "keep-me"
    assert {config["type"] for config in data["launch"]["configurations"]} == {"node", "java", "debugpy"}
    assert "Angular.ng-template" in data["extensions"]["recommendations"]
    secret = project / ".env.devready"
    assert stat.S_IMODE(secret.stat().st_mode) == 0o600
    secret_before = secret.read_bytes()
    assert "/.env.devready" in (project / ".gitignore").read_text().splitlines()
    assert "existing-rule" in (project / ".gitignore").read_text().splitlines()
    assert (project / "eslint.config.mjs").exists()
    (project / "eslint.config.mjs").write_text("custom configuration")
    configure.configure_project(project, "cursor", "postgres,redis")
    assert workspace.read_bytes() == before
    assert secret.read_bytes() == secret_before
    assert (project / "eslint.config.mjs").read_text() == "custom configuration"
    assert (project / ".gitignore").read_text().count("/.env.devready") == 1

    legacy_project = root / 'legacy project'
    legacy_project.mkdir()
    legacy_secret = legacy_project / '.env.d-environment'
    legacy_secret.write_text('POSTGRES_PASSWORD=keep-existing-credentials\n')
    legacy_secret.chmod(0o600)
    for _ in range(2):
        configure.configure_project(legacy_project, 'code', 'postgres,redis')
    assert legacy_secret.read_text() == 'POSTGRES_PASSWORD=keep-existing-credentials\n'
    assert not (legacy_project / '.env.devready').exists()
    assert (legacy_project / '.gitignore').read_text().count('/.env.d-environment') == 1
    legacy_workspace = json.loads((legacy_project / 'development.code-workspace').read_text())
    service_tasks = {task['label']: task for task in legacy_workspace['tasks']['tasks']}
    assert service_tasks['Start dev services']['args'][:3] == ['compose', '--env-file', '.env.d-environment']
    assert service_tasks['Stop dev services']['args'][:3] == ['compose', '--env-file', '.env.d-environment']

    backed_up = root / 'backed-up.json'
    backed_up.write_text('{"existing": 1}\n')
    original_backup = root / 'backed-up.json.d-environment.bak'
    original_backup.write_text('{"original": true}\n')
    configure.write_json(backed_up, {'updated': 2})
    assert original_backup.read_text() == '{"original": true}\n'
    assert not (root / 'backed-up.json.devready.bak').exists()

    path = root / ".cursor/mcp.json"
    path.parent.mkdir()
    path.write_text(json.dumps({"mcpServers": {"existing": {"command": "keep-me"}}}))
    configure.configure_cursor_mcp("/path with spaces/laya", user_dir=root)
    assert json.loads(path.with_name('mcp.json.devready.bak').read_text()) == {"mcpServers": {"existing": {"command": "keep-me"}}}
    result = json.loads(path.read_text())
    assert result["mcpServers"]["existing"]["command"] == "keep-me"
    assert result["mcpServers"]["laya-jev"]["command"] == "/path with spaces/laya"
    assert result["mcpServers"]["laya-jev"]["env"]["LAYA_PRELOAD"] == "0"
    before = path.read_bytes()
    modified = path.stat().st_mtime_ns
    configure.configure_cursor_mcp("/path with spaces/laya", user_dir=root)
    assert path.read_bytes() == before and path.stat().st_mtime_ns == modified
    path.write_text("invalid JSON")
    try:
        configure.configure_cursor_mcp("changed", user_dir=root)
    except json.JSONDecodeError:
        pass
    else:
        raise AssertionError("Invalid existing configuration must not be overwritten")
    assert path.read_text() == "invalid JSON"

print("Project configuration, backups, secrets, MCP registration, and repeat-run checks passed.")
