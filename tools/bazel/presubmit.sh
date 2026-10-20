#!/usr/bin/env bash
# Single-command validation gate for the Bazel migration: run this before
# sending a PR. CI (.github/workflows/bazel.yml) runs this same script, so a
# local pass should closely predict a green PR. Target: < 2 minutes warm.
#
# Checks, cheap -> expensive (rationale: docs/bazel-migration/fable_thoughts.md
# section 10 -- each step maps to a regression class that previously reached
# main):
#   1. buildifier format+lint (same invocation as buildifier.yml)
#   2. upstream changes audit (1:1 bidirectional check vs allowed_upstream_files.txt)
#   3. Starlark & architecture & genrule hermeticity audits
#   4. starlark & python test-wrapper unit tests
#   5. python helper byte-compile
#   6. bazel analysis (--nobuild) of the flagship targets
#   7. module-extension evaluation (@dart_packages, @dart_tests)
#   8. dart analyze over the bazel tooling scripts + test_imports.json parity
#
# All steps run even after a failure so one invocation reports everything.
set -uo pipefail
cd "$(dirname "$0")/../.."

FAILURES=()

# Share a single Bazel server across both manual `bazel` runs and `presubmit.sh`
# by default so @dart_tests doesn't ping-pong `tests_metadata_*.json` across two
# JVMs or double memory usage. Opt into tmpfs only when explicitly requested via
# BAZEL_USE_SHM=1.
BAZEL_STARTUP_ARGS=()
if [ "${CI:-}" != "true" ] && [ "${BAZEL_USE_SHM:-0}" = "1" ] && [ -w /dev/shm ]; then
  USER_ID=$(id -u 2>/dev/null || echo "${USER:-default}")
  BAZEL_STARTUP_ARGS+=("--output_user_root=/dev/shm/bazel_user_root_$USER_ID")
fi

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

step "upstream changes audit"
if [ "${GITHUB_ACTIONS:-}" = "true" ]; then
  echo "SKIP: upstream changes audit skipped in GitHub Actions CI"
else
  if ! python3 - <<'PY'
import subprocess
import sys

sys.path.insert(0, "tools/bazel")
from presubmit_checks import IsAutoExemptOverlayPath


def rev_exists(rev):
    return subprocess.call(
        ["git", "rev-parse", "--verify", "--quiet", rev],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    ) == 0


allowed = set()
with open("tools/bazel/allowed_upstream_files.txt", "r") as f:
    for line in f:
        line = line.strip()
        if line and not line.startswith("#"):
            allowed.add(line)

if rev_exists("MERGE_HEAD"):
    base = subprocess.check_output(["git", "rev-parse", "MERGE_HEAD"], text=True).strip()
    strict_stale = True
elif rev_exists("upstream-sdk/main"):
    base = subprocess.check_output(
        ["git", "merge-base", "HEAD", "upstream-sdk/main"], text=True
    ).strip()
    strict_stale = True
else:
    base_branch = "origin/main" if rev_exists("origin/main") else "main"
    base = subprocess.check_output(
        ["git", "merge-base", "HEAD", base_branch], text=True
    ).strip()
    strict_stale = False

diff_files = [
    p.strip()
    for p in subprocess.check_output(
        ["git", "diff", "--diff-filter=AM", "--name-only", base], text=True
    ).splitlines()
    if p.strip()
]

non_exempt_actual = {p for p in diff_files if not IsAutoExemptOverlayPath(p)}
unapproved = sorted(non_exempt_actual - allowed)
stale = sorted(allowed - non_exempt_actual) if strict_stale else []
auto_exempt_in_list = sorted(p for p in allowed if IsAutoExemptOverlayPath(p))

ok = True
if unapproved:
    print("Modified/added upstream files missing from tools/bazel/allowed_upstream_files.txt:")
    for p in unapproved:
        print(f" - {p}")
    ok = False
if auto_exempt_in_list:
    print("Auto-exempt Bazel overlay files redundantly listed in tools/bazel/allowed_upstream_files.txt:")
    for p in auto_exempt_in_list:
        print(f" - {p}")
    ok = False
if stale:
    print("Stale entries in tools/bazel/allowed_upstream_files.txt (no longer differ from upstream):")
    for p in stale:
        print(f" - {p}")
    ok = False
sys.exit(0 if ok else 1)
PY
  then
    fail "upstream changes audit: mismatch against tools/bazel/allowed_upstream_files.txt"
  fi
fi

step "Starlark copy audit"
starlark_cp_matches=$(git grep -n -E "(ctx|repository_ctx)\.execute *\(.*['\" ]cp['\" ]" -- '*.bzl' 2>/dev/null | grep -v '^third_party/' | grep -v '# exempt-starlark-copy: ok' || true)
if [ -n "$starlark_cp_matches" ]; then
  echo "$starlark_cp_matches"
  fail "Starlark copy audit: ctx.execute with 'cp' found (use ctx.read/ctx.file for hermetic copying, or ctx.symlink)"
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
  matches=$(echo "$audit_files" | xargs grep -H -F -n "$pattern" 2>/dev/null \
    | grep -v '# arch-pinned-variant: ok' || true)
  if [ -n "$matches" ]; then
    echo "$matches"
    fail "architecture audit: $pattern is hardcoded (parameterize via select(), or mark an arch-pinned variant with '# arch-pinned-variant: ok')"
  fi
done
concat_matches=$(echo "$audit_files" | xargs grep -H -n -E '"TARGET_ARCH_"[[:space:]]*\+' 2>/dev/null || true)
if [ -n "$concat_matches" ]; then
  echo "$concat_matches"
  fail "architecture audit: concat-built TARGET_ARCH_ define evades the literal grep (write the honest literal + marker)"
fi

step "starlark & wrapper unit tests"
if ! bazel "${BAZEL_STARTUP_ARGS[@]}" test --config=cloudtop-safe //tools/bazel/...; then
  fail "bazel test --config=cloudtop-safe //tools/bazel/..."
fi
if ! python3 tools/test_wrapper_test.py; then
  fail "python3 tools/test_wrapper_test.py"
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

step "python helpers byte-compile"
if ! git ls-files 'tools/bazel/*.py' 'tools/bazel/**/*.py' | xargs python3 -m py_compile; then
  fail "py_compile of tools/bazel python helpers"
fi

step "bazel analysis (--nobuild) of flagship targets"
if ! bazel "${BAZEL_STARTUP_ARGS[@]}" build --config=cloudtop-safe --nobuild \
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
  OUTPUT_BASE=$(bazel "${BAZEL_STARTUP_ARGS[@]}" info output_base 2>/dev/null || true)
  if [ -n "$OUTPUT_BASE" ]; then
    dart_paths=("$OUTPUT_BASE"/external/*prebuilt_dart_sdk*/bin/dart)
    if [ -x "${dart_paths[0]:-}" ]; then
      DART="${dart_paths[0]}"
    fi
  fi
fi

if [ -z "${BAZEL_BIN:-}" ]; then
  BAZEL_BIN=$(bazel "${BAZEL_STARTUP_ARGS[@]}" info bazel-bin 2>/dev/null || true)
  if [ -n "$BAZEL_BIN" ]; then
    export BAZEL_BIN
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
