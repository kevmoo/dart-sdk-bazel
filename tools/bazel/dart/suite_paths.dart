// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Resolves canonical source directory paths for test suites.
String getSuiteSourceDir(String workspaceDir, String pkgDir,
    [String? co19Dir]) {
  if (pkgDir == 'co19') {
    return co19Dir ?? '$workspaceDir/tests/co19/src';
  }
  if (pkgDir.startsWith('co19/')) {
    final subSuite = pkgDir.substring('co19/'.length);
    final base = co19Dir ?? '$workspaceDir/tests/co19/src';
    return '$base/$subSuite';
  }
  if (pkgDir == 'fuzzer') {
    return '$workspaceDir/runtime/tools/dartfuzz';
  }
  if (pkgDir.startsWith('fuzzer/')) {
    final subPath = pkgDir.substring('fuzzer/'.length);
    return '$workspaceDir/runtime/tools/dartfuzz/$subPath';
  }
  for (final suite in {
    'corelib',
    'standalone',
    'ffi',
    'language',
    'dartdevc'
  }) {
    if (pkgDir == suite) {
      return '$workspaceDir/tests/$suite';
    }
    if (pkgDir.startsWith('$suite/')) {
      final subPath = pkgDir.substring('$suite/'.length);
      return '$workspaceDir/tests/$suite/$subPath';
    }
  }
  return '$workspaceDir/$pkgDir';
}

/// Resolves the relative workspace path prefix for a test suite.
String getSuiteRelPrefix(String pkgDir) {
  if (pkgDir == 'co19') {
    return 'tests/co19/src';
  }
  if (pkgDir.startsWith('co19/')) {
    final subSuite = pkgDir.substring('co19/'.length);
    return 'tests/co19/src/$subSuite';
  }
  if (pkgDir == 'fuzzer') {
    return 'runtime/tools/dartfuzz';
  }
  if (pkgDir.startsWith('fuzzer/')) {
    final subPath = pkgDir.substring('fuzzer/'.length);
    return 'runtime/tools/dartfuzz/$subPath';
  }
  for (final suite in {
    'corelib',
    'standalone',
    'ffi',
    'language',
    'dartdevc'
  }) {
    if (pkgDir == suite) {
      return 'tests/$suite';
    }
    if (pkgDir.startsWith('$suite/')) {
      final subPath = pkgDir.substring('$suite/'.length);
      return 'tests/$suite/$subPath';
    }
  }
  return pkgDir;
}
