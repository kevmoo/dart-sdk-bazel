#!/usr/bin/env bash
# Single-command validation gate for the Bazel migration: run this before
# sending a PR. CI (.github/workflows/bazel.yml) runs this same script, so a
# local pass should closely predict a green PR. Target: < 2 minutes warm.
#
# Checks, cheap -> expensive (rationale: docs/bazel-migration/fable_thoughts.md
# section 10 -- each step maps to a regression class that previously reached
# main):
#   1. buildifier format+lint (same invocation as buildifier.yml)
#   2. hardcoded-architecture audit (same patterns as tools/bazel/hooks/
#      pre-commit, but whole-tree and not skippable via --no-verify)
#   3. python helper byte-compile
#   4. bazel analysis (--nobuild) of the flagship targets -- catches missing
#      $(location) prerequisites, Starlark errors, dangling labels
#   5. module-extension evaluation (@dart_packages, @dart_tests) -- catches
#      generator crashes nothing else loads
#   6. dart analyze over the bazel tooling scripts
#
# All steps run even after a failure so one invocation reports everything.
set -uo pipefail
cd "$(dirname "$0")/../.."

FAILURES=()

step() {
  echo
  echo "=== $1 ==="
}

fail() {
  echo "FAIL: $1"
  FAILURES+=("$1")
}

step "buildifier format + lint"
if command -v buildifier >/dev/null 2>&1; then
  if ! git ls-files '*BUILD.bazel' '*MODULE.bazel' '*.bzl' \
    | grep -v 'gen_targets.bzl' | grep -v '^third_party/' \
    | xargs buildifier --mode=check --lint=warn --warnings=all; then
    fail "buildifier (fix with: buildifier --lint=fix <files>)"
  fi
else
  echo "SKIP: buildifier not installed (the Buildifier CI workflow still runs it)"
fi

step "hardcoded-architecture audit"
# Keep patterns and exclusions in sync with tools/bazel/hooks/pre-commit.
forbidden_patterns=(
  '"-m64"'
  '"-march=x86-64"'
  '"-msse2"'
  '"--target=x86_64-linux-gnu"'
  '"TARGET_ARCH_X64"'
)
audit_files=$(git ls-files '*BUILD.bazel' '*MODULE.bazel' '*.bzl' '*.snap' '*.append' \
  | grep -E -v 'gen_targets\.bzl|rules\.bzl|^build/config/' || true)
# Lines carrying '# arch-pinned-variant: ok' are exempt: explicitly
# arch-pinned cross variants (e.g. *_product_linux_x64 targets) legitimately
# carry their arch define; the marker keeps the exemption visible in review.
for pattern in "${forbidden_patterns[@]}"; do
  matches=$(echo "$audit_files" | xargs grep -H -F -n "$pattern" 2>/dev/null \
    | grep -v '# arch-pinned-variant: ok' || true)
  if [ -n "$matches" ]; then
    echo "$matches"
    fail "architecture audit: $pattern is hardcoded (parameterize via select(), or mark an arch-pinned variant with '# arch-pinned-variant: ok')"
  fi
done
# Obfuscated concat forms ("TARGET_ARCH_" + "X64") evaluate identically but
# dodge the literal greps. Never allowed: write the honest literal (plus the
# marker if the target is a deliberately arch-pinned variant).
concat_matches=$(echo "$audit_files" | xargs grep -H -n -E '"TARGET_ARCH_"[[:space:]]*\+' 2>/dev/null || true)
if [ -n "$concat_matches" ]; then
  echo "$concat_matches"
  fail "architecture audit: concat-built TARGET_ARCH_ define evades the literal grep (write the honest literal + marker)"
fi

step "starlark macro unit tests"
if ! bazel test //tools/bazel/dart/tests:dart_rules_tests; then
  fail "bazel test //tools/bazel/dart/tests:dart_rules_tests"
fi

step "genrule hermeticity audit"
genrule_audit_files=$(git ls-files '*BUILD.bazel' '*MODULE.bazel' '*.bzl' \
  | grep -v '^third_party/' || true)
cp_matches=$(echo "$genrule_audit_files" | xargs grep -H -n -E 'cmd[[:space:]]*=[[:space:]]*".*[[:space:]";&|](cp|mv)[[:space:]]+' 2>/dev/null | grep -v '# exempt-genrule: ok' || true)
if [ -n "$cp_matches" ]; then
  echo "$cp_matches"
  fail "genrule audit: shell cp/mv command found inside cmd string (use copy_file from @bazel_skylib, or mark '# exempt-genrule: ok')"
fi
ambient_matches=$(echo "$genrule_audit_files" | xargs grep -H -n -E 'cmd[[:space:]]*=[[:space:]]*".*[[:space:]";&|](git|date)[[:space:]]+' 2>/dev/null | grep -v '# exempt-genrule: ok' || true)
if [ -n "$ambient_matches" ]; then
  echo "$ambient_matches"
  fail "genrule audit: ambient host command (git/date) found inside cmd string (use --workspace_status_command or stamping)"
fi

