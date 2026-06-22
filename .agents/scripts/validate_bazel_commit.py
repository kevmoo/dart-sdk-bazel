#!/usr/bin/env python3
import sys, json, subprocess, os, re

def deny(reason):
    print(json.dumps({"decision": "deny", "reason": reason}))
    sys.exit(0)

def allow():
    print(json.dumps({"decision": "allow"}))
    sys.exit(0)

def main():
    if sys.stdin.isatty():
        data = {"args": {"CommandLine": "git commit"}}
    else:
        try:
            data = json.load(sys.stdin)
        except Exception:
            allow()

    if not isinstance(data, dict):
        allow()

    args = data.get("args", {})
    cmd = args.get("CommandLine", "") if isinstance(args, dict) else ""

    # Only gate commit / upload operations
    if not any(k in cmd for k in ["git commit", "git cl upload", "git push", "presubmit"]):
        allow()

    # Get modified files (staged and unstaged) using -z to handle spaces and renames robustly
    try:
        staged = subprocess.check_output(["git", "diff", "-z", "--cached", "--name-only"]).decode("utf-8", "ignore").split(chr(0))
        unstaged = subprocess.check_output(["git", "diff", "-z", "--name-only"]).decode("utf-8", "ignore").split(chr(0))
        modified_files = list(set(filter(None, staged + unstaged)))
    except Exception:
        allow()

    if not modified_files:
        allow()

    # 1. Check Bazel files for forbidden anti-patterns
    bazel_files = [f for f in modified_files if f.endswith(".bazel") or f.endswith(".bzl") or f.endswith("BUILD")]
    for bf in bazel_files:
        if os.path.exists(bf):
            try:
                with open(bf, "r", encoding="utf-8", errors="ignore") as f:
                    content = f.read()
                if "package_config.json" in content:
                    deny(f"Rule violation in {bf}: Direct reference to package_config.json breaks Bazel hermeticity. Use runfiles or @dart_packages.")
                if re.search(r"\b(sed|dirname|cat|rm)\b", content):
                    deny(f"Rule violation in {bf}: Spawning Unix shell utilities (sed/dirname/cat) breaks Windows workstation sandboxing. Use native Starlark or Python scripts.")
            except Exception:
                pass

    # 2. Check Dart analyze on modified Dart tooling scripts
    tooling_dart = [f for f in modified_files if f.startswith("tools/bazel") and f.endswith(".dart")]
    if tooling_dart:
        try:
            res = subprocess.run(["dart", "analyze", "tools/bazel"], capture_output=True, text=True)
            if res.returncode != 0:
                deny("Static analysis failed on modified tools/bazel Dart scripts. Please run 'dart analyze tools/bazel' and resolve all issues before committing.")
        except Exception:
            pass

    allow()

if __name__ == "__main__":
    main()
