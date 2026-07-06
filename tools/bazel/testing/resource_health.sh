#!/usr/bin/env bash
# Resource Health Check & Cleanup Script for Dart SDK Agents
# Usage: check_resource_health.sh [--clean-tmp]
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "================================================================="
echo "📊 DART SDK WORKSPACE RESOURCE HEALTH CHECK"
echo "================================================================="
echo ""

echo "💾 Disk Space Usage:"
df -h / /tmp /dev/shm | grep -v Filesystem || true
echo ""

echo "🔢 Inode Usage:"
df -i / /tmp /dev/shm | grep -v Filesystem || true
echo ""

echo "🧹 Agent Worktrees Found:"
FOUND_WORKTREES=0
for THREAD in core bazel; do
    if [ -d "$WORKSPACE_ROOT/$THREAD" ]; then
        for DIR in "$WORKSPACE_ROOT/$THREAD"/agent-*; do
            if [ -d "$DIR" ]; then
                FOUND_WORKTREES=$((FOUND_WORKTREES + 1))
                SIZE=$(du -sh "$DIR" 2>/dev/null | cut -f1)
                NAME=$(basename "$DIR" | sed 's/^agent-//')
                echo "  • [$THREAD] agent-$NAME ($SIZE) → clean with: .agents/scripts/rmagenttree $THREAD $NAME"
            fi
        done
    fi
done

if [ "$FOUND_WORKTREES" -eq 0 ]; then
    echo "  (No inactive agent worktrees found)"
fi
echo ""

if [ "${1:-}" = "--clean-tmp" ]; then
    echo "🧹 Cleaning temporary files in /tmp..."
    rm -rf /tmp/sar.server.* /tmp/sar.cli_internal.* /tmp/duckie_customization* /tmp/bazel-sandbox.* 2>/dev/null || true
    echo "✅ /tmp cleanup complete."
fi

echo "================================================================="
