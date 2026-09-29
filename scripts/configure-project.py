#!/usr/bin/env python3
import argparse
import json
import os
from pathlib import Path
import secrets
import shlex
import shutil
import stat
import subprocess
import tempfile


def write_json(path, data):
    content = json.dumps(data, indent=2) + "\n"
    if path.exists() and path.read_text() == content:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    mode = stat.S_IMODE(path.stat().st_mode) if path.exists() else 0o600
    backup = path.with_name(path.name + ".devready.bak")
    legacy_backup = path.with_name(path.name + ".d-environment.bak")
    if path.exists() and not backup.exists() and not legacy_backup.exists():
        shutil.copy2(path, backup)
    with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, delete=False) as output:
        output.write(content)
        temporary = Path(output.name)
    try:
        temporary.chmod(mode)
        temporary.replace(path)
    finally:
        temporary.unlink(missing_ok=True)


def read_json(path):
    data = json.loads(path.read_text()) if path.exists() else {}
    if not isinstance(data, dict):
        raise ValueError(f"Expected a JSON object in {path}")
    return data


def configure_cursor_mcp(command, user_dir=None):
    user_dir = user_dir or Path.home()
    path = user_dir / ".cursor/mcp.json"
    data = read_json(path)
    server = {"command": command, "args": [], "env": {"LAYA_PRELOAD": "0"}}
    data.setdefault("mcpServers", {})["laya-jev"] = server
    write_json(path, data)


