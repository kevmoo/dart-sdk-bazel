#!/usr/bin/env bash
set -euo pipefail

# Get the worktree root
WORKSPACE_ROOT="$(git rev-parse --show-toplevel)"

DART="$WORKSPACE_ROOT/tools/sdks/dart-sdk/bin/dart"
SCRIPT="$WORKSPACE_ROOT/docs/bazel-migration/gen_board_from_beads.dart"

if [ ! -x "$DART" ]; then
    if which dart >/dev/null; then
        DART="dart"
    else
        echo "❌ Dart SDK not found at $DART and 'dart' is not in PATH."
        exit 1
    fi
fi

if [ ! -f "$SCRIPT" ]; then
    echo "❌ Board generator script not found at $SCRIPT"
    exit 1
fi

echo "📊 Running board generator..."
"$DART" "$SCRIPT"
echo "✅ Backlog boards regenerated."
