#!/usr/bin/env python3
# Copyright (c) 2011, the Dart project authors.  Please see the AUTHORS file
# for details. All rights reserved. Use of this source code is governed by a
# BSD-style license that can be found in the LICENSE file.

from contextlib import ExitStack
import os
import string
import subprocess
import sys

import utils


def ResolveConfig(named_config):
    repo_name = 'dart_tests'
    injected_flags = []
    suffix = '_vm_release'

    if not named_config:
        return repo_name, suffix, injected_flags

    config_lower = named_config.lower()
    tokens = [t for t in config_lower.replace('-', '_').split('_') if t]

    is_debug = 'debug' in tokens
    is_product = 'product' in tokens

    if is_debug and is_product:
        raise ValueError(
            f"Configuration '{named_config}' cannot contain both 'debug' and 'product'"
        )

    is_wasm = 'wasm' in tokens or 'dart2wasm' in tokens
    is_dart2js = 'dart2js' in tokens
    is_cfe = 'cfe' in tokens or 'fasta' in tokens
    is_aot = 'aot' in tokens

    if 'asan' in tokens:
        injected_flags.append('--features=asan')
    elif 'msan' in tokens:
        injected_flags.append('--features=msan')
    elif 'tsan' in tokens:
        injected_flags.append('--features=tsan')

    arch = None
    for a in [
            'simarm64', 'simarm', 'simriscv64', 'simriscv32', 'arm64', 'arm',
            'riscv64', 'riscv32', 'ia32', 'x64'
    ]:
        if a in tokens:
            arch = a
            break

    if arch:
        injected_flags.append(f'--//build/config:dart_target_arch={arch}')

    if is_wasm:
        browser = None
        if 'chrome' in tokens:
            browser = 'chrome'
        elif 'firefox' in tokens:
            browser = 'firefox'

        modifier = 'release'
        if 'asserts' in tokens:
            modifier = 'asserts'
        elif 'optimized' in tokens:
            modifier = 'optimized'

        if browser:
            suffix = f'_wasm_{browser}_{modifier}'
        else:
            suffix = f'_wasm_{modifier}'
    elif is_dart2js:
        if 'chrome' in tokens:
            suffix = '_dart2js_chrome_release'
        elif 'firefox' in tokens:
            suffix = '_dart2js_firefox_release'
        else:
            suffix = '_dart2js_release'
    elif is_cfe:
        suffix = '_cfe_release'
    elif is_aot:
        if is_product:
            suffix = '_vm_aot_product'
            injected_flags.append('--//build/config:dart_product=true')
        elif is_debug:
            suffix = '_vm_aot_debug'
            injected_flags.append('--//build/config:dart_debug=true')
        else:
            suffix = '_vm_aot_release'
    elif is_debug:
        suffix = '_vm_debug'
        injected_flags.append('--//build/config:dart_debug=true')
    elif is_product:
        suffix = '_vm_product'
        injected_flags.append('--//build/config:dart_product=true')
    else:
        suffix = '_vm_release'

    sim_archs = {'simarm', 'simarm64', 'simriscv32', 'simriscv64'}
    if arch in sim_archs:
        suffix = f'{suffix}_{arch}'

    return repo_name, suffix, injected_flags


