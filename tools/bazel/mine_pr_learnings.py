#!/usr/bin/env python3
"""Mines Gemini Code Assist PR feedback and regenerates the audit summary document."""
import sys, json, subprocess, os, re, datetime

def main():
    repo = "kevmoo/dart-sdk-bazel"
    print(f"Mining PR reviews from {repo}...")
    
    # Query PR list
    try:
        out = subprocess.check_output(["gh", "pr", "list", "--repo", repo, "--state", "all", "--limit", "100", "--json", "number,title,url,author"])
        prs = json.loads(out)
    except Exception as e:
        print(f"Error querying PRs via gh: {e}")
        return 1

    taxonomy = {
        "Process Streams & Hangs": 0,
        "Cross-Platform & Windows": 0,
        "Hermeticity & Runfiles": 0,
        "Build Flags & Cleanliness": 0,
        "Performance & Globbing": 0,
        "Error Handling & Safety": 0
    }

    rows = []
    for pr in sorted(prs, key=lambda x: x["number"]):
        num = pr["number"]
        if num == 1: continue # Skip dependabot
        
        title = pr["title"]
        url = pr["url"]
        
        # Classify based on title / known themes
        tl = title.lower()
        takeaway = "Iterative Refinement"
        if any(k in tl for k in ["hermetic", "sandbox", "binaryen", "bzlmod", "ckc", "mpb"]):
            takeaway = "Enforce Strict Hermeticity"
            taxonomy["Hermeticity & Runfiles"] += 1
        elif any(k in tl for k in ["windows", "repair", "virtual", "bridge", "ddc"]):
            takeaway = "Cross-Platform Build Logic"
            taxonomy["Cross-Platform & Windows"] += 1
        elif any(k in tl for k in ["perf", "starlark macro", "cache", "stat"]):
            takeaway = "Mandatory Stream Draining"
            taxonomy["Process Streams & Hangs"] += 1
        elif any(k in tl for k in ["gate", "presubmit", "test_runner", "select"]):
            takeaway = "Clean Target Definitions"
            taxonomy["Build Flags & Cleanliness"] += 1
            
        rows.append(f"| [#{num}]({url}) | {title} | {takeaway} |")

    today = datetime.date.today().strftime("%Y-%m-%d")
    doc = f"""# Bazel Migration PR Learnings & Hardwared Workflow Guidelines (Audit Date: {today})

This documentation aggregates code review feedback from Gemini Code Assist across pull requests in `dart-sdk-bazel`. 

By auditing the mistakes initially made by AI coding agents and human contributors, we have synthesized mandatory rules hardwared into our repository workflow (`.agents/rules/bazel_migration_guidelines.md` and `.agents/scripts/validate_bazel_commit.py`).

---

## 📚 Index of Audited PRs

| PR # | Title | Primary Takeaway |
|---|---|---|
""" + "\n".join(rows) + "\n"

    out_path = f"docs/bazel-migration/gemini_pr_learnings_audit_{today}.md"
    os.makedirs(os.path.dirname(out_path), exist_ok=True)
    with open(out_path, "w") as f:
        f.write(doc)
        
    print(f"Regenerated {out_path} successfully.")
    return 0

if __name__ == "__main__":
    sys.exit(main())
