# Task Tracking with Beads — Setup & Workflow

Bazel-migration tasks live in **beads** (`bd`), a Dolt-backed issue tracker —
**not** in a checked-in file. [BACKLOG.md](BACKLOG.md) / [BACKLOG_HISTORY.md](BACKLOG_HISTORY.md)
are *generated* from it (see [gen_board_from_beads.dart](gen_board_from_beads.dart)).

The beads database is **not** in the git tree. It rides on the `refs/dolt/data`
side ref of the **`kevmoo/sdk` fork** (not the upstream `dart.googlesource.com`
remote), so it is carried by the fork, recovered with `bd`, and never lost as
long as nobody force-pushes it.

## Learning the `bd` workflow (general)

The general `bd` workflow (`bd ready` / `create` / `show` / `close`, dependency
graph, compaction survival) is documented by beads' own **skill**. Install it
once per machine — either:

- **Plugin**: `/plugin marketplace add steveyegge/beads && /plugin install beads`, or
- **SessionStart hook**: `bd setup claude` (runs `bd prime` to inject context).

Run `bd prime` anytime for the AI-optimized workflow cheat-sheet.

## First-time setup on a new machine (e.g. the Mac side)

Nothing beads-related is in the git tree except this doc and the generated board
(`.beads/`, the exclude rules, and the remote config are all local/per-clone),
so a fresh clone needs three steps:

```bash
# 1. Install the tools
brew install beads dolt           # beads may need a tap — see github.com/steveyegge/beads

# 2. Let git authenticate to GitHub over HTTPS non-interactively
gh auth setup-git                 # uses the gh token as a git credential helper

# 3. Recover the task DB from the fork (clones refs/dolt/data)
bd init --prefix sdk --remote git+https://github.com/kevmoo/dart-sdk-bazel.git

bd count        # should list the tasks (verifies recovery)
bd ready        # actionable tasks
```

## Daily workflow

```bash
bd ready                                  # unblocked tasks
bd blocked                                # tasks waiting on prerequisites
bd show <id>                              # full task context
bd update <id> --claim                    # claim + set in_progress
bd close <id> --reason "..."              # complete a task

# After any task change, regenerate the board and push the DB:
tools/sdks/dart-sdk/bin/dart docs/bazel-migration/gen_board_from_beads.dart
bd dolt push                              # ship the DB to the fork
git add docs/bazel-migration/BACKLOG.md docs/bazel-migration/BACKLOG_HISTORY.md  # commit the board
```

## 🔄 Task Lifecycle & PR Alignment (CRITICAL)

To keep the backlog board accurate and prevent desynchronization:

1.  **READY / BLOCKED (Open):** The task is waiting in the backlog.
2.  **IN PROGRESS (Active):** Claim the task (`bd update <id> --claim`) when you start working. **The task MUST remain in the `IN_PROGRESS` state throughout the entire development and PR review process.**
3.  **CLOSED (Done):** Only close the task (`bd close <id>`) **AFTER the PR has successfully landed (merged) upstream.** Never close a task while its changes are still in a branch or active PR.

## Gotchas (learned the hard way — don't relearn these)

- **Use `git+https://`, never `git+ssh://`** for the dolt remote. The ssh URL
  triggers a `gnome-ssh-askpass` GUI popup and hangs; https authenticates
  silently via the `gh` credential helper.
- The dolt remote `bd dolt push` targets **must be named `origin`** (a remote
  named anything else is silently ignored → "No remote is configured").
- The DB lives on the **`kevmoo/sdk` fork**, not the upstream `origin`
  (`dart.googlesource.com`), which is read-only and has no beads data.
- **Never force-push** the dolt remote — a normal push only adds and can't lose
  history; a force-push is the only way to destroy it.
- **Auto-push is inert** in embedded mode (no background process), so `bd dolt
  push` is a **manual** step. Local `.beads/` history is always safe
  (`auto-commit=on`); the fork is the durable off-machine copy.
- `.beads/` is gitignored and local — it is never committed.

## 🕵️‍♂️ Troubleshooting Headless / Agent Environments

When running `bd` or `dolt` commands in background agent sessions (such as JetSki daemons), you may encounter two common environmental hurdles:

### 1. Database Resolution in Git Worktrees
In a Git worktree layout, if the worktree contains a checked-in `.beads/` folder, `bd` will resolve the database directory locally to that worktree (e.g., `sdk/.beads/`).
*   **Why:** This allows each sandbox worktree to manage its own isolated, local copy of the Dolt issue database.
*   **Impact:** Any raw `dolt` commands must be run inside `sdk/.beads/embeddeddolt/sdk/` to interact directly with the active database.

### 2. SSH Push Failures (`Permission denied (publickey)`)
If you have a global Git configuration that rewrites HTTPS pushes to SSH (using `pushinsteadof`):
```ini
url.git@github.com:.pushinsteadof=https://github.com/
```
Background agents will fail to push (`bd dolt push` or `git push`) because they lack access to your active SSH agent/keys (usually due to a missing or inaccessible `SSH_AUTH_SOCK` in the daemon environment).

#### **The Permanent Solution (SSH Agent Symlink):**
We have implemented a permanent solution that allows background agents to use your active SSH agent seamlessly:
1.  **Static Symlink:** A static symlink is maintained at `~/.ssh/ssh_auth_sock` which always points to your active SSH agent socket. This is automatically updated upon login via your Zsh configuration (`~/.config/zsh/rc.d/linux-local.zsh`).
2.  **Daemon Configuration:** The JetSki Hub Daemon is configured via `~/.config/jetski/hub.env` to inject `SSH_AUTH_SOCK=/usr/local/google/home/<username>/.ssh/ssh_auth_sock` into all spawned agent environments.

With this setup, both `git push` and `bd dolt push` work out-of-the-box in background sessions without any manual intervention.

#### **The Legacy Bypass (HTTPS Fallback):**
If the SSH agent connection is ever broken, you can still temporarily bypass the global rewrite in a shell session to force Git and Dolt to use HTTPS (which authenticates silently via the `gh` credential helper):
```bash
# Temporarily unset pushinsteadof globally for this shell, and ensure it is restored on exit
git config --global url.git@github.com:.pushinsteadof ""
trap 'git config --global --unset url.git@github.com:.pushinsteadof' EXIT

# Run your push commands
PATH=$PATH:$HOME/go/bin bd dolt push
```

