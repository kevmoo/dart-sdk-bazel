#!/usr/bin/env python3
# Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
# for details. All rights reserved. Use of this source code is governed by a
# BSD-style license that can be found in the LICENSE file.
"""Bazel build wrapper and target mappings for tools/build.py."""

import os
import subprocess
import sys

tools_dir = os.path.realpath(os.path.join(os.path.dirname(__file__), '..'))
if tools_dir not in sys.path:
    sys.path.insert(0, tools_dir)

import utils

BAZEL_TARGET_MAPPING = {
    'create_sdk': ['//sdk:create_sdk'],
    'dart2wasm': [
        '//utils/dart2wasm:compile_dart2wasm_platform',
        '//utils/dart2wasm:dart2wasm_product_snapshot',
        '//utils/dart2wasm:dart2wasm_asserts_snapshot',
        '//utils/dart2wasm:dart2wasm_snapshot'
    ],
    'dart2wasm_benchmark': [
        '//utils/dart2wasm:compile_dart2wasm_platform',
        '//utils/dart2wasm:dart2wasm_product_snapshot'
    ],
    'dartvm': ['//runtime/bin:dartvm'],
    'runtime': ['//runtime/bin:dartvm'],
    'most': ['//sdk:create_sdk'],
}


def BuildWithBazel(options, targets, env):
    # Run the pruning script to remove conflicting upstream Bazel files
    prune_script = os.path.join(tools_dir, 'prune_third_party_bazel_files.py')
    subprocess.check_call([sys.executable, prune_script])

    bazel_targets = []
    for t in targets:
        if t in BAZEL_TARGET_MAPPING:
            bazel_targets.extend(BAZEL_TARGET_MAPPING[t])
        elif t.startswith('//') or t.startswith('@'):
            bazel_targets.append(t)
        else:
            print(
                "Warning: Unknown GN-to-Bazel target mapping for '%s'. Passing it as raw target."
                % t)
            bazel_targets.append(t)

    if not bazel_targets:
        bazel_targets.append('//sdk:create_sdk')

    for target_os in options.os:
        for mode in options.mode:
            for arch in options.arch:
                for sanitizer in options.sanitizer:
                    bazel_command = [utils.ResolveBazelPath(), 'build']

                    if mode == 'debug':
                        bazel_command.append('--//build/config:dart_debug=true')
                    elif mode == 'product':
                        bazel_command.append(
                            '--//build/config:dart_product=true')

                    if target_os == 'linux' and arch == 'arm64':
                        bazel_command.append(
                            '--platforms=//build/platforms:linux_arm64')
                    elif arch != utils.GuessArchitecture():
                        print(
                            "Warning: Cross-compilation to arch '%s' on OS '%s' is not fully mapped in Bazel yet."
                            % (arch, target_os))

                    bazel_command.extend(bazel_targets)

                    print('Running: ' + ' '.join(bazel_command))
                    returncode = subprocess.call(bazel_command, env=env)
                    if returncode != 0:
                        return returncode
    return 0
