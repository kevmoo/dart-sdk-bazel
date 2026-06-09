---
trigger: always_on
description: Strict safeguards for git push and force-push operations
---

# ⛔ STRICT GIT PUSH RESTRICTIONS

To protect remote repository history and prevent accidental or destructive changes to remote branches, you MUST strictly adhere to the following rules regarding `git push` operations:

1. **NEVER PUSH UNILATERALLY:**
   - You are explicitly **PROHIBITED** from executing `git push` or any remote-write operations under any circumstances, unless the user has explicitly and unambiguously granted permission for that specific push operation in the current turn (e.g., *"Please push the commits to the remote"*).
   - General goal statements (e.g., *"Get this ready to push"*) are NOT permission to push. You must report back when ready and wait for the user's explicit push command.

2. **FORCE PUSHES REQUIRE IMMEDIATE, EXPLICIT AUTHORIZATION:**
   - You are strictly prohibited from executing any force push (`git push --force`, `git push -f`, or `git push origin ... --force`) unless the human user has explicitly and unambiguously authorized that specific force push **immediately before** it is executed in the current turn.
   - This authorization **cannot** be inferred from earlier statements in the conversation (such as *"let's do that"* or *"please"*). Even if a multi-step plan containing a force push was previously approved, the agent **MUST pause, summarize the changes, and ask for a final, explicit confirmation** right before running the actual force push command.

