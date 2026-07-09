// Copyright (c) 2026, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

String getHealthBadge(int passed, int total) {
  if (total == 0) return '❄️';
  final pct = (passed / total) * 100.0;
  if (pct <= 10.0) return '⚫';
  if (pct <= 50.0) return '🔴';
  if (pct <= 80.0) return '🟠';
  if (pct < 100.0) return '🟡';
  return '🟢';
}

void main(List<String> args) {
  final inputPath = args.isNotEmpty
      ? args[0]
      : 'docs/bazel-migration/test_matrix_results.json';
  final outputPath = args.length > 1 ? args[1] : null;

  final inFile = File(inputPath);
  if (!inFile.existsSync()) {
    print('❌ Error: Could not locate JSON source of truth at: $inputPath');
    print('Please run `dart tools/bazel/testing/test_runner.dart` first.');
    exit(1);
  }

  final data =
      jsonDecode(inFile.readAsStringSync()) as Map<String, dynamic>? ?? {};
  final timestamp = data['timestamp'] as String? ?? '';
  final interval = data['watchdog_interval_seconds'] as int? ?? 300;
  final gapAnalysis =
      data['universe_gap_analysis'] as Map<String, dynamic>? ?? {};
  final configs = data['config_results'] as Map<String, dynamic>? ?? {};
  final isDryRun = (data['is_dry_run'] as bool? ?? false) ||
      configs.values
          .any((c) => (c['status'] as String? ?? '').contains('Dry Run'));

  final buf = StringBuffer();
  buf.writeln('# Dart SDK Bazel Test Completion Matrix & Gap Analysis');
  buf.writeln();
  buf.writeln('* **Generated At:** `$timestamp`');
  buf.writeln(
    '* **Source of Truth:** [`test_matrix_results.json`](./test_matrix_results.json)',
  );
  buf.writeln('* **Watchdog Watch Interval:** `${interval}s` (5 minutes)');
  buf.writeln();

  if (isDryRun) {
    buf.writeln('> [!WARNING]');
    buf.writeln(
      '> **DRY RUN MODE**: Targets were discovered but **NOT EXECUTED**. Pass `--run` to `test_runner.sh` to execute tests and collect real pass/fail results.',
    );
    buf.writeln();
  }

  buf.writeln('---');
  buf.writeln();
  buf.writeln('## 🌌 Active Starlark Test Universe (By Configuration)');
  buf.writeln();
  buf.writeln('| Configuration | Status | Total Targets | Failed |');
  buf.writeln('|---|---|---:|---:|');

  final sortedCfgNames = configs.keys.toList()..sort();
  var totalUniverseTargets = 0;
  var totalPassed = 0;
  var totalFailed = 0;

  for (final cfg in configs.values) {
    totalUniverseTargets += (cfg['total_targets'] as int? ?? 0);
    totalPassed += (cfg['passed'] as int? ?? 0);
    totalFailed += (cfg['failed'] as int? ?? 0);
  }

  final universeStatusStr = isDryRun
      ? '**🔍 Dry Run (Unexecuted)**'
      : (totalUniverseTargets == 0
          ? '**❄️ Skipped**'
          : '**${getHealthBadge(totalPassed, totalUniverseTargets)} ${(totalPassed / totalUniverseTargets * 100.0).toStringAsFixed(1)}%**');
  buf.writeln(
    '| **Universe Totals** | $universeStatusStr | **$totalUniverseTargets** | **$totalFailed** |',
  );

  for (final cfgName in sortedCfgNames) {
    final cfg = configs[cfgName] as Map<String, dynamic>? ?? {};
    final total = cfg['total_targets'] as int? ?? 0;
    final passed = cfg['passed'] as int? ?? 0;
    final failed = cfg['failed'] as int? ?? 0;
    final status = cfg['status'] as String? ?? 'Unknown';

    final statusSuffix = status == 'Active' ? '' : ' ($status)';
    final statusStr = isDryRun
        ? '🔍 Dry Run (Unexecuted)'
        : (total == 0
            ? '❄️ Skipped$statusSuffix'
            : '${getHealthBadge(passed, total)} ${(passed / total * 100.0).toStringAsFixed(1)}%$statusSuffix');
    buf.writeln(
      '| `$cfgName` | $statusStr | $total | $failed |',
    );
  }
  buf.writeln();
  buf.writeln('---');
  buf.writeln();
  buf.writeln('## 📦 Starlark Test Completion Matrix (Suite × Configuration)');
  buf.writeln();

  final primaryConfigs = ['vm_release', 'wasm_release', 'cfe_release'];
  buf.writeln(
    '| Suite | `vm_release` | `wasm_release` | `cfe_release` | `Other Configs` | Total Targets |',
  );
  buf.writeln('|---|---|---|---|---|---:|');

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
    final rowCells = <String>[];

    var primaryTotalSum = 0;
    var primaryPassedSum = 0;

    for (final cfgName in primaryConfigs) {
      final cfg = configs[cfgName] as Map<String, dynamic>? ?? {};
      final bySuite = cfg['by_suite'] as Map<String, dynamic>? ?? {};
      final sMap = bySuite[sName] as Map<String, dynamic>? ?? {};
      final total = sMap['total'] as int? ?? 0;
      final passed = sMap['passed'] as int? ?? 0;

      primaryTotalSum += total;
      primaryPassedSum += passed;

      if (total == 0) {
        rowCells.add('❄️');
      } else if (isDryRun) {
        rowCells.add('🔍 $total');
      } else {
        rowCells.add('${getHealthBadge(passed, total)} $passed / $total');
      }
    }

    for (final cfgName in sortedCfgNames) {
      final cfg = configs[cfgName] as Map<String, dynamic>? ?? {};
      final bySuite = cfg['by_suite'] as Map<String, dynamic>? ?? {};
      final sMap = bySuite[sName] as Map<String, dynamic>? ?? {};
      suiteTotal += (sMap['total'] as int? ?? 0);
      suitePassed += (sMap['passed'] as int? ?? 0);
    }

    final restTotal = (suiteTotal - primaryTotalSum).clamp(0, suiteTotal);
    final restPassed = (suitePassed - primaryPassedSum).clamp(0, suitePassed);

    if (restTotal == 0) {
      rowCells.add('❄️');
    } else if (isDryRun) {
      rowCells.add('🔍 $restTotal');
    } else {
      rowCells.add(
          '${getHealthBadge(restPassed, restTotal)} $restPassed / $restTotal');
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

  if (isDryRun) {
    buf.writeln(
      '🔍 *Dry run executed — target discovery complete. Run with `--run` to execute tests and collect failure results.*',
    );
  } else if (totalFailed == 0) {
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
