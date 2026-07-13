---
name: bazel-pre-pr
description: Runs pre-flight checks and deep code reviews on local commits of a feature branch before push or PR creation.
---

# Bazel Pre-PR Pre-Flight Review (`bazel-pre-pr`)

This skill defines the pre-flight checks and local commit code review workflow to execute before a branch is pushed to remote or a pull request is created. It helps catch common Bazel migration bugs and style violations early.

---

## When to Use This Skill
- Run this skill before staging a commit for upload or pushing a new feature branch to GitHub.
- Trigger when the user requests "run pre-pr check", "review my local commits", or "verify my feature branch before PR".

---

## 📋 Operational Workflow

### Step 1: Feature Branch Validation (VCS Gate)
Before initiating any code analysis, you MUST verify that the local repository is in a valid state for code review:
1. **Branch Check**: Get the current git branch name.
2. **Gate Criterion**: The current branch MUST NOT be `main` (or the default base branch). If it is `main`, **stop immediately** and print a hard-stop error:
   `Error: Cannot run bazel-pre-pr on the 'main' branch. Please create a feature branch, commit your changes, and try again.`
3. **Commit Check**: Ensure there is at least one local commit distinguishing the current branch from the base branch. Safely resolve the base branch (falling back to `main` if `origin/main` is not configured) and run the log:
   ```bash
   BASE_BRANCH=$(git rev-parse --verify origin/main >/dev/null 2>&1 && echo "origin/main" || echo "main")
   git log $BASE_BRANCH..HEAD --oneline
   ```
   If this returns empty, **stop immediately** and print:
   `Error: No local commits found on this branch compared to the base branch.`

### Step 2: Spin Up Code Review Subagent
If the branch checks pass, spin up a subagent of type `self` (inheriting all tools and rules) to run the code review in the background:
- **Role**: `Bazel Code Reviewer`
- **Initial Task**:
  1. Retrieve the full diff of the local commits. Safely resolve the base branch (falling back to `main` if `origin/main` is not configured) and run the diff:
     ```bash
     BASE_BRANCH=$(git rev-parse --verify origin/main >/dev/null 2>&1 && echo "origin/main" || echo "main")
     git diff $BASE_BRANCH...HEAD
     ```
  2. Read the active migration guidelines from the repository root: `docs/bazel-migration/GUIDELINES.md`.
  3. Surgically audit all modifications in the diff against the guidelines listed in that file.
  4. Conduct a general, highly skeptical engineering review of the diff: check for logical robustness, verify assumptions, look for edge cases, resource cleanup misses, or race conditions, and identify opportunities to simplify the code.
  5. Write a triage report artifact named `bazel_pre_pr_review.md` in the parent conversation's artifacts directory.
  6. The report MUST structure issues exactly like `github-pr-triage`:
     - **Header**: `# Pre-PR Review: <branch_name>`
     - **Metadata**: Commits analyzed, date, status.
     - **Issues Grouped by Category**:
       - For each issue:
         - **Context**: File path and line range.
         - **Urgency**: `🔥 Critical` (causes compile/test failures or sandboxing violations), `⚠️ Warning` (style/performance degradation), `💡 Suggestion`.
         - **The Flaw**: Description of the guideline violated.
         - **The Recommended Fix**: Correct vs. Incorrect code block comparison.

### Step 3: Present Triage Report to User
Once the subagent finishes and writes the `bazel_pre_pr_review.md` artifact:
1. Load and present the triage report to the user.
2. The report file MUST be created as a user-facing artifact with `RequestFeedback: true` in the metadata to render the **Proceed** button.
3. If no critical issues are found, notify the user that the branch is ready for push. If issues are found, prompt the user to approve the planned refactorings or fixes.
