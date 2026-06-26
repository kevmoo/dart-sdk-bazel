---
name: backlog
description: Regenerate and inspect the Bazel migration task backlog, dependency graph, tag metrics, and history board.
---

# Backlog & Task Coordination Board Skill (`backlog`)

Use this skill whenever you need to regenerate, inspect, or summarize the Bazel migration backlog, active work items, tag taxonomy distribution, or completed history.

## How to Regenerate the Board

From the root of the SDK checkout (`sdk/`):

```bash
tools/sdks/dart-sdk/bin/dart docs/bazel-migration/gen_board_from_beads.dart
```

### What this Command Performs:
1. **Syncs Tag Taxonomy**: Reads `docs/bazel-migration/beads/tag_definitions.json` and syncs it into Beads persistent DB memory (`bd remember tag-definitions`).
2. **Validates Tags**: Verifies issue tags against kebab-case regex rules and defined taxonomy scopes.
3. **Segregates Active vs. Deferred Work**: Groups tasks marked with `later: true` tags into a dedicated `Deferred Backlog` section.
4. **Updates Markdown Boards**: Regenerates human-readable matrix boards `docs/bazel-migration/BACKLOG.md` and `docs/bazel-migration/BACKLOG_HISTORY.md`.

## Mandatory Agent Workflow
Whenever modifying tasks in Beads (`bd`):
1. Execute the board generation command above.
2. Stage and commit updated `BACKLOG.md` and `BACKLOG_HISTORY.md` files.
3. Request explicit user confirmation before running `bd dolt push`.
