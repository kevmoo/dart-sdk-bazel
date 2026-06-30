// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'suite_paths.dart';

void main() {
  var failures = 0;
  void check(dynamic actual, dynamic expected, String name) {
    if (actual != expected) {
      print('FAIL: $name - expected $expected, got $actual');
      failures++;
    } else {
      print('PASS: $name');
    }
  }

  final ws = '/sdk';
  check(getSuiteSourceDir(ws, 'language'), '/sdk/tests/language',
      'language suite source dir');
  check(getSuiteSourceDir(ws, 'corelib'), '/sdk/tests/lib',
      'corelib suite source dir');
  check(getSuiteSourceDir(ws, 'corelib/async'), '/sdk/tests/lib/async',
      'corelib/async suite source dir');
  check(getSuiteSourceDir(ws, 'pkg/compiler'), '/sdk/pkg/compiler',
      'pkg suite source dir');
  check(getSuiteSourceDir(ws, 'co19', '/ext/co19'), '/ext/co19',
      'co19 external repo dir');

  check(getSuiteSourceDir(ws, 'dartdevc'), '/sdk/tests/dartdevc',
      'dartdevc suite source dir');
  check(getSuiteSourceDir(ws, 'fuzzer'), '/sdk/runtime/tools/dartfuzz',
      'fuzzer suite source dir');

  check(getSuiteRelPrefix('language'), 'tests/language', 'language rel prefix');
  check(getSuiteRelPrefix('corelib'), 'tests/lib', 'corelib rel prefix');
  check(getSuiteRelPrefix('corelib/async'), 'tests/lib/async',
      'corelib/async rel prefix');
  check(getSuiteRelPrefix('dartdevc'), 'tests/dartdevc', 'dartdevc rel prefix');
  check(getSuiteRelPrefix('fuzzer'), 'runtime/tools/dartfuzz',
      'fuzzer rel prefix');
  check(getSuiteRelPrefix('pkg/compiler'), 'pkg/compiler', 'pkg rel prefix');

  if (failures > 0) {
    throw Exception('$failures suite_paths tests failed!');
  }
  print('All suite_paths tests passed!');
}