BAZEL_STARTUP_ARGS=()
if [ -w /dev/shm ]; then
  SHM_EXEC_ALLOWED=false
  if touch /dev/shm/test_exec_$$ 2>/dev/null; then
    if chmod +x /dev/shm/test_exec_$$ 2>/dev/null && /dev/shm/test_exec_$$ 2>/dev/null; then
      SHM_EXEC_ALLOWED=true
    fi
    rm -f /dev/shm/test_exec_$$ || true
  fi
  if [ "$SHM_EXEC_ALLOWED" = true ]; then
    SHM_FREE_INODES=$(df -iP /dev/shm 2>/dev/null | awk 'NR==2 {print $4}' || echo "0")
    if [[ ! "$SHM_FREE_INODES" =~ ^[0-9]+$ ]]; then
      SHM_FREE_INODES=0
    fi
    SHM_FREE_KB=$(df -kP /dev/shm 2>/dev/null | awk 'NR==2 {print $4}' || echo "0")
    if [[ ! "$SHM_FREE_KB" =~ ^[0-9]+$ ]]; then
      SHM_FREE_KB=0
    fi
    if [ "$SHM_FREE_INODES" -gt 1000000 ] && [ "$SHM_FREE_KB" -gt 15728640 ]; then
      USER_ID=$(id -u 2>/dev/null || echo "${USER:-default}")
      BAZEL_STARTUP_ARGS+=("--output_user_root=/dev/shm/bazel_user_root_$USER_ID")
    fi
  fi
fi

step "python helpers byte-compile"
if ! git ls-files 'tools/bazel/*.py' 'tools/bazel/**/*.py' | xargs python3 -m py_compile; then
  fail "py_compile of tools/bazel python helpers"
fi

step "bazel analysis (--nobuild) of flagship targets"
if ! bazel "${BAZEL_STARTUP_ARGS[@]}" build --nobuild \
  //sdk:create_sdk \
  //runtime/bin:dartvm \
  //utils:gen_kernel_exe \
  //utils:compile_platform_exe; then
  fail "bazel analysis of //sdk:create_sdk + //runtime/bin:dartvm + utils exes"
fi

step "module extension: @dart_packages"
if ! bazel "${BAZEL_STARTUP_ARGS[@]}" query '@dart_packages//pkg/...' >/dev/null; then
  fail "@dart_packages extension evaluation"
fi

step "module extension: @dart_tests (slowest step, ~1 min warm)"
if ! bazel "${BAZEL_STARTUP_ARGS[@]}" query '@dart_tests//...' >/dev/null; then
  fail "@dart_tests extension evaluation"
fi

# Resolve Dart SDK binary
DART=tools/sdks/dart-sdk/bin/dart
if [ ! -x "$DART" ]; then
  # CI: the SDK is downloaded by the third_party extension (which the queries
  # above just evaluated) instead of living in the gclient-synced workspace.
  OUTPUT_BASE=$(bazel "${BAZEL_STARTUP_ARGS[@]}" info output_base 2>/dev/null || true)
  if [ -n "$OUTPUT_BASE" ]; then
    dart_paths=("$OUTPUT_BASE"/external/*prebuilt_dart_sdk*/bin/dart)
    if [ -x "${dart_paths[0]:-}" ]; then
      DART="${dart_paths[0]}"
    fi
  fi
fi

step "dart analyze (bazel tooling scripts)"
if [ -n "$DART" ] && [ -x "$DART" ]; then
  if ! git ls-files 'tools/bazel/**/*.dart' 'tools/bazel/*.dart' 'docs/bazel-migration/*.dart' \
    | xargs "$DART" analyze; then
    fail "dart analyze of bazel tooling scripts"
  fi
else
  echo "SKIP: no dart binary found (tools/sdks/dart-sdk absent and no fetched prebuilt SDK)"
fi
step "entrypoint script validation: test_everything.sh"
if ! ./tools/bazel/test_everything.sh --help >/dev/null; then
  fail "tools/bazel/test_everything.sh --help execution"
fi

step "validate test_imports.json files"
if [ -n "$DART" ] && [ -x "$DART" ]; then
  packages=(
    "pkg/analysis_server"
    "pkg/analyzer"
    "pkg/compiler"
  )
  for pkg in "${packages[@]}"; do
    echo "Regenerating $pkg/test_imports.json..."
    if ! "$DART" tools/bazel/dart/gen_test_imports.dart "$pkg"; then
      fail "Failed to run gen_test_imports.dart for $pkg"
    fi
  done

  # Check if git diff detects any changes in those files.
  # We use git diff --exit-code, which exits with 1 if there are differences.
  if ! git diff --exit-code "${packages[@]/%//test_imports.json}" >/dev/null 2>&1; then
    git diff "${packages[@]/%//test_imports.json}"
    fail "test_imports.json files are out of date. Please run tools/bazel/dart/gen_test_imports.dart for the modified packages and commit the changes."
  fi
else
  echo "SKIP: no dart binary found (tools/sdks/dart-sdk absent and no fetched prebuilt SDK)"
fi

echo
if [ "${#FAILURES[@]}" -gt 0 ]; then
  echo "presubmit FAILED (${#FAILURES[@]} check(s)):"
  printf ' - %s\n' "${FAILURES[@]}"
  exit 1
fi
echo "presubmit OK"
