---
name: dart-sdk-cleanup-bead
description: >-
  Post-merge cleanup protocol for Dart SDK Bazel thread task worktrees, beads issue closing, and remote sync.
---

# Dart SDK Post-Merge Cleanup & Bead Closing (`dart-sdk-cleanup-bead`)

This skill defines the standard protocol for cleaning up task worktrees, closing beads issues, and syncing local `main` with remote after a PR has been merged on the **Bazel thread (`bazel`)**.

---

## When to Use This Skill

- Trigger when a PR has landed/merged on GitHub and you need to close out a task, and clean up sandbox worktrees/branches.
- Use when requested to "clean up bead", "close bead <id>", or "tear down worktree after merge".

---

## 📋 Step-by-Step Execution Protocol

```mermaid
flowchart TD
    A["PR Merged on Remote"] --> B["1. Go to Main Bazel Checkout<br/>cd bazel/main/sdk"]
    B --> C["2. Pull Latest & Verify PR Landed<br/>git pull origin main"]
    C --> D["3. Cleanup Worktree & Local Branch<br/>.agents/scripts/rmagenttree bazel task-name<br/>git branch -d branch-name"]
    D --> E["4. Update Bead<br/>bd close bead-id"]
    E --> F["5. Interactive Authorization<br/>ask_question: Push main branch to origin?"]
    F -->|"Approved"| G["git push origin main"]
    F -->|"Declined"| H["Keep local commit unpushed"]
```

### 1. Go to Main Bazel Checkout
Navigate to the primary persistent main checkout for the `bazel` thread:
```bash
cd /usr/local/google/home/kevmoo/github/dart-sdk/bazel/main/sdk
```

### 2. Pull Latest & Confirm PR Landed
Pull the latest changes from the primary remote `origin/main` to verify the PR commit has landed:
```bash
git pull origin main
```
Confirm `git log -n 5` contains the merged PR commit.

### 3. Cleanup Worktree and Branch
Reclaim disk space by deleting the task sandbox worktree and local branch:
```bash
# Remove the sandbox worktree
.agents/scripts/rmagenttree bazel <task-name>

# Delete the local feature branch (if it exists)
git branch -d <branch-name>
```

### 4. Update Bead
Close the corresponding bead issue in the local database:
```bash
# Close the bead
bd close <bead-id>
```

### 5. Offer to Push using `ask_question`
Use `ask_question` to ask the user for authorization to push the local commit and sync Dolt remote:
- Option 1: `(Recommended) Yes, push commit to origin/main and sync Dolt remote`
- Option 2: `No, keep local commit unpushed for now`

If approved, run:
```bash
git push origin main
bd dolt push
```
