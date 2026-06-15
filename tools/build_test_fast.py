#!/usr/bin/env python3
# Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
# for details. All rights reserved. Use of this source code is governed by a
# BSD-style license that can be found in the LICENSE file.

# build_test_fast.py
#
# A smart wrapper around tools/build.py and tools/test.py that uses a
# minimal, hardcoded mapping to determine exactly what needs to be built.
# This avoids building the entire SDK (like CI does) just to run a single test.

import sys
import os
import subprocess
import platform


def get_host_os():
    if sys.platform == 'win32':
        return 'win'
    elif sys.platform == 'darwin':
        return 'mac'
    return 'linux'


def get_host_arch():
    machine = platform.machine().lower()
    if machine in ['arm64', 'aarch64']:
        return 'arm64'
    return 'x64'



def guess_compiler_from_paths(test_paths):
    # Try to guess the best compiler based on the test paths
    for path in test_paths:
        # Wasm tests
        if 'tests/web/wasm' in path or 'pkg/dart2wasm' in path:
            return 'dart2wasm'
        # DDC specific tests
        elif 'tests/dartdevc' in path or 'pkg/dev_compiler' in path:
            return 'ddc'
        # General web / dart2js tests
        elif 'tests/web' in path or 'pkg/compiler' in path:
            return 'dart2js'
        # Analyzer / language server tests
        elif 'pkg/analyzer' in path or 'pkg/analysis_server' in path:
            return 'dart2analyzer'

    # Default to the VM's JIT compiler
    return 'dartk'


