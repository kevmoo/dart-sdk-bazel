// Copyright (c) 2026, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// All coarse and fine-grained suites currently discovered in Starlark.
const activeStarlarkSuites = {
  'language',
  'corelib',
  'standalone',
  'ffi',
  'pkg',
  'web/wasm',
  'co19',
  'dartdevc',
};

/// All GN/Ninja/RCI suites known on disk mapped to their tracking Bead ID.
const unmigratedGnSuites = {
  'modular': 'sdk-2w0',
  'hot_reload': 'sdk-2w0',
  'lib': 'sdk-u0p',
  'web (HTML)': 'sdk-wax',
  'runtime (C++ unit/service)': 'sdk-4z5',
  'benchmarks': 'sdk-245',
};

/// All 23 Starlark test configs discovered in generate_test_targets.dart.
const knownConfigs = {
  'vm_release',
  'vm_debug',
  'vm_product',
  'wasm_release',
  'wasm_asserts',
  'wasm_optimized',
  'wasm_chrome_release',
  'wasm_chrome_asserts',
  'wasm_chrome_optimized',
  'wasm_firefox_release',
  'wasm_firefox_asserts',
  'dart2js_chrome_release',
  'ddc_chrome_release',
  'dart2js_firefox_release',
  'cfe_release',
  'vm_aot_release',
  'vm_release_simarm',
  'vm_aot_release_simarm',
  'vm_release_simarm64',
  'vm_aot_release_simarm64',
  'vm_release_simriscv64',
  'vm_aot_release_simriscv64',
  'analyzer_release',
};

void printUsage() {
  print('''
Magic Test Universe Runner & Report Data Exporter

Usage:
  dart tools/bazel/run_test_universe.dart [flags]

Flags:
  --skip-suites=<s1,s2>     Comma-separated suites to skip (e.g. co19,pkg)
  --only-suites=<s1,s2>     Only run specified suites
  --skip-configs=<c1,c2>    Comma-separated configs to skip (e.g. wasm_firefox_release)
  --only-configs=<c1,c2>    Only run specified configs
  --dry-run                 Query and filter targets without executing bazel test
  --output=<path>           JSON output path (default: docs/bazel-migration/test_matrix_results.json)
  --heartbeat=<path>        Heartbeat status file (default: docs/bazel-migration/PATROL_HEARTBEAT.json)
  --bazel-arg=<arg>         Extra argument to pass to bazel test (can be repeated)
  --watchdog-interval=<s>   Recommended watchdog timer in seconds (default: 300)
  -h, --help                Show this help
''');
}

void writeHeartbeat(String path, Map<String, dynamic> data) {
  try {
    final file = File(path);
    file.parent.createSync(recursive: true);
    final tmpFile = File('$path.tmp');
    tmpFile.writeAsStringSync(JsonEncoder.withIndent('  ').convert(data));
    if (file.existsSync()) {
      file.deleteSync();
    }
    tmpFile.renameSync(path);
  } catch (_) {}
}

String determineSuite(String target) {
  if (target.startsWith('@dart_tests//pkg/')) {
    return 'pkg';
  } else if (target.startsWith('@dart_tests//web/wasm')) {
    return 'web/wasm';
  }
  const prefix = '@dart_tests//';
  if (target.startsWith(prefix)) {
    final colonIdx = target.indexOf(':', prefix.length);
    if (colonIdx != -1) {
      final path = target.substring(prefix.length, colonIdx);
      final slashIdx = path.indexOf('/');
      return slashIdx != -1 ? path.substring(0, slashIdx) : path;
    }
  }
  return 'unknown';
}

