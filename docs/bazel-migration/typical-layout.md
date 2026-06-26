# Typical Workspace Layout & Architecture

This document describes the typical development workspace layout used by **kevmoo** to support concurrent development across multiple Dart SDK forks and development streams.

---

## 🏛️ Bare Repository + Sandbox Worktree Architecture

To optimize disk space, handle `gclient` hermetically, and keep working directories pristine across concurrent tasks, this workspace uses a specialized **Bare Repository + Sandbox Worktree** layout.

### Key Concepts & Variable Conventions:

* **`{workspace-root}`**: The root directory of the repository setup on the local machine (typically `~/github/dart-sdk/`, though customizable per machine).
* **`{thread}`**: The specific development stream within the repository:
  * `core`: Open-source Dart SDK thread (tracks `upstream-sdk/main`).
  * `bazel`: Internal Bazel migration thread (tracks `origin/main` on `kevmoo/dart-sdk-bazel`).
* **`{root-worktree}`**: The primary persistent main checkout for a thread (`{workspace-root}/{thread}/main/sdk`).
* **`{sandbox-worktree}`** *(or task worktree)*: Short-lived task worktree (`{workspace-root}/{thread}/agent-{task-name}/sdk`).
* **`{bare-repo}`**: The central git database housing objects for all worktrees (`{workspace-root}/.bare/`).

---

## 📖 Single Source of Truth & Reference Links

* **Master Workspace Playbook**: All workspace rules, automation scripts (`mkagenttree`, `rmagenttree`), and operational workflows are formally defined in 👉 **[.agents/AGENTS.md](../../.agents/AGENTS.md)**.
* **Agent Config Repository**: If there is any confusion regarding operational guidelines, automation scripts, or agent skills, refer to the underlying configuration repository at 👉 **[https://github.com/kevmoo/dart-sdk-agent-config](https://github.com/kevmoo/dart-sdk-agent-config)**.
