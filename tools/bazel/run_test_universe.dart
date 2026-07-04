// Copyright (c) 2026, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

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
  'runtime',
};

/// All GN/Ninja/RCI suites known on disk mapped to their tracking Bead ID.
const unmigratedGnSuites = {
  'modular': 'sdk-2w0',
  'hot_reload': 'sdk-2w0',
  'web (HTML)': 'sdk-wax',
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
  --chunk-size=<N>          Number of targets per Bazel invocation chunk (default: 400)
  --by-suite                Partition chunks strictly grouped by test suite name
  --dry-run                 Query and filter targets without executing bazel test
  --output=<path>           JSON output path (default: docs/bazel-migration/test_matrix_results.json)
  --heartbeat=<path>        Heartbeat status file (default: docs/bazel-migration/PATROL_HEARTBEAT.json)
  --bazel-arg=<arg>         Extra argument to pass to bazel test (can be repeated)
  --watchdog-interval=<s>   Recommended watchdog timer in seconds (default: 300)
  -h, --help                Show this help
''');
}

void purgeRunfilesSymlinks() {
  try {
    final binDir = Directory('bazel-out');
    if (!binDir.existsSync()) return;

    for (final entity in binDir.listSync()) {
      if (entity is Directory) {
        final testlogs = Directory('${entity.path}/testlogs');
        if (testlogs.existsSync()) {
          Process.runSync('chmod', ['-R', 'u+w', testlogs.path]);
          Process.runSync('rm', ['-rf', testlogs.path]);
        }
      }
    }

    Process.runSync('find', [
      'bazel-out',
      '-type',
      'd',
      '-name',
      '*.runfiles',
      '-prune',
      '-exec',
      'chmod',
      '-R',
      'u+w',
      '{}',
      '+',
      '-exec',
      'rm',
      '-rf',
      '{}',
      '+'
    ]);
  } catch (_) {}
}

double getFreeDiskGb(String path) {
  try {
    final res = Process.runSync('df', ['-kP', path]);
    if (res.exitCode == 0) {
      final lines = (res.stdout as String).trim().split('\n');
      if (lines.length >= 2) {
        final parts = lines[1].trim().split(RegExp(r'\s+'));
        if (parts.length >= 4) {
          final freeKb = double.tryParse(parts[3]);
          if (freeKb != null) {
            return freeKb / 1024 / 1024;
          }
        }
      }
    }
  } catch (_) {}
  return -1.0;
}

void writeHeartbeat(String path, Map<String, dynamic> data) {
  try {
    final tmpFree = getFreeDiskGb(Directory.systemTemp.path);
    final wsFree = getFreeDiskGb('.');
    data['disk_free_gb'] = {
      'tmp': tmpFree >= 0 ? tmpFree.toStringAsFixed(1) : 'unknown',
      'workspace': wsFree >= 0 ? wsFree.toStringAsFixed(1) : 'unknown',
    };
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

String determineSuite(String rawTarget) {
  var target = rawTarget;
  if (target.startsWith('@@')) {
    target = target.substring(2);
  } else if (target.startsWith('@')) {
    target = target.substring(1);
  }
  final doubleSlashIdx = target.indexOf('//');
  if (doubleSlashIdx != -1) {
    target = target.substring(doubleSlashIdx + 2);
  }
  if (target.startsWith('pkg/')) {
    return 'pkg';
  } else if (target.startsWith('web/wasm/') ||
      target.startsWith('web/wasm:') ||
      target == 'web/wasm') {
    return 'web/wasm';
  }
  final colonIdx = target.indexOf(':');
  final path = colonIdx != -1 ? target.substring(0, colonIdx) : target;
  if (path.isEmpty) {
    return 'unknown';
  }
  final slashIdx = path.indexOf('/');
  return slashIdx != -1 ? path.substring(0, slashIdx) : path;
}

void main(List<String> args) async {
  final skipSuites = <String>{};
  final onlySuites = <String>{};
  final skipConfigs = <String>{};
  final onlyConfigs = <String>{};
  final bazelStartupArgs = <String>[];
  final bazelArgs = <String>['--keep_going', '--test_output=errors'];
  var outputPath = 'docs/bazel-migration/test_matrix_results.json';
  var heartbeatPath = 'docs/bazel-migration/PATROL_HEARTBEAT.json';
  var chunkSize = 400;
  var bySuite = false;
  var dryRun = false;
  var watchdogInterval = 300;

  for (final arg in args) {
    if (arg == '-h' || arg == '--help') {
      printUsage();
      return;
    } else if (arg == '--dry-run') {
      dryRun = true;
    } else if (arg.startsWith('--chunk-size=')) {
      final val = int.tryParse(arg.substring('--chunk-size='.length));
      if (val != null && val > 0) chunkSize = val;
    } else if (arg == '--by-suite') {
      bySuite = true;
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
    } else if (arg.startsWith('--bazel-startup-arg=')) {
      bazelStartupArgs.add(arg.substring('--bazel-startup-arg='.length));
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

  print(
      '🔍 Querying Bazel for all @dart_tests//... and //runtime/... test targets...');
  final queryRes = await Process.run('bazel', [
    ...bazelStartupArgs,
    'query',
    'tests(@dart_tests//...) + tests(//runtime/...)',
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
  final sortedKnownConfigs = knownConfigs.toList()
    ..sort((a, b) => b.length.compareTo(a.length));

  for (final target in allTargets) {
    final suite = determineSuite(target);
    if (onlySuites.isNotEmpty && !onlySuites.contains(suite)) {
      continue;
    }
    if (skipSuites.contains(suite)) {
      continue;
    }

    String? matchedConfig;
    for (final c in sortedKnownConfigs) {
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
      'failed_targets': <String>{},
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
    print('\n🚀 Executing Bazel tests across universe (chunked)...');

    final targetChunks = <List<String>>[];
    if (bySuite) {
      final suiteMap = <String, List<String>>{};
      for (final t in filteredTargets) {
        final s = determineSuite(t);
        suiteMap.putIfAbsent(s, () => []).add(t);
      }
      for (final group in suiteMap.values) {
        for (var i = 0; i < group.length; i += chunkSize) {
          targetChunks.add(group.sublist(i,
              (i + chunkSize < group.length) ? i + chunkSize : group.length));
        }
      }
    } else {
      for (var i = 0; i < filteredTargets.length; i += chunkSize) {
        targetChunks.add(filteredTargets.sublist(
            i,
            (i + chunkSize < filteredTargets.length)
                ? i + chunkSize
                : filteredTargets.length));
      }
    }

    print(
        '🧩 Partitioned $totalCount targets into ${targetChunks.length} chunks (max $chunkSize targets/chunk)');

    final startTime = DateTime.now();
    var cumulativeSummaryCount = 0;

    final logFile = File('bazel_test_run.log');
    if (logFile.existsSync()) {
      logFile.deleteSync();
    }

    for (var chunkIdx = 0; chunkIdx < targetChunks.length; chunkIdx++) {
      final chunkTargets = targetChunks[chunkIdx];
      final normalizedTargets = chunkTargets.map((t) {
        if (t.startsWith('@@//')) {
          return t.substring(2);
        } else if (t.startsWith('@//')) {
          return t.substring(1);
        }
        return t;
      }).toList();

      final tempFile = File('bazel_test_targets_chunk.tmp');
      await tempFile.writeAsString(normalizedTargets.join('\n'));

      final bepFile = File('test_bep.json');
      if (bepFile.existsSync()) {
        bepFile.deleteSync();
      }

      final dt = DateTime.now().difference(startTime).inSeconds;
      final elapsedMins = dt / 60.0;
      final percent = totalCount > 0
          ? (cumulativeSummaryCount / totalCount * 100.0)
          : 100.0;

      print(
          '\n🚀 [Chunk ${chunkIdx + 1}/${targetChunks.length}] Running ${chunkTargets.length} targets | Total Progress: ${percent.toStringAsFixed(1)}% ($cumulativeSummaryCount/$totalCount targets)');

      writeHeartbeat(heartbeatPath, {
        'status': 'RUNNING',
        'timestamp': DateTime.now().toUtc().toIso8601String(),
        'completed_targets': cumulativeSummaryCount,
        'total_targets': totalCount,
        'percent': percent.toStringAsFixed(1),
        'elapsed_minutes': elapsedMins.toStringAsFixed(1),
        'current_chunk': chunkIdx + 1,
        'total_chunks': targetChunks.length,
        'test_targets_completed': cumulativeSummaryCount,
        'process_rss_mb':
            (ProcessInfo.currentRss / (1024 * 1024)).toStringAsFixed(1),
      });

      try {
        final fullArgs = [
          ...bazelStartupArgs,
          'test',
          ...bazelArgs,
          '--build_event_json_file=test_bep.json',
          '--target_pattern_file=bazel_test_targets_chunk.tmp',
        ];

        final outSink = logFile.openWrite(mode: FileMode.append);
        try {
          final testProc = await Process.start('bazel', fullArgs);
          final outDone = testProc.stdout.forEach(outSink.add);
          final errDone = testProc.stderr.forEach(outSink.add);
          await Future.wait([outDone, errDone]);
          final exitCode = await testProc.exitCode;
          if (exitCode != 0) {
            print(
                '⚠️ Bazel exited with non-zero code $exitCode for chunk ${chunkIdx + 1}');
          }
        } finally {
          await outSink.flush();
          await outSink.close();
        }

        if (bepFile.existsSync()) {
          final lines = bepFile.readAsLinesSync();
          for (final line in lines) {
            if (line.trim().isEmpty) continue;
            try {
              final evt = jsonDecode(line) as Map<String, dynamic>;
              if (evt.containsKey('testSummary')) {
                cumulativeSummaryCount++;
                final idMap = evt['id'] as Map<String, dynamic>?;
                final label = idMap?['testSummary']?['label'] as String?;
                final summary = evt['testSummary'] as Map<String, dynamic>;
                final status = summary['overallStatus'] as String?;

                if (label != null) {
                  final cfg = sortedKnownConfigs.firstWhere(
                    (c) => label.endsWith('_$c') || label.contains('_${c}_'),
                    orElse: () => 'vm_release',
                  );
                  final config = configResults[cfg];
                  if (config != null) {
                    final suite = determineSuite(label);
                    final bySuite =
                        config['by_suite'] as Map<String, Map<String, int>>;
                    final suiteData = bySuite.putIfAbsent(
                        suite, () => {'total': 0, 'passed': 0, 'failed': 0});
                    suiteData['total'] = (suiteData['total'] ?? 0) + 1;

                    if (status == 'PASSED') {
                      config['passed'] = (config['passed'] as int) + 1;
                      suiteData['passed'] = (suiteData['passed'] ?? 0) + 1;
                    } else {
                      config['failed'] = (config['failed'] as int) + 1;
                      (config['failed_targets'] as Set<String>).add(label);
                      suiteData['failed'] = (suiteData['failed'] ?? 0) + 1;
                    }
                  }
                }
              }
            } catch (_) {}
          }
          try {
            bepFile.deleteSync();
          } catch (_) {}
        }
        final chunkDt = DateTime.now().difference(startTime).inSeconds;
        final chunkElapsedMins = chunkDt / 60.0;
        final chunkPercent = totalCount > 0
            ? (cumulativeSummaryCount / totalCount * 100.0)
            : 100.0;

        writeHeartbeat(heartbeatPath, {
          'status': 'RUNNING',
          'timestamp': DateTime.now().toUtc().toIso8601String(),
          'completed_targets': cumulativeSummaryCount,
          'total_targets': totalCount,
          'percent': chunkPercent.toStringAsFixed(1),
          'elapsed_minutes': chunkElapsedMins.toStringAsFixed(1),
          'current_chunk': chunkIdx + 1,
          'total_chunks': targetChunks.length,
          'test_targets_completed': cumulativeSummaryCount,
          'process_rss_mb':
              (ProcessInfo.currentRss / (1024 * 1024)).toStringAsFixed(1),
        });

        final serializableConfigResults =
            configResults.map((key, value) => MapEntry(key, {
                  ...value,
                  'failed_targets':
                      (value['failed_targets'] as Set<String>).toList(),
                }));

        final intermediateOutput = {
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
          'config_results': serializableConfigResults,
        };
        final intermediateFile = File(outputPath);
        intermediateFile.parent.createSync(recursive: true);
        await intermediateFile.writeAsString(
            JsonEncoder.withIndent('  ').convert(intermediateOutput));
      } catch (e) {
        print('⚠️ Error executing chunk ${chunkIdx + 1}: $e');
      } finally {
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

      purgeRunfilesSymlinks();
    }

    final totalDt = DateTime.now().difference(startTime).inSeconds;
    final finalRate = totalDt > 0 ? (totalCount / totalDt) : 0.0;
    writeHeartbeat(heartbeatPath, {
      'status': 'COMPLETED',
      'timestamp': DateTime.now().toUtc().toIso8601String(),
      'completed_targets': cumulativeSummaryCount,
      'total_targets': totalCount,
      'percent': '100.0',
      'elapsed_minutes': (totalDt / 60.0).toStringAsFixed(1),
      'eta_remaining_minutes': '0.0',
      'rate_targets_per_sec': finalRate.toStringAsFixed(2),
    });
  }

  final finalConfigResults = configResults.map((key, value) => MapEntry(key, {
        ...value,
        'failed_targets': (value['failed_targets'] as Set<String>).toList(),
      }));

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
    'config_results': finalConfigResults,
  };

  final outFile = File(outputPath);
  outFile.parent.createSync(recursive: true);
  await outFile.writeAsString(JsonEncoder.withIndent('  ').convert(outputMap));
  print('✅ Exported canonical test completion results to: $outputPath');
}