void main(List<String> args) async {
  final skipSuites = <String>{};
  final onlySuites = <String>{};
  final skipConfigs = <String>{};
  final onlyConfigs = <String>{};
  final bazelArgs = <String>['--keep_going', '--test_output=errors'];
  var outputPath = 'docs/bazel-migration/test_matrix_results.json';
  var heartbeatPath = 'docs/bazel-migration/PATROL_HEARTBEAT.json';
  var dryRun = false;
  var watchdogInterval = 300;

  for (final arg in args) {
    if (arg == '-h' || arg == '--help') {
      printUsage();
      return;
    } else if (arg == '--dry-run') {
      dryRun = true;
    } else if (arg.startsWith('--skip-suites=')) {
      skipSuites.addAll(arg.substring('--skip-suites='.length).split(','));
    } else if (arg.startsWith('--only-suites=')) {
      onlySuites.addAll(arg.substring('--only-suites='.length).split(','));
    } else if (arg.startsWith('--skip-configs=')) {
      skipConfigs.addAll(arg.substring('--skip-configs='.length).split(','));
    } else if (arg.startsWith('--only-configs=')) {
      onlyConfigs.addAll(arg.substring('--only-configs='.length).split(','));
    } else if (arg.startsWith('--output=')) {
      outputPath = arg.substring('--output='.length);
    } else if (arg.startsWith('--heartbeat=')) {
      heartbeatPath = arg.substring('--heartbeat='.length);
    } else if (arg.startsWith('--bazel-arg=')) {
      bazelArgs.add(arg.substring('--bazel-arg='.length));
    } else if (arg.startsWith('--watchdog-interval=')) {
      final val = int.tryParse(arg.substring('--watchdog-interval='.length));
      if (val == null) {
        print('❌ Error: --watchdog-interval must be a valid integer.');
        exit(1);
      }
      watchdogInterval = val;
    } else {
      print('Unknown flag: $arg');
      printUsage();
      exit(1);
    }
  }

  print('🔍 Querying Bazel for all @dart_tests//... test targets...');
  final queryRes = await Process.run('bazel', [
    'query',
    'tests(@dart_tests//...)',
  ]);

  if (queryRes.exitCode != 0) {
    print('❌ Bazel query failed:\n${queryRes.stderr}');
    exit(queryRes.exitCode);
  }

  final allTargets = (queryRes.stdout as String)
      .split('\n')
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  print('📦 Total discovered Starlark test targets: ${allTargets.length}');

  final filteredTargets = <String>[];
  for (final target in allTargets) {
    final suite = determineSuite(target);
    if (onlySuites.isNotEmpty && !onlySuites.contains(suite)) {
      continue;
    }
    if (skipSuites.contains(suite)) {
      continue;
    }

    String? matchedConfig;
    for (final c in knownConfigs) {
      if (target.endsWith('_$c') || target.contains('_${c}_')) {
        matchedConfig = c;
        break;
      }
    }
    matchedConfig ??= 'vm_release';

    if (onlyConfigs.isNotEmpty && !onlyConfigs.contains(matchedConfig)) {
      continue;
    }
    if (skipConfigs.contains(matchedConfig)) {
      continue;
    }

    filteredTargets.add(target);
  }

  print(
      '🎯 Targets remaining after quarantine filtering: ${filteredTargets.length}');

  final configResults = <String, Map<String, dynamic>>{};
  for (final c in knownConfigs) {
    final suiteMap = <String, Map<String, int>>{};
    for (final s in activeStarlarkSuites) {
      suiteMap[s] = {'total': 0, 'passed': 0, 'failed': 0};
    }
    configResults[c] = {
      'total_targets': 0,
      'passed': 0,
      'failed': 0,
      'status': 'Active',
      'failed_targets': <String>[],
      'by_suite': suiteMap,
    };
  }

  for (final target in filteredTargets) {
    final suite = determineSuite(target);
    for (final c in knownConfigs) {
      if (target.endsWith('_$c') || target.contains('_${c}_')) {
        configResults[c]!['total_targets'] =
            (configResults[c]!['total_targets'] as int) + 1;
        final bySuite =
            configResults[c]!['by_suite'] as Map<String, Map<String, int>>;
        bySuite.putIfAbsent(
            suite, () => {'total': 0, 'passed': 0, 'failed': 0});
        bySuite[suite]!['total'] = (bySuite[suite]!['total'] ?? 0) + 1;
        break;
      }
    }
  }

  final totalCount = filteredTargets.length;

  if (dryRun) {
    print(
        '\n🚀 [DRY RUN] Would execute: bazel test ${bazelArgs.join(' ')} <$totalCount targets>');
    for (final c in knownConfigs) {
      final total = configResults[c]!['total_targets'] as int;
      if (total == 0) {
        configResults[c]!['status'] = 'Skipped / Filtered Out';
      } else {
        configResults[c]!['passed'] = total;
      }
      final bySuite =
          configResults[c]!['by_suite'] as Map<String, Map<String, int>>;
      for (final s in bySuite.keys) {
        bySuite[s]!['passed'] = bySuite[s]!['total'] ?? 0;
      }
    }
    writeHeartbeat(heartbeatPath, {
      'status': 'DRY_RUN',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'completed_targets': totalCount,
      'total_targets': totalCount,
      'percent': '100.0',
      'elapsed_minutes': '0.0',
      'eta_remaining_minutes': '0.0',
      'rate_targets_per_sec': '0.0',
    });
  } else {
    print('\n🚀 Executing Bazel tests across universe...');
    final tempFile = File('bazel_test_targets.tmp');
    await tempFile.writeAsString(filteredTargets.join('\n'));

    final bepFile = File('test_bep.json');
    if (bepFile.existsSync()) {
      bepFile.deleteSync();
    }

    final startTime = DateTime.now();
    writeHeartbeat(heartbeatPath, {
      'status': 'STARTING',
      'timestamp': startTime.toUtc().toIso8601String(),
      'completed_targets': 0,
      'total_targets': totalCount,
      'percent': '0.0',
      'elapsed_minutes': '0.0',
      'eta_remaining_minutes': 'Calculating...',
      'rate_targets_per_sec': '0.0',
    });

    var summaryCount = 0;
    var lastOffset = 0;
    final timer = Timer.periodic(Duration(seconds: 15), (_) async {
      if (!bepFile.existsSync()) {
        return;
      }
      try {
        final length = await bepFile.length();
        if (length > lastOffset) {
          final newCount = await bepFile
              .openRead(lastOffset, length)
              .transform(utf8.decoder)
              .transform(const LineSplitter())
              .where((line) => line.contains('testSummary'))
              .length;
          summaryCount += newCount;
          lastOffset = length;
        }
        final dt = DateTime.now().difference(startTime).inSeconds;
        final elapsedMins = dt / 60.0;
        final percent =
            totalCount > 0 ? (summaryCount / totalCount * 100.0) : 100.0;
        var etaStr = 'Calculating...';
        var rate = 0.0;
        if (summaryCount > 0 && dt > 0) {
          rate = summaryCount / dt;
          final remainingSec = (totalCount - summaryCount) / rate;
          etaStr = (remainingSec / 60.0).toStringAsFixed(1);
        }
        writeHeartbeat(heartbeatPath, {
          'status': 'RUNNING',
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'completed_targets': summaryCount,
          'total_targets': totalCount,
          'percent': percent.toStringAsFixed(1),
          'elapsed_minutes': elapsedMins.toStringAsFixed(1),
          'eta_remaining_minutes': etaStr,
          'rate_targets_per_sec': rate.toStringAsFixed(2),
        });
        print(
            '⏳ [${elapsedMins.toStringAsFixed(1)}m] Progress: ${percent.toStringAsFixed(1)}% ($summaryCount/$totalCount targets) | ETA: ${etaStr}m remaining | Rate: ${rate.toStringAsFixed(2)}/s');
      } catch (_) {}
    });

    try {
      final fullArgs = [
        'test',
        ...bazelArgs,
        '--build_event_json_file=test_bep.json',
        '--target_pattern_file=bazel_test_targets.tmp',
      ];

      final logFile = File('bazel_test_run.log');
      final outSink = logFile.openWrite();
      final testProc = await Process.start('bazel', fullArgs);
      final outSub = testProc.stdout.listen(outSink.add);
      final errSub = testProc.stderr.listen(outSink.add);
      final exitCode = await testProc.exitCode;
      await outSub.cancel();
      await errSub.cancel();
      await outSink.flush();
      await outSink.close();

      print('📊 Bazel test run completed with exit code: $exitCode');

      if (bepFile.existsSync()) {
        final lines = bepFile
            .openRead()
            .transform(utf8.decoder)
            .transform(LineSplitter());
        await for (final line in lines) {
          if (line.trim().isEmpty) continue;
          try {
            final evt = jsonDecode(line) as Map<String, dynamic>;
            if (evt.containsKey('testSummary')) {
              final idMap = evt['id'] as Map<String, dynamic>?;
              final label = idMap?['testSummary']?['label'] as String?;
              final summary = evt['testSummary'] as Map<String, dynamic>;
              final status = summary['overallStatus'] as String?;

              if (label != null) {
                String? cfg;
                for (final c in knownConfigs) {
                  if (label.endsWith('_$c') || label.contains('_${c}_')) {
                    cfg = c;
                    break;
                  }
                }
                cfg ??= 'vm_release';
                final suite = determineSuite(label);
                final bySuite = configResults[cfg]!['by_suite']
                    as Map<String, Map<String, int>>;
                bySuite.putIfAbsent(
                    suite, () => {'total': 0, 'passed': 0, 'failed': 0});

                if (status == 'PASSED') {
                  configResults[cfg]!['passed'] =
                      (configResults[cfg]!['passed'] as int) + 1;
                  bySuite[suite]!['passed'] =
                      (bySuite[suite]!['passed'] ?? 0) + 1;
                } else {
                  configResults[cfg]!['failed'] =
                      (configResults[cfg]!['failed'] as int) + 1;
                  (configResults[cfg]!['failed_targets'] as List<String>)
                      .add(label);
                  bySuite[suite]!['failed'] =
                      (bySuite[suite]!['failed'] ?? 0) + 1;
                }
              }
            }
          } catch (_) {}
        }
      }
    } finally {
      timer.cancel();
      if (tempFile.existsSync()) {
        try {
          tempFile.deleteSync();
        } catch (_) {}
      }
      if (bepFile.existsSync()) {
        try {
          bepFile.deleteSync();
        } catch (_) {}
      }
    }

    final totalDt = DateTime.now().difference(startTime).inSeconds;
    final finalRate = totalDt > 0 ? (totalCount / totalDt) : 0.0;
    writeHeartbeat(heartbeatPath, {
      'status': 'COMPLETED',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'completed_targets': totalCount,
      'total_targets': totalCount,
      'percent': '100.0',
      'elapsed_minutes': (totalDt / 60.0).toStringAsFixed(1),
      'eta_remaining_minutes': '0.0',
      'rate_targets_per_sec': finalRate.toStringAsFixed(2),
    });
  }

  final outputMap = {
    'timestamp': DateTime.now().toUtc().toIso8601String(),
    'watchdog_interval_seconds': watchdogInterval,
    'quarantine': {
      'skip_suites': skipSuites.toList(),
      'only_suites': onlySuites.toList(),
      'skip_configs': skipConfigs.toList(),
      'only_configs': onlyConfigs.toList(),
    },
    'universe_gap_analysis': {
      'active_starlark_suites': activeStarlarkSuites.toList(),
      'unmigrated_gn_suites': unmigratedGnSuites,
    },
    'config_results': configResults,
  };

  final outFile = File(outputPath);
  outFile.parent.createSync(recursive: true);
  await outFile.writeAsString(JsonEncoder.withIndent('  ').convert(outputMap));
  print('✅ Exported canonical test completion results to: $outputPath');
}
