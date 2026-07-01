#!/usr/bin/env bash
# Developer entrypoint script to execute Bazel tests across the Dart SDK universe safely.
# Incorporates automated resource bounds safeguards (RAM job throttling, disk space sandbox checks).

set -euo pipefail

cd "$(dirname "$0")/../.."

show_help() {
  cat <<'EOF'
tools/bazel/test_everything.sh — Dart SDK Bazel Universe Entrypoint

Usage:
  tools/bazel/test_everything.sh [options]

Options:
  --run                     Execute Bazel tests across targets and update test matrix results JSON
  --dry-run                 Query and filter targets without running bazel test (default if --run is omitted)
  --only-suites=<s1,s2>     Comma-separated suites to run (e.g. pkg,language)
  --skip-suites=<s1,s2>     Comma-separated suites to skip (e.g. co19,web/wasm)
  --only-configs=<c1,c2>    Comma-separated configs to run (e.g. vm_release)
  --skip-configs=<c1,c2>    Comma-separated configs to skip
  --jobs=<N>                Override parallel test jobs limit (default: auto-calculated based on RAM)
  --sandbox-base=<DIR>      Override Bazel sandbox base directory (default: auto-selected based on disk space)
  --output=<PATH>           JSON results output path (default: docs/bazel-migration/test_matrix_results.json)
  --heartbeat=<PATH>        Heartbeat status path (default: docs/bazel-migration/PATROL_HEARTBEAT.json)
  --bazel-arg=<ARG>         Pass extra argument to bazel test (can be repeated)
  -h, --help                Show this help message

Examples:
  # Dry-run target discovery & print resource bounds report
  tools/bazel/test_everything.sh

  # Run full test universe safely with automated resource bounds
  tools/bazel/test_everything.sh --run

  # Run specific suites with custom job limit
  tools/bazel/test_everything.sh --run --only-suites=pkg --jobs=8
EOF
}

# 1. Resolve Prebuilt Dart SDK
DART="tools/sdks/dart-sdk/bin/dart"
if [ ! -x "$DART" ]; then
  OUTPUT_BASE=$(bazel info output_base 2>/dev/null || true)
  if [ -n "$OUTPUT_BASE" ]; then
    DART=$(ls "$OUTPUT_BASE"/external/*prebuilt_dart_sdk*/bin/dart 2>/dev/null | head -n 1 || true)
  fi
fi

if [ -z "$DART" ] || [ ! -x "$DART" ]; then
  echo "📦 Prebuilt Dart SDK not found locally. Fetching via Bazel..."
  bazel query '@dart_sdk//...' >/dev/null 2>&1 || true
  OUTPUT_BASE=$(bazel info output_base 2>/dev/null || true)
  if [ -n "$OUTPUT_BASE" ]; then
    DART=$(ls "$OUTPUT_BASE"/external/*prebuilt_dart_sdk*/bin/dart 2>/dev/null | head -n 1 || true)
  fi
fi

if [ -z "$DART" ] || [ ! -x "$DART" ]; then
  echo "❌ Error: Unable to locate or fetch prebuilt Dart SDK binary."
  exit 1
fi

# 2. Resource Bounds Detection & Safeguards
RAM_AVAIL_MB=4090
if [ -f /proc/meminfo ]; then
  RAM_AVAIL_KB=$(grep -i MemAvailable /proc/meminfo | awk '{print $2}' || true)
  if [ -n "$RAM_AVAIL_KB" ]; then
    RAM_AVAIL_MB=$(( RAM_AVAIL_KB / 1024 ))
  fi
elif command -v free >/dev/null 2>&1; then
  RAM_AVAIL_MB=$(free -m | awk '/Mem:/ {print $7}' || true)
fi

RAM_AVAIL_GB=$(( RAM_AVAIL_MB / 1024 ))

# Calculate safe local test jobs: 1 job per ~2.5 GB available RAM, capped between 2 and 16
CALC_JOBS=$(( RAM_AVAIL_GB / 3 ))
if [ "$CALC_JOBS" -lt 2 ]; then
  CALC_JOBS=2
fi
if [ "$CALC_JOBS" -gt 16 ]; then
  CALC_JOBS=16
fi