def TestWithBazel(args):
    # Run the pruning script to remove conflicting upstream Bazel files
    prune_script = os.path.join(
        os.path.dirname(__file__), 'prune_third_party_bazel_files.py')
    subprocess.check_call([sys.executable, prune_script])

    named_config = None
    remaining_args = []
    i = 0
    while i < len(args):
        arg = args[i]
        if arg == '-n' or arg == '--named-configuration':
            if i + 1 < len(args):
                named_config = args[i + 1]
                i += 2
                continue
        elif arg.startswith('--named-configuration='):
            named_config = arg.split('=', 1)[1]
            i += 1
            continue
        remaining_args.append(arg)
        i += 1

    try:
        repo_name, suffix, injected_flags = ResolveConfig(named_config)
    except ValueError as e:
        print(f"Error: {e}")
        return 1

    selectors = []
    bazel_flags = []
    i = 0
    while i < len(remaining_args):
        arg = remaining_args[i]
        if arg == '-v' or arg == '--verbose':
            bazel_flags.append('--test_output=streamed')
            i += 1
        elif arg == '--test-output=all':
            bazel_flags.append('--test_output=all')
            i += 1
        elif arg == '--test-output=errors':
            bazel_flags.append('--test_output=errors')
            i += 1
        elif arg.startswith('--test-output='):
            val = arg.split('=', 1)[1]
            bazel_flags.append(f'--test_output={val}')
            i += 1
        elif arg == '-j' or arg == '--workers':
            if i + 1 < len(remaining_args):
                bazel_flags.append(f'--local_test_jobs={remaining_args[i+1]}')
                i += 2
            else:
                i += 1
        elif arg.startswith('--workers='):
            val = arg.split('=', 1)[1]
            bazel_flags.append(f'--local_test_jobs={val}')
            i += 1
        elif arg.startswith('-j'):
            val = arg[2:]
            bazel_flags.append(f'--local_test_jobs={val}')
            i += 1
        elif arg == '--test-filter':
            if i + 1 < len(remaining_args):
                bazel_flags.append(f'--test_filter={remaining_args[i+1]}')
                i += 2
            else:
                i += 1
        elif arg.startswith('--test-filter='):
            val = arg.split('=', 1)[1]
            bazel_flags.append(f'--test_filter={val}')
            i += 1
        elif arg == '--repeat':
            if i + 1 < len(remaining_args):
                bazel_flags.append(f'--runs_per_test={remaining_args[i+1]}')
                i += 2
            else:
                i += 1
        elif arg.startswith('--repeat='):
            val = arg.split('=', 1)[1]
            bazel_flags.append(f'--runs_per_test={val}')
            i += 1
        elif arg.startswith('-'):
            # Skip unsupported test runner flags
            i += 1
        else:
            selectors.append(arg)
            i += 1

    if not selectors:
        print(
            "Error: Bazel test delegation requires at least one test selector (e.g., 'web/wasm/simd/vector_test')."
        )
        return 1

    # Query all targets recursively in the dynamic test repository
    query_command = [utils.ResolveBazelPath(), 'query', f'@{repo_name}//...']
    process = subprocess.Popen(query_command,
                               stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE)
    out, err = process.communicate()
    if process.returncode != 0:
        print(
            f"Error: Failed to query Bazel targets for repository '@{repo_name}'. Make sure the named configuration is valid."
        )
        return 1
    all_targets = [
        t.strip() for t in out.decode('utf-8').splitlines() if t.strip()
    ]

    bazel_targets = []
    filter_parts = []
    for selector in selectors:
        name = selector
        if name.startswith('tests/'):
            name = name[len('tests/'):]
        if name.endswith('.dart'):
            name = name[:-len('.dart')]

        parts = name.split('/')
        coarse_suites = {"corelib", "standalone", "ffi", "language"}
        if parts and parts[0] in coarse_suites:
            pkg_dir = parts[0]
        elif len(parts) >= 2:
            pkg_dir = f"{parts[0]}/{parts[1]}"
        else:
            pkg_dir = f"{parts[0]}/misc"

        target = f"@{repo_name}//{pkg_dir}:tests{suffix}"
        rel_path = name[len(pkg_dir) + 1:] if len(name) > len(pkg_dir) else ""
        fine_grained_target_name = rel_path.replace('/', '_')
        if fine_grained_target_name.endswith('.dart'):
            fine_grained_target_name = fine_grained_target_name[:-5]
        fine_grained_target = f"@{repo_name}//{pkg_dir}:{fine_grained_target_name}{suffix}" if fine_grained_target_name else ""

        if fine_grained_target and fine_grained_target in all_targets:
            if fine_grained_target not in bazel_targets:
                bazel_targets.append(fine_grained_target)
        elif target in all_targets:
            if target not in bazel_targets:
                bazel_targets.append(target)
            filter_parts.append(name)
        else:
            # Support deep directory selectors in fine-grained packages
            matched = False
            if len(name) > len(pkg_dir):
                target_prefix = rel_path.replace('/', '_')
                pkg_prefix = f"@{repo_name}//{pkg_dir}:"
                matches = []
                for t in all_targets:
                    if t.startswith(pkg_prefix) and t.endswith(suffix):
                        target_name = t.split(':', 1)[1]
                        target_name_nosuffix = target_name[:-len(
                            suffix)] if suffix else target_name
                        if target_name_nosuffix.startswith(target_prefix):
                            matches.append(t)
                if matches:
                    for m in matches:
                        if m not in bazel_targets:
                            bazel_targets.append(m)
                    matched = True

            if not matched:
                # Support broad directory suite selectors (e.g. 'web', 'language')
                prefix1 = f"@{repo_name}//{name}/"
                prefix2 = f"@{repo_name}//{name}:"
                matches = [
                    t for t in all_targets
                    if (t.startswith(prefix1) or t.startswith(prefix2)) and
                    t.endswith(suffix)
                ]
                if matches:
                    for m in matches:
                        if m not in bazel_targets:
                            bazel_targets.append(m)
                    filter_parts.append(name)
                    matched = True

            if not matched:
                print(
                    f"Warning: No matching Bazel test targets found for selector '{selector}' under configuration '{repo_name}' with suffix '{suffix}'"
                )

    if not bazel_targets:
        print(
            "Error: No valid Bazel test targets were resolved from the selectors."
        )
        return 1

    if filter_parts:
        combined_filter = '|'.join(filter_parts)
        bazel_flags.append(f'--test_filter={combined_filter}')

    bazel_command = [utils.ResolveBazelPath(), 'test'
                    ] + injected_flags + bazel_flags + bazel_targets
    print('Running Bazel Tests: ' + ' '.join(bazel_command))
    process = subprocess.Popen(bazel_command)
    process.wait()
    return process.returncode


