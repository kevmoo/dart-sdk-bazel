# Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
# for details. All rights reserved. Use of this source code is governed by a
# BSD-style license that can be found in the LICENSE file.

"""Dynamic Bazel test discovery and target generation rules."""

def _dynamic_test_repo_impl(repository_ctx):
    # repo_ctx.workspace_root is the main repository root (requires Bazel 7+)
    workspace_dir = repository_ctx.workspace_root

    # Locate the prebuilt Dart SDK executable and exporter script
    dart_path = workspace_dir.get_child("tools").get_child("sdks").get_child("dart-sdk").get_child("bin").get_child("dart")
    exporter_path = workspace_dir.get_child("pkg").get_child("test_runner").get_child("bin").get_child("test_runner.dart")

    if not dart_path.exists:
        fail("Could not locate prebuilt Dart SDK at: " + str(dart_path))
    if not exporter_path.exists:
        fail("Could not locate test runner script at: " + str(exporter_path))

    # Define the generator script path
    generator_path = workspace_dir.get_child("tools").get_child("bazel").get_child("dart").get_child("generate_test_targets.dart")

    # The embedded script's "/external/" is runfiles-path string matching, not
    # a fragile external-repo dependency (newer buildifiers flag string contents).
    # buildifier: disable=external-path
    repository_ctx.file("run_single_test.sh", content = """#!/bin/bash
if [ -z "$TEST_SRCDIR" ]; then
  echo "Error: TEST_SRCDIR environment variable is not set!"
  exit 2
fi

DART_BIN=$(find -L "$TEST_SRCDIR" -name dart -type f -perm -u+x | head -n 1)
RUNNER_DART=$(find -L "$TEST_SRCDIR" -name run_single_test.dart -type f | head -n 1)

if [ -z "$DART_BIN" ] || [ -z "$RUNNER_DART" ]; then
  echo "Error: Dynamic launcher was unable to locate dart or run_single_test.dart in runfiles!"
  exit 2
fi

PKG_CONFIG=$(find -L "$TEST_SRCDIR" -name package_config.json -type f | head -n 1)
if [ -n "$PKG_CONFIG" ]; then
  STAGING_DIR=$(dirname "$PKG_CONFIG")
  mkdir -p "$STAGING_DIR/tools/bazel/dart"
  cp "$PKG_CONFIG" "$STAGING_DIR/tools/bazel/dart/package_config.json"
fi

CHROMEDRIVER_BIN=""
for path in \
  "$TEST_SRCDIR/chromedriver/chromedriver" \
  "$TEST_SRCDIR/_main/external/chromedriver/chromedriver" \
  "$TEST_SRCDIR/chromedriver/chromedriver.exe" \
  "$TEST_SRCDIR/_main/external/chromedriver/chromedriver.exe"; do
  if [ -f "$path" ] && [ -x "$path" ]; then
    CHROMEDRIVER_BIN="$path"
    break
  fi
done

if [ -z "$CHROMEDRIVER_BIN" ]; then
  CHROMEDRIVER_BIN=$(find -L "$TEST_SRCDIR" \\( -name chromedriver -o -name chromedriver.exe \\) -type f -perm -u+x 2>/dev/null | head -n 1)
fi
if [ -n "$CHROMEDRIVER_BIN" ]; then
  export CHROMEDRIVER_PATH="$CHROMEDRIVER_BIN"
fi

export DART_BIN="$DART_BIN"
exec "$DART_BIN" "$RUNNER_DART" "$@"
""", executable = True)

    # Run the dynamic generator natively
    generator_args = [
        str(dart_path),
        str(generator_path),
        "--workspace-dir=" + str(workspace_dir),
        "--output-dir=" + str(repository_ctx.path(".")),
    ]
    for s in repository_ctx.attr.suites:
        generator_args.append("--suite=" + s)

    res = repository_ctx.execute(generator_args)

    if res.return_code != 0:
        fail("Failed to generate test targets:\n" + res.stderr + "\n" + res.stdout)

# Define the dynamic repository rule.
dynamic_test_repository = repository_rule(
    implementation = _dynamic_test_repo_impl,
    attrs = {
        "suites": attr.string_list(mandatory = True),
    },
)

# Bzlmod module extension wrapper to instantiate the test repository
def _test_ext_impl(ctx):
    dynamic_test_repository(
        name = "dart_tests",
        suites = [
            "language",
            "corelib",
            "standalone",
            "ffi",
            "pkg",
            "web/wasm",
        ],
    )
    return ctx.extension_metadata(reproducible = True)

dart_tests_extension = module_extension(implementation = _test_ext_impl)
# Force refetch trigger: 21
