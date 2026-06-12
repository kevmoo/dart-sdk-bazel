#!/usr/bin/env python3
# Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
# for details. All rights reserved. Use of this source code is governed by a
# BSD-style license that can be found in the LICENSE file.

import io
import os
import sys
import unittest
from unittest.mock import MagicMock, patch, mock_open

# Ensure tools directory is in path to import test.py
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test


class TestResolveConfig(unittest.TestCase):

    def test_default_config(self):
        repo, suffix, flags = test.ResolveConfig(None)
        self.assertEqual(repo, 'dart_tests')
        self.assertEqual(suffix, '_vm_release')
        self.assertEqual(flags, [])

    def test_wasm_configs(self):
        repo, suffix, flags = test.ResolveConfig('dart2wasm-linux-d8')
        self.assertEqual(suffix, '_wasm_release')
        self.assertEqual(flags, [])

        repo, suffix, flags = test.ResolveConfig('dart2wasm-asserts-d8')
        self.assertEqual(suffix, '_wasm_asserts')
        self.assertEqual(flags, [])

        repo, suffix, flags = test.ResolveConfig('dart2wasm-optimized-d8')
        self.assertEqual(suffix, '_wasm_optimized')
        self.assertEqual(flags, [])

    def test_cfe_config(self):
        repo, suffix, flags = test.ResolveConfig('cfe')
        self.assertEqual(suffix, '_cfe_release')
        self.assertEqual(flags, [])

    def test_vm_debug_config(self):
        repo, suffix, flags = test.ResolveConfig('debug_x64')
        self.assertEqual(suffix, '_vm_debug')
        self.assertEqual(flags, [
            '--//build/config:dart_target_arch=x64',
            '--//build/config:dart_debug=true'
        ])

    def test_vm_product_config(self):
        repo, suffix, flags = test.ResolveConfig('product_x64')
        self.assertEqual(suffix, '_vm_product')
        self.assertEqual(flags, [
            '--//build/config:dart_target_arch=x64',
            '--//build/config:dart_product=true'
        ])

    def test_sanitizer_configs(self):
        repo, suffix, flags = test.ResolveConfig('dart-asan')
        self.assertEqual(suffix, '_vm_release')
        self.assertEqual(flags, ['--features=asan'])

        repo, suffix, flags = test.ResolveConfig('debug_x64_asan')
        self.assertEqual(suffix, '_vm_debug')
        self.assertEqual(flags, [
            '--features=asan', '--//build/config:dart_target_arch=x64',
            '--//build/config:dart_debug=true'
        ])

        repo, suffix, flags = test.ResolveConfig('product_x64_tsan')
        self.assertEqual(suffix, '_vm_product')
        self.assertEqual(flags, [
            '--features=tsan', '--//build/config:dart_target_arch=x64',
            '--//build/config:dart_product=true'
        ])

    def test_aot_configs(self):
        repo, suffix, flags = test.ResolveConfig('vm-aot-release-x64')
        self.assertEqual(suffix, '_vm_aot_release')
        self.assertEqual(flags, ['--//build/config:dart_target_arch=x64'])

        repo, suffix, flags = test.ResolveConfig('vm-aot-debug-x64')
        self.assertEqual(suffix, '_vm_aot_debug')
        self.assertEqual(flags, [
            '--//build/config:dart_target_arch=x64',
            '--//build/config:dart_debug=true'
        ])

        repo, suffix, flags = test.ResolveConfig('vm-aot-product-x64')
        self.assertEqual(suffix, '_vm_aot_product')
        self.assertEqual(flags, [
            '--//build/config:dart_target_arch=x64',
            '--//build/config:dart_product=true'
        ])

    def test_mutual_exclusion_errors(self):
        with self.assertRaises(ValueError) as ctx:
            test.ResolveConfig('vm-debug-product-x64')
        self.assertIn("cannot contain both 'debug' and 'product'",
                      str(ctx.exception))

    def test_browser_configs_with_modifiers(self):
        # dart2wasm-asserts-chrome -> _wasm_chrome_asserts
        repo, suffix, flags = test.ResolveConfig('dart2wasm-asserts-chrome')
        self.assertEqual(suffix, '_wasm_chrome_asserts')
        self.assertEqual(flags, [])

        # dart2wasm-optimized-chrome -> _wasm_chrome_optimized
        repo, suffix, flags = test.ResolveConfig('dart2wasm-optimized-chrome')
        self.assertEqual(suffix, '_wasm_chrome_optimized')
        self.assertEqual(flags, [])

        # dart2wasm-asserts-firefox -> _wasm_firefox_asserts
        repo, suffix, flags = test.ResolveConfig('dart2wasm-asserts-firefox')
        self.assertEqual(suffix, '_wasm_firefox_asserts')
        self.assertEqual(flags, [])

        # dart2wasm-optimized-firefox -> _wasm_firefox_optimized
        repo, suffix, flags = test.ResolveConfig('dart2wasm-optimized-firefox')
        self.assertEqual(suffix, '_wasm_firefox_optimized')
        self.assertEqual(flags, [])


