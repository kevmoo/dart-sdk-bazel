// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Resolves canonical source directory paths for test suites.
String getSuiteSourceDir(String workspaceDir, String pkgDir,
    [String? co19Dir]) {
  if (pkgDir == 'co19') {
    return co19Dir ?? '$workspaceDir/tests/co19/src';
  }
  if (const {'corelib', 'standalone', 'ffi', 'language'}.contains(pkgDir)) {
    return '$workspaceDir/tests/$pkgDir';
  }
  return '$workspaceDir/$pkgDir';
}

/// Resolves the relative workspace path prefix for a test suite.
String getSuiteRelPrefix(String pkgDir) {
  if (const {'corelib', 'standalone', 'ffi', 'language'}.contains(pkgDir)) {
    return 'tests/$pkgDir';
  }
  return pkgDir;
}