# Check free disk space & free inodes on /dev/shm (RAM-backed, 15M+ inodes) vs /tmp vs workspace
TMP_FREE_KB=$(df -k /tmp 2>/dev/null | awk 'NR==2 {print $4}' || echo "0")
TMP_FREE_GB=$(( TMP_FREE_KB / 1024 / 1024 ))

SELECTED_SANDBOX="/tmp"
if [ -w /dev/shm ]; then
  SHM_FREE_INODES=$(df -i /dev/shm 2>/dev/null | awk 'NR==2 {print $4}' || echo "0")
  if [ "$SHM_FREE_INODES" -gt 1000000 ]; then
    SELECTED_SANDBOX="/dev/shm"
  fi
elif [ "$TMP_FREE_GB" -lt 15 ]; then
  SELECTED_SANDBOX="/var/tmp"
fi

# 3. Parse Arguments
RUN_MODE=false
EXPLICIT_DRY_RUN=false
CUSTOM_JOBS=""
CUSTOM_SANDBOX=""
PASSTHROUGH_ARGS=()
HAS_BAZEL_JOBS_ARG=false
HAS_BAZEL_SANDBOX_ARG=false

for arg in "$@"; do
  case "$arg" in
    -h|--help)
      show_help
      exit 0
      ;;
    --run)
      RUN_MODE=true
      ;;
    --dry-run)
      EXPLICIT_DRY_RUN=true
      ;;
    --jobs=*)
      CUSTOM_JOBS="${arg#*=}"
      ;;
    --sandbox-base=*)
      CUSTOM_SANDBOX="${arg#*=}"
      ;;
    --bazel-arg=*)
      BAZEL_VAL="${arg#*=}"
      if [[ "$BAZEL_VAL" == --local_test_jobs=* ]] || [[ "$BAZEL_VAL" == --jobs=* ]]; then
        HAS_BAZEL_JOBS_ARG=true
      fi
      if [[ "$BAZEL_VAL" == --sandbox_base=* ]]; then
        HAS_BAZEL_SANDBOX_ARG=true
      fi
      PASSTHROUGH_ARGS+=("$arg")
      ;;
    *)
      PASSTHROUGH_ARGS+=("$arg")
      ;;
  esac
done

FINAL_JOBS="${CUSTOM_JOBS:-$CALC_JOBS}"
FINAL_SANDBOX="${CUSTOM_SANDBOX:-$SELECTED_SANDBOX}"

if [ "$HAS_BAZEL_JOBS_ARG" = false ]; then
  PASSTHROUGH_ARGS+=("--bazel-arg=--local_test_jobs=$FINAL_JOBS")
fi

if [ "$HAS_BAZEL_SANDBOX_ARG" = false ]; then
  PASSTHROUGH_ARGS+=("--bazel-arg=--sandbox_base=$FINAL_SANDBOX")
fi

PASSTHROUGH_ARGS+=("--bazel-startup-arg=--output_user_root=$FINAL_SANDBOX/bazel_user_root")

if [ "$RUN_MODE" = false ]; then
  PASSTHROUGH_ARGS+=("--dry-run")
fi

# 4. Print Resource Bounds Summary
echo "============================================================"
echo "🛡️  Resource Bounds & Environment Report"
echo "  • Dart SDK:             $DART"
echo "  • Available RAM:        ${RAM_AVAIL_GB} GB"
echo "  • Configured Jobs Limit: $FINAL_JOBS parallel test workers"
echo "  • Sandbox Directory:     $FINAL_SANDBOX (${TMP_FREE_GB} GB available on /tmp)"
if [ "$RUN_MODE" = false ] && [ "$EXPLICIT_DRY_RUN" = false ]; then
  echo "  • Execution Mode:       DRY RUN (target discovery only)"
  echo "    👉 To execute full test universe, run with: --run"
fi
echo "============================================================"
echo

# 5. Delegate to run_test_universe.dart & render markdown matrix
"$DART" tools/bazel/run_test_universe.dart "${PASSTHROUGH_ARGS[@]}"
"$DART" docs/bazel-migration/render_test_matrix.dart docs/bazel-migration/test_matrix_results.json docs/bazel-migration/TEST_COMPLETION_MATRIX.md