class TestTestWithBazel(unittest.TestCase):

    def setUp(self):
        self.mock_targets = [
            '@dart_tests//corelib:tests_vm_release',
            '@dart_tests//corelib:list_test_none_vm_release',
            '@dart_tests//corelib:list_test_01_vm_release',
            '@dart_tests//pkg/smith:tests_vm_release',
            '@dart_tests//pkg/smith:smith_test_vm_release',
            '@dart_tests//web/wasm:tests_wasm_release',
            '@dart_tests//web/wasm:ffi_test_wasm_release',
        ]
        # Mock subprocess.check_call to prevent running the pruning script during unit tests
        self.patcher_check_call = patch('subprocess.check_call')
        self.mock_check_call = self.patcher_check_call.start()
        self.addCleanup(self.patcher_check_call.stop)

    def _mock_popen(self,
                    query_stdout=b'',
                    query_returncode=0,
                    test_returncode=0):
        mock_process_query = MagicMock()
        mock_process_query.communicate.return_value = (query_stdout, b'')
        mock_process_query.returncode = query_returncode

        mock_process_test = MagicMock()
        mock_process_test.wait.return_value = test_returncode
        mock_process_test.returncode = test_returncode

        def popen_side_effect(args, **kwargs):
            if 'query' in args:
                return mock_process_query
            else:
                return mock_process_test

        return popen_side_effect

    @patch('subprocess.Popen')
    @patch('utils.ResolveBazelPath', return_value='bazel')
    def test_no_selectors(self, mock_resolve_bazel, mock_popen):
        # Redirect stdout to capture error message
        captured_output = io.StringIO()
        sys.stdout = captured_output

        try:
            exit_code = test.TestWithBazel([])
            self.assertEqual(exit_code, 1)
            self.assertIn(
                "Error: Bazel test delegation requires at least one test selector",
                captured_output.getvalue())
        finally:
            sys.stdout = sys.__stdout__

    @patch('subprocess.Popen')
    @patch('utils.ResolveBazelPath', return_value='bazel')
    def test_query_failure(self, mock_resolve_bazel, mock_popen):
        mock_popen.side_effect = self._mock_popen(query_returncode=1)

        captured_output = io.StringIO()
        sys.stdout = captured_output

        try:
            exit_code = test.TestWithBazel(['corelib/list_test'])
            self.assertEqual(exit_code, 1)
            self.assertIn("Error: Failed to query Bazel targets",
                          captured_output.getvalue())
        finally:
            sys.stdout = sys.__stdout__

    @patch('subprocess.Popen')
    @patch('utils.ResolveBazelPath', return_value='bazel')
    def test_resolve_fine_grained_target(self, mock_resolve_bazel, mock_popen):
        query_output = '\n'.join(self.mock_targets).encode('utf-8')
        mock_popen.side_effect = self._mock_popen(query_stdout=query_output)

        captured_output = io.StringIO()
        sys.stdout = captured_output

        try:
            # corelib/list_test has fine-grained targets list_test_none and list_test_01.
            # But the selector is 'corelib/list_test'.
            # Wait, in tools/test.py, if name.endswith('.dart') we strip it.
            # If selector is 'corelib/list_test', it maps to:
            # target = @dart_tests//corelib:tests_vm_release
            # fine_grained_target = @dart_tests//corelib:list_test_vm_release (which is not in mock_targets, but list_test_none_vm_release is)
            # Wait, list_test has subtests. Let's see how it matches.
            # If we pass 'corelib/list_test/none', it maps to:
            # pkg_dir = corelib
            # rel_path = list_test/none -> fine_grained_target_name = list_test_none
            # fine_grained_target = @dart_tests//corelib:list_test_none_vm_release
            # This should match!
            exit_code = test.TestWithBazel(['corelib/list_test/none'])
            self.assertEqual(exit_code, 0)

            # Verify the bazel command run
            self.assertIn(
                "Running Bazel Tests: bazel test @dart_tests//corelib:list_test_none_vm_release",
                captured_output.getvalue())
        finally:
            sys.stdout = sys.__stdout__

    @patch('subprocess.Popen')
    @patch('utils.ResolveBazelPath', return_value='bazel')
    def test_resolve_coarse_grained_target(self, mock_resolve_bazel,
                                           mock_popen):
        query_output = '\n'.join(self.mock_targets).encode('utf-8')
        mock_popen.side_effect = self._mock_popen(query_stdout=query_output)

        captured_output = io.StringIO()
        sys.stdout = captured_output

        try:
            # If we pass 'corelib/list_test' and 'corelib:list_test_vm_release' doesn't exist,
            # it should fall back to '@dart_tests//corelib:tests_vm_release' with filter '--test_filter=corelib/list_test'
            exit_code = test.TestWithBazel(['corelib/list_test'])
            self.assertEqual(exit_code, 0)
            self.assertIn(
                "Running Bazel Tests: bazel test --test_filter=corelib/list_test @dart_tests//corelib:tests_vm_release",
                captured_output.getvalue())
        finally:
            sys.stdout = sys.__stdout__

    @patch('subprocess.Popen')
    @patch('utils.ResolveBazelPath', return_value='bazel')
    def test_resolve_deep_directory_selector(self, mock_resolve_bazel,
                                             mock_popen):
        query_output = '\n'.join(self.mock_targets).encode('utf-8')
        mock_popen.side_effect = self._mock_popen(query_stdout=query_output)

        captured_output = io.StringIO()
        sys.stdout = captured_output

        try:
            # Support deep directory selectors in fine-grained packages
            # E.g. pkg/smith/smith_test -> should match @dart_tests//pkg/smith:smith_test_vm_release
            exit_code = test.TestWithBazel(['pkg/smith/smith_test'])
            self.assertEqual(exit_code, 0)
            self.assertIn(
                "Running Bazel Tests: bazel test @dart_tests//pkg/smith:smith_test_vm_release",
                captured_output.getvalue())
        finally:
            sys.stdout = sys.__stdout__

    @patch('subprocess.Popen')
    @patch('utils.ResolveBazelPath', return_value='bazel')
    def test_resolve_broad_directory_selector(self, mock_resolve_bazel,
                                              mock_popen):
        query_output = '\n'.join(self.mock_targets).encode('utf-8')
        mock_popen.side_effect = self._mock_popen(query_stdout=query_output)

        captured_output = io.StringIO()
        sys.stdout = captured_output

        try:
            # E.g. 'web' should match all targets under web/
            # In mock_targets we have:
            # @dart_tests//web/wasm:tests_wasm_release
            # @dart_tests//web/wasm:ffi_test_wasm_release
            # If we run with -n dart2wasm-linux-d8 (suffix: _wasm_release)
            exit_code = test.TestWithBazel(['-n', 'dart2wasm-linux-d8', 'web'])
            self.assertEqual(exit_code, 0)
            # It should match both web/wasm targets
            # Order might vary, so we check they are in the command
            command_line = captured_output.getvalue()
            self.assertIn("Running Bazel Tests: bazel test", command_line)
            self.assertIn("@dart_tests//web/wasm:tests_wasm_release",
                          command_line)
            self.assertIn("@dart_tests//web/wasm:ffi_test_wasm_release",
                          command_line)
            self.assertIn("--test_filter=web", command_line)
        finally:
            sys.stdout = sys.__stdout__

    @patch('subprocess.Popen')
    @patch('utils.ResolveBazelPath', return_value='bazel')
    def test_invalid_selector_warning(self, mock_resolve_bazel, mock_popen):
        query_output = '\n'.join(self.mock_targets).encode('utf-8')
        mock_popen.side_effect = self._mock_popen(query_stdout=query_output)

        captured_output = io.StringIO()
        sys.stdout = captured_output

        try:
            exit_code = test.TestWithBazel(['nonexistent/test'])
            self.assertEqual(exit_code, 1)
            self.assertIn(
                "Error: No matching Bazel test targets found for selector 'nonexistent/test'",
                captured_output.getvalue())
            self.assertIn(
                "Error: The following selectors did not match any Bazel targets: nonexistent/test",
                captured_output.getvalue())
        finally:
            sys.stdout = sys.__stdout__


if __name__ == '__main__':
    unittest.main()
