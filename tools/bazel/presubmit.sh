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
for pattern in "${forbidden_patterns[@]}"; do
  if echo "$audit_files" | xargs grep -H -F -n "$pattern" 2>/dev/null; then
    fail "architecture audit: $pattern is hardcoded (parameterize via select())"
  fi
done

step "python helpers byte-compile"
if ! git ls-files 'tools/bazel/*.py' 'tools/bazel/**/*.py' | xargs python3 -m py_compile; then
  fail "py_compile of tools/bazel python helpers"
fi

step "bazel analysis (--nobuild) of flagship targets"
if ! bazel build --nobuild \
  //sdk:create_sdk \
  //runtime/bin:dartvm \
  //utils:gen_kernel_exe \
  //utils:compile_platform_exe; then
  fail "bazel analysis of //sdk:create_sdk + //runtime/bin:dartvm + utils exes"
fi

step "module extension: @dart_packages"
if ! bazel query '@dart_packages//pkg/...' >/dev/null; then
  fail "@dart_packages extension evaluation"
fi

step "module extension: @dart_tests (slowest step, ~1 min warm)"
if ! bazel query '@dart_tests//...' >/dev/null; then
  fail "@dart_tests extension evaluation"
fi

step "dart analyze (bazel tooling scripts)"
DART=tools/sdks/dart-sdk/bin/dart
if [ ! -x "$DART" ]; then
  # CI: the SDK is downloaded by the third_party extension (which the queries
  # above just evaluated) instead of living in the gclient-synced workspace.
  DART=$(ls "$(bazel info output_base)"/external/*prebuilt_dart_sdk*/bin/dart 2>/dev/null | head -n 1 || true)
fi
if [ -n "$DART" ] && [ -x "$DART" ]; then
  if ! git ls-files 'tools/bazel/**/*.dart' 'tools/bazel/*.dart' 'docs/bazel-migration/*.dart' \
    | xargs "$DART" analyze; then
    fail "dart analyze of bazel tooling scripts"
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
