#!/usr/bin/env python3
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile


def serve():
    for line in sys.stdin:
        request = json.loads(line)
        if "id" not in request:
            continue
        if request["method"] == "initialize":
            result = {
                "protocolVersion": request["params"]["protocolVersion"],
                "capabilities": {"tools": {}},
                "serverInfo": {"name": "fixture", "version": "1"},
            }
        else:
            assert request["method"] == "tools/list"
            assert os.environ["LAYA_PRELOAD"] == "0"
            assert os.environ["HF_HUB_OFFLINE"] == "1"
            tools = [] if "--missing-tool" in sys.argv else [
                {"name": "laya_status", "inputSchema": {"type": "object"}}
            ]
            result = {"tools": tools}
        print(json.dumps({"jsonrpc": "2.0", "id": request["id"], "result": result}), flush=True)


if "--serve" in sys.argv:
    serve()
else:
    root = Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory() as directory:
        server = Path(directory) / "fixture-server"
        for missing in (False, True):
            args = [str(Path(__file__).resolve()), "--serve"] + (["--missing-tool"] if missing else [])
            server.write_text(f"#!{sys.executable}\nimport os\nos.execv({sys.executable!r}, {([sys.executable] + args)!r})\n")
            server.chmod(0o700)
            result = subprocess.run([sys.executable, str(root / "scripts/check-mcp.py"), str(server)], capture_output=True, text=True, timeout=40)
            assert (result.returncode != 0) == missing, result.stdout + result.stderr
    print("Real MCP SDK handshake and missing-tool failure checks passed.")