def configure_project(project, editor, services, components=""):
    package = read_json(project / "package.json")
    javascript = (project / "package.json").exists()
    python = (project / "pyproject.toml").exists()
    java = any((project / file).exists() for file in ("pom.xml", "build.gradle", "build.gradle.kts"))
    go = (project / "go.mod").exists()
    native_languages = set(components.split(",")) & {"c", "cpp"}
    settings = {
        "editor.fontFamily": "'JetBrainsMono Nerd Font Mono', monospace",
        "terminal.integrated.fontFamily": "JetBrainsMono Nerd Font Mono",
        "editor.formatOnSave": True,
        "workbench.colorTheme": "Dracula",
    }
    extensions = ["EditorConfig.EditorConfig", "dracula-theme.theme-dracula"]
    tasks, configurations = [], []

    if javascript:
        extensions += ["dbaeumer.vscode-eslint", "esbenp.prettier-vscode"]
        for language in ("javascript", "typescript", "json", "html", "css"):
            settings[f"[{language}]"] = {"editor.defaultFormatter": "esbenp.prettier-vscode"}
        settings["editor.codeActionsOnSave"] = {"source.fixAll.eslint": "explicit"}
        settings["npm.packageManager"] = "pnpm"
        if "@angular/core" in package.get("dependencies", {}):
            extensions.append("Angular.ng-template")
        tasks += [
            {"label": "Lint", "type": "process", "command": "pnpm", "args": ["exec", "eslint", "."]},
            {"label": "Check formatting", "type": "process", "command": "pnpm", "args": ["exec", "prettier", "--check", "."]},
        ]
        if "test" in package.get("scripts", {}):
            tasks.append({"label": "JavaScript tests", "type": "process", "command": "pnpm", "args": ["test"], "group": "test"})
        configurations.append({"name": "Debug JavaScript file", "type": "node", "request": "launch", "program": "${file}", "console": "integratedTerminal"})
        eslint_configured = any(project.glob("eslint.config.*")) or any(project.glob(".eslintrc*")) or "eslintConfig" in package
        if not eslint_configured:
            (project / "eslint.config.mjs").write_text(
                'import tseslint from "typescript-eslint";\nimport prettier from "eslint-config-prettier";\n\n'
                'export default [...tseslint.configs.recommended, prettier, { ignores: ["dist/**", "build/**", "coverage/**"] }];\n'
            )
    if python:
        extensions += ["ms-python.python", "ms-python.debugpy", "charliermarsh.ruff"]
        settings.update({
            "[python]": {"editor.defaultFormatter": "charliermarsh.ruff"},
            "python.defaultInterpreterPath": "${workspaceFolder}/.venv/bin/python",
            "python.testing.pytestEnabled": True,
            "python.testing.unittestEnabled": False,
        })
        tasks += [
            {"label": "Python lint", "type": "process", "command": "uv", "args": ["run", "ruff", "check", "."]},
            {"label": "Python tests", "type": "process", "command": "uv", "args": ["run", "pytest"], "group": "test"},
        ]
        configurations.append({"name": "Debug Python file", "type": "debugpy", "request": "launch", "program": "${file}", "console": "integratedTerminal"})
    if java:
        extensions.append("vscjava.vscode-java-pack")
        settings["[java]"] = {"editor.defaultFormatter": "redhat.java"}
        if os.environ.get("JAVA_HOME"):
            settings["java.jdt.ls.java.home"] = os.environ["JAVA_HOME"]
        wrapper = "./mvnw" if (project / "pom.xml").exists() else "./gradlew"
        tasks.append({"label": "Java tests", "type": "process", "command": wrapper, "args": ["test"], "group": "test"})
        configurations.append({"name": "Debug Java file", "type": "java", "request": "launch", "mainClass": "${file}"})

    if go:
        extensions.append("golang.go")
        settings["[go]"] = {"editor.defaultFormatter": "golang.go"}
        tasks += [
            {"label": "Go tests", "type": "process", "command": "go", "args": ["test", "./..."], "group": "test"},
            {"label": "Go vet", "type": "process", "command": "go", "args": ["vet", "./..."]},
        ]
    if native_languages:
        extensions.append("llvm-vs-code-extensions.vscode-clangd")
        for language in sorted(native_languages):
            settings[f"[{language}]"] = {"editor.defaultFormatter": "llvm-vs-code-extensions.vscode-clangd"}
        if (project / "CMakeLists.txt").exists():
            extensions.append("ms-vscode.cmake-tools")
            settings["cmake.configureSettings"] = {"CMAKE_EXPORT_COMPILE_COMMANDS": True}
            tasks += [
                {"label": "CMake configure", "type": "process", "command": "cmake",
                 "args": ["-S", ".", "-B", "build", "-DCMAKE_EXPORT_COMPILE_COMMANDS=ON"]},
                {"label": "CMake build", "type": "process", "command": "cmake", "args": ["--build", "build"], "group": "build"},
            ]

    if services:
        compose = project / "compose.dev.yaml"
        if not compose.exists():
            shutil.copyfile(Path(__file__).resolve().parents[1] / "compose.dev.yaml", compose)
        env_file = project / ".env.devready"
        # Keep existing credentials and workspace tasks using the same file.
        if (project / ".env.d-environment").exists():
            env_file = project / ".env.d-environment"
        ignore = project / ".gitignore"
        ignored = ignore.read_text() if ignore.exists() else ""
        if f"/{env_file.name}" not in ignored.splitlines():
            with ignore.open("a") as output:
                output.write(f"\n/{env_file.name}\n")
        if not env_file.exists():
            with open(env_file, "x", opener=lambda path, flags: os.open(path, flags, 0o600)) as output:
                output.write(f"POSTGRES_USER=dev\nPOSTGRES_DB=app\nPOSTGRES_PASSWORD={secrets.token_urlsafe(24)}\n")
        command = ["compose", "--env-file", env_file.name, "-f", "compose.dev.yaml"]
        for service in services.split(","):
            command += ["--profile", service]
        tasks.append({"label": "Start dev services", "type": "process", "command": "docker", "args": command + ["up", "-d", "--wait"]})
        tasks.append({"label": "Stop dev services", "type": "process", "command": "docker", "args": command + ["down"]})
        print("Service configuration created; start it with: docker " + " ".join(command + ["up", "-d", "--wait"]))

    if editor != "none":
        workspace = project / "development.code-workspace"
        data = read_json(workspace)
        data.setdefault("folders", [{"path": "."}])
        existing_settings = data.setdefault("settings", {})
        for key, value in settings.items():
            if isinstance(value, dict) and isinstance(existing_settings.get(key), dict):
                existing_settings[key].update(value)
            else:
                existing_settings[key] = value
        recommendations = data.setdefault("extensions", {}).setdefault("recommendations", [])
        recommendations[:] = list(dict.fromkeys(recommendations + extensions))
        for key, field, entries in (("tasks", "tasks", tasks), ("launch", "configurations", configurations)):
            section = data.setdefault(key, {"version": "2.0.0" if key == "tasks" else "0.2.0"})
            existing = section.setdefault(field, [])
            identity = "label" if key == "tasks" else "name"
            labels = {entry[identity] for entry in existing}
            existing.extend(entry for entry in entries if entry[identity] not in labels)
        write_json(workspace, data)
        for extension in extensions:
            subprocess.run([editor, "--install-extension", extension], check=True)
        print("Open the configured workspace with: " + shlex.join([editor, str(workspace)]))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--project", type=Path)
    parser.add_argument("--editor", choices=("none", "code", "cursor"), default="none")
    parser.add_argument("--services", default="")
    parser.add_argument("--components", default="")
    parser.add_argument("--mcp-target", choices=("cursor",))
    parser.add_argument("--mcp-command")
    args = parser.parse_args()
    if args.mcp_target:
        if not args.mcp_command:
            parser.error("--mcp-command is required")
        configure_cursor_mcp(args.mcp_command)
    elif args.project and args.project.is_dir():
        if any(service not in ("postgres", "redis") for service in args.services.split(",") if service):
            parser.error("Unknown service")
        configure_project(args.project.resolve(), args.editor, args.services, args.components)
    else:
        parser.error("An existing --project directory is required")


if __name__ == "__main__":
    main()
