# Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
# for details. All rights reserved. Use of this source code is governed by a
# BSD-style license that can be found in the LICENSE file.

"""Dynamic Bazel test discovery and target generation rules."""

def _dynamic_test_repo_impl(repository_ctx):
    # repo_ctx.workspace_root is the main repository root (requires Bazel 7+)
    workspace_dir = repository_ctx.workspace_root

    # Resolve the Dart binary through @prebuilt_dart_sdk instead of the raw
    # workspace path: the overlay repo symlinks the gclient-synced
    # tools/sdks/dart-sdk when present and downloads it from CIPD otherwise,
    # so this extension also works on hosts without the workspace copy
    # (CI runners — the raw path made every CI presubmit run fail).
    dart_label = Label("@prebuilt_dart_sdk//:bin/dart")
    dart_path = repository_ctx.path(dart_label)
    repository_ctx.watch(dart_path)
    exporter_path = workspace_dir.get_child("pkg").get_child("test_runner").get_child("bin").get_child("test_runner.dart")

    if not dart_path.exists:
        fail("Could not locate prebuilt Dart SDK at: " + str(dart_path))
    if not exporter_path.exists:
        fail("Could not locate test runner script at: " + str(exporter_path))

    # Watch the generator so edits to it automatically re-fetch this
    # repository (previously that required hand-bumping the trigger comment at
    # the bottom of this file). Resolving a Label to a path is NOT enough on
    # Bazel 7+; the explicit watch() registers the invalidation dependency.
    generator_path = repository_ctx.path(Label("@//tools/bazel/dart:generate_test_targets.dart"))
    repository_ctx.watch(generator_path)

    # The embedded script's "/external/" is runfiles-path string matching, not
    # a fragile external-repo dependency (newer buildifiers flag string contents).
    # buildifier: disable=external-path
    repository_ctx.file("run_single_test.sh", content = """#!/bin/bash
if [ -z "$TEST_SRCDIR" ]; then
  echo "Error: TEST_SRCDIR environment variable is not set!"
  exit 2
fi


DART_BIN=""
if [ -n "$DART_BIN_RLOCATION" ] && [ -f "$TEST_SRCDIR/$DART_BIN_RLOCATION" ]; then
  DART_BIN="$TEST_SRCDIR/$DART_BIN_RLOCATION"
fi
if [ -z "$DART_BIN" ]; then
  for CANDIDATE in \
    "$TEST_SRCDIR/prebuilt_dart_sdk/bin/dart" \
    "$TEST_SRCDIR/_main/external/prebuilt_dart_sdk/bin/dart" \
    "$TEST_SRCDIR/_main/runtime/bin/dartvm" \
    "$TEST_SRCDIR/runtime/bin/dartvm"; do
    if [ -f "$CANDIDATE" ]; then
      DART_BIN="$CANDIDATE"
      break
    fi
  done
fi
if [ -z "$DART_BIN" ]; then
  DART_BIN=$(find -L "$TEST_SRCDIR" -name dart -type f -perm -u+x | head -n 1)
fi

RUNNER_DART=""
if [ -n "$RUNNER_DART_RLOCATION" ] && [ -f "$TEST_SRCDIR/$RUNNER_DART_RLOCATION" ]; then
  RUNNER_DART="$TEST_SRCDIR/$RUNNER_DART_RLOCATION"
fi
if [ -z "$RUNNER_DART" ]; then
  for CANDIDATE in \
    "$TEST_SRCDIR/_main/pkg/test_runner/bin/run_single_test.dart" \
    "$TEST_SRCDIR/pkg/test_runner/bin/run_single_test.dart"; do
    if [ -f "$CANDIDATE" ]; then
      RUNNER_DART="$CANDIDATE"
      break
    fi
  done
fi
if [ -z "$RUNNER_DART" ]; then
  RUNNER_DART=$(find -L "$TEST_SRCDIR" -name run_single_test.dart -type f | head -n 1)
fi

if [ -z "$DART_BIN" ] || [ -z "$RUNNER_DART" ]; then
  echo "Error: Dynamic launcher was unable to locate dart or run_single_test.dart in runfiles!"
  exit 2
fi

PKG_CONFIG=""
if [ -n "$PACKAGE_CONFIG_RLOCATION" ] && [ -f "$TEST_SRCDIR/$PACKAGE_CONFIG_RLOCATION" ]; then
  PKG_CONFIG="$TEST_SRCDIR/$PACKAGE_CONFIG_RLOCATION"
fi
if [ -z "$PKG_CONFIG" ]; then
  for CANDIDATE in \
    "$TEST_SRCDIR/+dart_packages_extension+dart_packages/.dart_tool/package_config.json" \
    "$TEST_SRCDIR/+dart_packages_extension+dart_packages/package_config.json" \
    "$TEST_SRCDIR/dart_packages/.dart_tool/package_config.json" \
    "$TEST_SRCDIR/dart_packages/package_config.json" \
    "$TEST_SRCDIR/_main/.dart_tool/package_config.json" \
    "$TEST_SRCDIR/.dart_tool/package_config.json" \
    "$TEST_SRCDIR/_main/package_config.json" \
    "$TEST_SRCDIR/package_config.json"; do
    if [ -f "$CANDIDATE" ]; then
      PKG_CONFIG="$CANDIDATE"
      break
    fi
  done
fi
if [ -z "$PKG_CONFIG" ]; then
  PKG_CONFIG=$(find -L "$TEST_SRCDIR" -name package_config.json -type f | head -n 1)
fi
if [ -n "$PKG_CONFIG" ]; then
  if [[ "$PKG_CONFIG" == *dart_packages* ]]; then
    DART_PACKAGES_FLAG="--packages=$PKG_CONFIG"
  else
    STAGING_DIR=$(dirname "$PKG_CONFIG")
    mkdir -p "$STAGING_DIR/tools/bazel/dart" 2>/dev/null || true
    cp "$PKG_CONFIG" "$STAGING_DIR/tools/bazel/dart/package_config.json" 2>/dev/null || true
    if [ -f "$STAGING_DIR/tools/bazel/dart/package_config.json" ]; then
      DART_PACKAGES_FLAG="--packages=$STAGING_DIR/tools/bazel/dart/package_config.json"
    else
      DART_PACKAGES_FLAG="--packages=$PKG_CONFIG"
    fi
  fi
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
exec "$DART_BIN" $DART_PACKAGES_FLAG "$RUNNER_DART" "$@"
""", executable = True)

    repository_ctx.file("run_ddc_test.sh", content = """#!/bin/bash
if [ -z "$TEST_SRCDIR" ]; then
  echo "Error: TEST_SRCDIR environment variable is not set!"
  exit 2
fi

DART_BIN=""
if [ -n "$DART_BIN_RLOCATION" ] && [ -f "$TEST_SRCDIR/$DART_BIN_RLOCATION" ]; then
  DART_BIN="$TEST_SRCDIR/$DART_BIN_RLOCATION"
fi
if [ -z "$DART_BIN" ]; then
  for CANDIDATE in \
    "$TEST_SRCDIR/_main/runtime/bin/dartvm" \
    "$TEST_SRCDIR/runtime/bin/dartvm" \
    "$TEST_SRCDIR/_main/dart-sdk/bin/dart" \
    "$TEST_SRCDIR/dart-sdk/bin/dart"; do
    if [ -f "$CANDIDATE" ]; then
      DART_BIN="$CANDIDATE"
      break
    fi
  done
fi
if [ -z "$DART_BIN" ]; then
  DART_BIN=$(find -L "$TEST_SRCDIR" -name dart -type f -perm -u+x | head -n 1)
fi

RUNNER_DART=""
if [ -n "$RUNNER_DART_RLOCATION" ] && [ -f "$TEST_SRCDIR/$RUNNER_DART_RLOCATION" ]; then
  RUNNER_DART="$TEST_SRCDIR/$RUNNER_DART_RLOCATION"
fi
if [ -z "$RUNNER_DART" ]; then
  for CANDIDATE in \
    "$TEST_SRCDIR/_main/pkg/test_runner/bin/run_ddc_test.dart" \
    "$TEST_SRCDIR/pkg/test_runner/bin/run_ddc_test.dart"; do
    if [ -f "$CANDIDATE" ]; then
      RUNNER_DART="$CANDIDATE"
      break
    fi
  done
fi
if [ -z "$RUNNER_DART" ]; then
  RUNNER_DART=$(find -L "$TEST_SRCDIR" -name run_ddc_test.dart -type f | head -n 1)
fi

PKG_CONFIG=""
if [ -n "$PACKAGE_CONFIG_RLOCATION" ] && [ -f "$TEST_SRCDIR/$PACKAGE_CONFIG_RLOCATION" ]; then
  PKG_CONFIG="$TEST_SRCDIR/$PACKAGE_CONFIG_RLOCATION"
fi
if [ -z "$PKG_CONFIG" ]; then
  for CANDIDATE in \
    "$TEST_SRCDIR/+dart_packages_extension+dart_packages/.dart_tool/package_config.json" \
    "$TEST_SRCDIR/+dart_packages_extension+dart_packages/package_config.json" \
    "$TEST_SRCDIR/dart_packages/.dart_tool/package_config.json" \
    "$TEST_SRCDIR/dart_packages/package_config.json" \
    "$TEST_SRCDIR/_main/.dart_tool/package_config.json" \
    "$TEST_SRCDIR/.dart_tool/package_config.json" \
    "$TEST_SRCDIR/_main/package_config.json" \
    "$TEST_SRCDIR/package_config.json"; do
    if [ -f "$CANDIDATE" ]; then
      PKG_CONFIG="$CANDIDATE"
      break
    fi
  done
fi
if [ -z "$PKG_CONFIG" ]; then
  PKG_CONFIG=$(find -L "$TEST_SRCDIR" -name package_config.json -type f | head -n 1)
fi
if [ -n "$PKG_CONFIG" ]; then
  if [[ "$PKG_CONFIG" == *dart_packages* ]]; then
    DART_PACKAGES_FLAG="--packages=$PKG_CONFIG"
  else
    STAGING_DIR=$(dirname "$PKG_CONFIG")
    mkdir -p "$STAGING_DIR/tools/bazel/dart" 2>/dev/null || true
    cp "$PKG_CONFIG" "$STAGING_DIR/tools/bazel/dart/package_config.json" 2>/dev/null || true
    if [ -f "$STAGING_DIR/tools/bazel/dart/package_config.json" ]; then
      DART_PACKAGES_FLAG="--packages=$STAGING_DIR/tools/bazel/dart/package_config.json"
    else
      DART_PACKAGES_FLAG="--packages=$PKG_CONFIG"
    fi
  fi
fi

if [ -z "$DART_BIN" ] || [ -z "$RUNNER_DART" ]; then
  echo "Error: Dynamic launcher was unable to locate dart or run_ddc_test.dart in runfiles!"
  exit 2
fi

export DART_BIN="$DART_BIN"
export DART_PACKAGE_CONFIG_JSON="$PKG_CONFIG"
exec "$DART_BIN" $DART_PACKAGES_FLAG "$RUNNER_DART" "$@"
""", executable = True)

    # Run the dynamic generator natively
    generator_args = [
        str(dart_path),
        str(generator_path),
        "--workspace-dir=" + str(workspace_dir),
        "--output-dir=" + str(repository_ctx.path(".")),
    ]
    generator_args.append("--max-shards=" + str(repository_ctx.attr.max_shards))
    if "co19" in repository_ctx.attr.suites:
        # Note: watch() on unpacked BUILD file does not detect test file changes inside the external repo.
        co19_label = Label("@dart_co19_tests//:BUILD.bazel")
        co19_path = repository_ctx.path(co19_label)
        repository_ctx.watch(co19_path)
        co19_dir = co19_path.dirname
        generator_args.append("--co19-dir=" + str(co19_dir))
    for s in repository_ctx.attr.suites:
        generator_args.append("--suite=" + s)

    res = repository_ctx.execute(generator_args)

    if res.return_code != 0:
        # The generator reports most errors only into debug.log in its output
        # dir (this repo), not stdout/stderr — without reading it back, CI
        # failures are blank "Failed to generate test targets" messages.
        debug_log = repository_ctx.path("debug.log")
        log_content = repository_ctx.read(debug_log) if debug_log.exists else "(no debug.log written)"
        fail("Failed to generate test targets:\n" + res.stderr + "\n" + res.stdout +
             "\n--- debug.log ---\n" + log_content)

# Define the dynamic repository rule.
dynamic_test_repository = repository_rule(
    implementation = _dynamic_test_repo_impl,
    attrs = {
        "max_shards": attr.int(default = 50),
        "suites": attr.string_list(mandatory = True),
    },
)

# Bzlmod module extension wrapper to instantiate the test repository
def _test_ext_impl(ctx):
    dynamic_test_repository(
        name = "dart_tests",
        max_shards = 50,
        suites = [
            "language",
            "corelib",
            "standalone",
            "ffi",
            "pkg",
            "web/wasm",
            "co19",
            "dartdevc",
        ],
    )
    return ctx.extension_metadata(reproducible = True)

dart_tests_extension = module_extension(implementation = _test_ext_impl)
# Edits to generate_test_targets.dart auto-invalidate via the Label resolution
# above. This manual trigger remains ONLY for changes the extension does not
# watch — e.g. adding/removing test files in the suites: bump it to re-scan.
# Force refetch trigger: 59