def main():
    args = sys.argv[1:]

    compiler = None
    runtime = None
    test_paths = []

    # test.py defaults to release mode, while build.py defaults to debug.
    # We MUST pass the mode and arch explicitly to build.py to match.
    mode = 'release'
    arch = get_host_arch()
    system = get_host_os()

    # Parse out compiler, mode, arch and test paths
    skip_next = False
    for i, arg in enumerate(args):
        if skip_next:
            skip_next = False
            continue

        if arg == '-c' or arg == '--compiler':
            compiler = args[i + 1]
            skip_next = True
        elif arg.startswith('--compiler='):
            compiler = arg.split('=', 1)[1]
        elif arg == '-m' or arg == '--mode':
            mode = args[i + 1]
            skip_next = True
        elif arg.startswith('--mode='):
            mode = arg.split('=', 1)[1]
        elif arg == '-a' or arg == '--arch':
            arch = args[i + 1]
            skip_next = True
        elif arg.startswith('--arch='):
            arch = arg.split('=', 1)[1]
        elif arg == '-r' or arg == '--runtime':
            runtime = args[i + 1]
            skip_next = True
        elif arg.startswith('--runtime='):
            runtime = arg.split('=', 1)[1]
        elif not arg.startswith('-'):
            test_paths.append(arg)

    # 1. Discover tests and exact metadata via dump-test-metadata
    tools_dir = os.path.dirname(os.path.abspath(__file__))
    test_script = os.path.join(tools_dir, 'test.py')
    if not os.path.exists(test_script):
        tools_dir = os.path.join(os.getcwd(), 'tools')
        test_script = os.path.join(tools_dir, 'test.py')

    import tempfile
    meta_json_path = os.path.join(tempfile.gettempdir(), 'build_test_fast_meta.json')
    if os.path.exists(meta_json_path):
        try:
            os.remove(meta_json_path)
        except:
            pass

    # If compiler wasn't explicitly passed, guess the compiler to seed test discovery correctly
    inferred = False
    meta_args = list(args)
    if compiler is None:
        guessed = guess_compiler_from_paths(test_paths)
        meta_args = ['-c', guessed] + meta_args
        inferred = True

    meta_cmd = [sys.executable, test_script] + meta_args + [f'--dump-test-metadata={meta_json_path}']
    print(f"🔍 Discovering test graph: python3 tools/test.py {' '.join(meta_args)} --dump-test-metadata=...")
    meta_result = subprocess.run(meta_cmd, stdout=subprocess.DEVNULL)
    if meta_result.returncode != 0 or not os.path.exists(meta_json_path):
        print("❌ Test discovery failed! Please check your test selectors and arguments.")
        sys.exit(meta_result.returncode if meta_result.returncode != 0 else 1)

    import json
    with open(meta_json_path, 'r') as f:
        test_cases = json.load(f)

    if not test_cases:
        print("❓ No tests matched your selectors! Please check your test paths/arguments.\n")
        sys.exit(0)

    # Extract all required compilers from the discovered test cases
    if compiler is None:
        discovered_compilers = set(tc.get('compiler', 'dartk').lower() for tc in test_cases)
        discovered_compilers = set('dartk' if c == 'dart2bytecode' else c for c in discovered_compilers)
        compiler = list(discovered_compilers)[0] if discovered_compilers else 'dartk'
        print(f"🔮 Empirically discovered compilers from test matrix: {' '.join(f'[{c}]' for c in discovered_compilers)}")
    else:
        discovered_compilers = {compiler.lower()}

    # Default to d8 for web tests to reduce noise, if no runtime specified
    inferred_runtime = False
    if runtime is None and any(c in ['dart2js', 'dart2wasm', 'ddc'] for c in discovered_compilers):
        runtime = 'd8'
        inferred_runtime = True
        print(f"🔮 Inferred runtime '\033[1m{runtime}\033[0m' for web compiler to reduce noise.")

    build_args = set()
    for tc in test_cases:
        build_args.update(tc.get('build_targets', []))

    build_args = list(build_args)
    targets_str = ' '.join(build_args) if build_args else '(none)'
    print(f"🎯 Determined minimal build targets: \033[1m{targets_str}\033[0m")

    stars_line = "🔹 " * 35

    if build_args:
        # 3. Build Dart using the minimal targets, matching test.py's mode and arch defaults
        build_script = os.path.join(tools_dir, 'build.py')
        build_cmd = [sys.executable, build_script, '-m', mode, '-a', arch] + build_args
        print(f"🚀 Building: python3 tools/build.py {' '.join(build_cmd[2:])}")
        print(stars_line)

        build_result = subprocess.run(build_cmd)
        print(stars_line)

        if build_result.returncode != 0:
            print("❌ Build failed! Aborting test run.")
            sys.exit(build_result.returncode)

        print("⭐⭐⭐ Build succeeded! ⭐⭐⭐\n")
    else:
        print("❓ No build targets required!\n")

    # 4. Run the tests
    if inferred:
        args = ['-c', compiler] + args

    if inferred_runtime:
        args = ['-r', runtime] + args

    # Ensure mode and arch match our build execution exactly
    if not any(a in ['-m', '--mode'] for a in args):
        args = ['-m', mode] + args
    if not any(a in ['-a', '--arch'] for a in args):
        args = ['-a', arch] + args

    test_cmd = [sys.executable, test_script] + args
    print(f"🧪 Running tests: python3 tools/test.py {' '.join(args)}")
    print(stars_line)
    test_result = subprocess.run(test_cmd)
    print(stars_line)

    if test_result.returncode != 0:
        print("\n" + "⚠️ " * 35)
        print("  TEST FAILED!")
        print(
            "If this failure looks like a missing file, missing snapshot, or compilation error,"
        )
        print(
            "it's possible that `build_test_fast.py` didn't build all the required dependencies."
        )
        print(
            "💡 You may need to update the `get_minimal_build_targets()` mapping in this script."
        )
        print(
            "   (Check tools/bots/test_matrix.json to see what CI builds for this test suite!)"
        )
        print("⚠️ " * 35 + "\n")
    else:
        print("⭐⭐⭐ Tests succeeded! ⭐⭐⭐")

    sys.exit(test_result.returncode)


if __name__ == '__main__':
    main()
