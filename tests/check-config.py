#!/usr/bin/env python3
import importlib.util
import json
import os
from pathlib import Path
import stat
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
    secret = project / ".env.d-environment"
    assert stat.S_IMODE(secret.stat().st_mode) == 0o600
    secret_before = secret.read_bytes()
    assert "/.env.d-environment" in (project / ".gitignore").read_text().splitlines()
    assert "existing-rule" in (project / ".gitignore").read_text().splitlines()
    assert (project / "eslint.config.mjs").exists()
    (project / "eslint.config.mjs").write_text("custom configuration")
    configure.configure_project(project, "cursor", "postgres,redis")
    assert workspace.read_bytes() == before
    assert secret.read_bytes() == secret_before
    assert (project / "eslint.config.mjs").read_text() == "custom configuration"
    assert (project / ".gitignore").read_text().count("/.env.d-environment") == 1

    path = root / ".copilot/mcp-config.json"
    path.parent.mkdir()
    path.write_text(json.dumps({"mcpServers": {"existing": {"command": "keep-me"}}}))
    configure.configure_mcp("copilot", "/path with spaces/laya", user_dir=root)
    result = json.loads(path.read_text())
    assert result["mcpServers"]["existing"]["command"] == "keep-me"
    assert result["mcpServers"]["laya-jev"]["command"] == "/path with spaces/laya"
    assert result["mcpServers"]["laya-jev"]["tools"] == ["*"]
    before = path.read_bytes()
    modified = path.stat().st_mtime_ns
    configure.configure_mcp("copilot", "/path with spaces/laya", user_dir=root)
    assert path.read_bytes() == before and path.stat().st_mtime_ns == modified
    path.write_text("invalid JSON")
    try:
        configure.configure_mcp("copilot", "changed", user_dir=root)
    except json.JSONDecodeError:
        pass
    else:
        raise AssertionError("Invalid existing configuration must not be overwritten")
    assert path.read_text() == "invalid JSON"
    configure.configure_mcp("cursor", "/path/laya", user_dir=root)
    assert json.loads((root / ".cursor/mcp.json").read_text())["mcpServers"]["laya-jev"]["env"]["LAYA_PRELOAD"] == "0"

print("Project configuration, backups, secrets, MCP registration, and repeat-run checks passed.")
