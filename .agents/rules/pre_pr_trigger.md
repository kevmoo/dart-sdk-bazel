---
trigger: always_on
description: Prompt for pre-PR checks before pushing or creating PR
---
Before creating a pull request or pushing changes to the remote repository, you must ask the user if they would like to run the `bazel-pre-pr` skill to perform a deep code review of the local commits against the migration guidelines.
