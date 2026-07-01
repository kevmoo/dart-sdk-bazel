// Copyright (c) 2026, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  final inputPath = args.isNotEmpty
      ? args[0]
      : 'docs/bazel-migration/test_matrix_results.json';
  final outputPath = args.length > 1 ? args[1] : null;

  final inFile = File(inputPath);
  if (!inFile.existsSync()) {
    print('❌ Error: Could not locate JSON source of truth at: $inputPath');
    print('Please run `dart tools/bazel/run_test_universe.dart` first.');
    exit(1);
  }

  final data =
      jsonDecode(inFile.readAsStringSync()) as Map<String, dynamic>? ?? {};
  final timestamp = data['timestamp'] as String? ?? '';
  final interval = data['watchdog_interval_seconds'] as int? ?? 300;
  final gapAnalysis =
      data['universe_gap_analysis'] as Map<String, dynamic>? ?? {};
  final configs = data['config_results'] as Map<String, dynamic>? ?? {};

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
  buf.writeln('## 🌌 Active Starlark Test Universe (By Configuration)');
  buf.writeln();
  buf.writeln('| Configuration | Status | Total Targets | Passed | Failed |');
  buf.writeln('|---|---|---|---|---|');

  final sortedCfgNames = configs.keys.toList()..sort();
  var totalUniverseTargets = 0;
  var totalPassed = 0;
  var totalFailed = 0;

  for (final cfgName in sortedCfgNames) {
    final cfg = configs[cfgName] as Map<String, dynamic>? ?? {};
    final total = cfg['total_targets'] as int? ?? 0;
    final passed = cfg['passed'] as int? ?? 0;
    final failed = cfg['failed'] as int? ?? 0;
    final status = cfg['status'] as String? ?? 'Unknown';

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
  buf.writeln('## 📦 Starlark Test Completion Matrix (Suite × Configuration)');
  buf.writeln();

  final primaryConfigs = ['vm_release', 'wasm_release', 'cfe_release'];
  buf.writeln(
    '| Suite | `vm_release` | `wasm_release` | `cfe_release` | `Other Configs` | Total Targets |',
  );
  buf.writeln('|---|---|---|---|---|---|');

  final allSuitesDiscovered = <String>{};
  for (final cfgName in sortedCfgNames) {
    final cfg = configs[cfgName] as Map<String, dynamic>? ?? {};
    final bySuite = cfg['by_suite'] as Map<String, dynamic>? ?? {};
    allSuitesDiscovered.addAll(bySuite.keys);
  }

  final sortedSuiteNames = allSuitesDiscovered.toList()..sort();
  for (final sName in sortedSuiteNames) {
    var suiteTotal = 0;
    var suitePassed = 0;
    var suiteFailed = 0;
    final rowCells = <String>[];

    var primaryTotalSum = 0;
    var primaryPassedSum = 0;
    var primaryFailedSum = 0;

    for (final cfgName in primaryConfigs) {
      final cfg = configs[cfgName] as Map<String, dynamic>? ?? {};
      final bySuite = cfg['by_suite'] as Map<String, dynamic>? ?? {};
      final sMap = bySuite[sName] as Map<String, dynamic>? ?? {};
      final total = sMap['total'] as int? ?? 0;
      final passed = sMap['passed'] as int? ?? 0;
      final failed = sMap['failed'] as int? ?? 0;

      primaryTotalSum += total;
      primaryPassedSum += passed;
      primaryFailedSum += failed;

      if (total == 0) {
        rowCells.add('❄️');
      } else if (failed > 0) {
        rowCells.add('❌ $passed / $total');
      } else {
        rowCells.add('✅ $passed / $total');
      }
    }

    for (final cfgName in sortedCfgNames) {
      final cfg = configs[cfgName] as Map<String, dynamic>? ?? {};
      final bySuite = cfg['by_suite'] as Map<String, dynamic>? ?? {};
      final sMap = bySuite[sName] as Map<String, dynamic>? ?? {};
      suiteTotal += (sMap['total'] as int? ?? 0);
      suitePassed += (sMap['passed'] as int? ?? 0);
      suiteFailed += (sMap['failed'] as int? ?? 0);
    }

    final restTotal = (suiteTotal - primaryTotalSum).clamp(0, suiteTotal);
    final restPassed = (suitePassed - primaryPassedSum).clamp(0, suitePassed);
    final restFailed = (suiteFailed - primaryFailedSum).clamp(0, suiteFailed);

    if (restTotal == 0) {
      rowCells.add('❄️');
    } else if (restFailed > 0) {
      rowCells.add('❌ $restPassed / $restTotal');
    } else {
      rowCells.add('✅ $restPassed / $restTotal');
    }

    buf.writeln('| **`$sName`** | ${rowCells.join(' | ')} | **$suiteTotal** |');
  }

  buf.writeln();
  buf.writeln('---');
  buf.writeln();
  buf.writeln('## 🚧 GN vs Bazel Gap Analysis (Unmigrated Suites)');
  buf.writeln();
  buf.writeln(
    'The following test suites exist in GN/Ninja/RCI (`tools/bots/test_matrix.json` & `tests/`) but are not yet scanned in Starlark:',
  );
  buf.writeln();
  final unmigratedMap =
      gapAnalysis['unmigrated_gn_suites'] as Map<String, dynamic>? ?? {};
  final sortedSuites = unmigratedMap.keys.toList()..sort();
  for (final s in sortedSuites) {
    final beadId = unmigratedMap[s] as String? ?? '';
    if (beadId.isNotEmpty) {
      buf.writeln(
        '* 🔴 `tests/$s` *(Tracked by [`$beadId`](./BACKLOG.md#$beadId))*',
      );
    } else {
      buf.writeln('* 🔴 `tests/$s`');
    }
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
      final cfg = configs[cfgName] as Map<String, dynamic>? ?? {};
      final failedList =
          (cfg['failed_targets'] as List<dynamic>?)?.cast<String>() ??
          <String>[];
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

  if (outputPath != null) {
    final file = File(outputPath);
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(buf.toString());
    print('✅ Generated canonical markdown completion matrix at: $outputPath');
  } else {
    stdout.write(buf.toString());
  }
}