def Main():
    args = sys.argv[1:]

    use_bazel = False
    if '--bazel' in args:
        args.remove('--bazel')
        use_bazel = True

    if use_bazel:
        return TestWithBazel(args)

    cleanup_dart = False
    if '--cleanup-dart-processes' in args:
        args.remove('--cleanup-dart-processes')
        cleanup_dart = True

    tools_dir = os.path.dirname(os.path.realpath(__file__))
    repo_dir = os.path.dirname(tools_dir)
    dart_test_script = os.path.join(repo_dir, 'pkg', 'test_runner', 'bin',
                                    'test_runner.dart')
    command = [utils.CheckedInSdkExecutable(), dart_test_script] + args

    # The testing script potentially needs the android platform tools in PATH so
    # we do that in ./tools/test.py (a similar logic exists in ./tools/build.py).
    android_platform_tools = os.path.normpath(
        os.path.join(tools_dir,
                     '../third_party/android_tools/sdk/platform-tools'))
    if os.path.isdir(android_platform_tools):
        os.environ['PATH'] = '%s%s%s' % (os.environ['PATH'], os.pathsep,
                                         android_platform_tools)

    with utils.FileDescriptorLimitIncreaser():
        with ExitStack() as stack:
            for ctx in utils.CoreDumpArchiver(args):
                stack.enter_context(ctx)
            exit_code = subprocess.call(command)

    if cleanup_dart:
        cleanup_command = [
            sys.executable,
            os.path.join(tools_dir, 'task_kill.py'), '--kill_dart=True',
            '--kill_vc=False'
        ]
        subprocess.call(cleanup_command)

    utils.DiagnoseExitCode(exit_code, command)
    return exit_code


if __name__ == '__main__':
    sys.exit(Main())
