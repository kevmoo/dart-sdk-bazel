# Local Agent Rules for remote-execution-infra Branch

> [!CRITICAL]
> This file defines safety rules that apply ONLY to the `remote-execution-infra` branch.

## 🚨 CRITICAL SAFETY RULE: DO NOT PUSH TO GITHUB

*   **PROHIBITION**: You are explicitly **PROHIBITED** from running `git push` or any command that uploads this branch (`remote-execution-infra`) to any remote repository (especially `origin` or `upstream`), unless the user explicitly and repeatedly confirms they want to push and have verified no secrets are leaked.
*   **Verification**: If the user asks you to push, you MUST:
    1. Run `git status` and `git diff` to verify no sensitive files (like `local.auto.tfvars` or files containing real IPs/emails) are staged or committed.
    2. Explicitly warn the user that this is a public repository and ask them to confirm they have performed a manual scrub.
*   **Credentials**: Always use placeholders (e.g., `<GCP_PROJECT_ID>`) in any new files you create.
