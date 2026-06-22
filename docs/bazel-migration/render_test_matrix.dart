// Copyright (c) 2026, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  final inputPath = args.isNotEmpty
      ? args[0]
      : 'docs/bazel-migration/test_matrix_results.json';
  final outputPath = args.length > 1
      ? args[1]
      : 'docs/bazel-migration/TEST_COMPLETION_MATRIX.md';

  final inFile = File(inputPath);
  if (!inFile.existsSync()) {
    print('❌ Error: Could not locate JSON source of truth at: $inputPath');
    print('Please run `dart tools/bazel/run_test_universe.dart` first.');
    exit(1);
  }

  final data = jsonDecode(inFile.readAsStringSync()) as Map<String, dynamic>;
  final timestamp = data['timestamp'] as String;
  final interval = data['watchdog_interval_seconds'] as int;
  final gapAnalysis = data['universe_gap_analysis'] as Map<String, dynamic>;
  final configs = data['config_results'] as Map<String, dynamic>;

  final buf = StringBuffer();
  buf.writeln('# Dart SDK Bazel Test Completion Matrix & Gap Analysis');
  buf.writeln();
  buf.writeln('* **Generated At:** `$timestamp`');
  buf.writeln(
    '* **Source of Truth:** [`test_matrix_results.json`](./test_matrix_results.json)',
  );
  buf.writeln('* **Watchdog Watch Interval:** `${interval}s` (5 minutes)');
  buf.writeln();
  buf.writeln('---');
  buf.writeln();
  buf.writeln('## 🌌 Active Starlark Test Universe');
  buf.writeln();
  buf.writeln('| Configuration | Status | Total Targets | Passed | Failed |');
  buf.writeln('|---|---|---|---|---|');

  final sortedCfgNames = configs.keys.toList()..sort();
  var totalUniverseTargets = 0;
  var totalPassed = 0;
  var totalFailed = 0;

  for (final cfgName in sortedCfgNames) {
    final cfg = configs[cfgName] as Map<String, dynamic>;
    final total = cfg['total_targets'] as int;
    final passed = cfg['passed'] as int;
    final failed = cfg['failed'] as int;
    final status = cfg['status'] as String;

    totalUniverseTargets += total;
    totalPassed += passed;
    totalFailed += failed;

    final statusIcon = failed > 0
        ? '❌ FAILED'
        : (total == 0 ? '❄️ Skipped' : '✅ PASSED');
    buf.writeln(
      '| `$cfgName` | $statusIcon ($status) | $total | $passed | $failed |',
    );
  }

  buf.writeln();
  buf.writeln(
    '**Universe Totals:** `$totalUniverseTargets` targets (`$totalPassed` passed, `$totalFailed` failed)',
  );
  buf.writeln();
  buf.writeln('---');
  buf.writeln();
  buf.writeln('## 🚧 GN vs Bazel Gap Analysis (Unmigrated Suites)');
  buf.writeln();
  buf.writeln(
    'The following test suites exist in GN/Ninja/RCI (`tools/bots/test_matrix.json` & `tests/`) but are not yet scanned in Starlark:',
  );
  buf.writeln();
  final unmigrated =
      (gapAnalysis['unmigrated_gn_suites'] as List<dynamic>).cast<String>()
        ..sort();
  for (final s in unmigrated) {
    buf.writeln('* 🔴 `tests/$s`');
  }

  buf.writeln();
  buf.writeln('---');
  buf.writeln();
  buf.writeln('## 🩹 Failing Targets Punch List');
  buf.writeln();

  if (totalFailed == 0) {
    buf.writeln(
      '🎉 *Zero test failures recorded in active Starlark universe!*',
    );
  } else {
    for (final cfgName in sortedCfgNames) {
      final cfg = configs[cfgName] as Map<String, dynamic>;
      final failedList = (cfg['failed_targets'] as List<dynamic>)
          .cast<String>();
      if (failedList.isNotEmpty) {
        buf.writeln('### `$cfgName` (${failedList.length} failures)');
        buf.writeln('```text');
        for (final t in failedList) {
          buf.writeln(t);
        }
        buf.writeln('```');
        buf.writeln();
      }
    }
  }

  final outFile = File(outputPath);
  outFile.writeAsStringSync(buf.toString());
  print('✅ Generated canonical markdown completion matrix at: $outputPath');
}
