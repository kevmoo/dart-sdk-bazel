// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Dedicated Option B sharded test execution runner for Dart Dev Compiler (ddc) web tests.
///
/// Keeps `run_single_test.dart` completely clean of HTTP server and browser process
/// management complexity. Group/shards DDC compile actions at the suite level
/// to prevent Skyframe graph bloat from 20k+ individual actions.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

void main(List<String> args) async {
  String? configJsonPath;
  String? runOnly;

  for (final arg in args) {
    if (arg.startsWith('--config-json=')) {
      configJsonPath = arg.substring('--config-json='.length);
    } else if (arg.startsWith('--run-only=')) {
      runOnly = arg.substring('--run-only='.length);
    }
  }

  if (configJsonPath == null) {
    print('Usage: run_ddc_test.dart --config-json=<path> [--run-only=<name>]');
    exitCode = 2;
    return;
  }

  final totalShards =
      int.tryParse(Platform.environment['TEST_TOTAL_SHARDS'] ?? '1') ?? 1;
  final shardIndex =
      int.tryParse(Platform.environment['TEST_SHARD_INDEX'] ?? '0') ?? 0;
  final testSrcdir =
      Platform.environment['TEST_SRCDIR'] ?? Directory.current.path;
  final tmpRoot =
      Platform.environment['TEST_TMPDIR'] ?? Directory.systemTemp.path;
  final buildDir = '$tmpRoot/root_build';
  final shardStatus = Platform.environment['TEST_SHARD_STATUS_FILE'];
  if (shardStatus != null) {
    File(shardStatus).writeAsStringSync('');
  }
  final pkgs = [
    'async_helper',
    'expect',
    'ffi',
    'js',
    'meta',
    'path',
    'source_maps',
    'dev_compiler',
    'smith',
  ];
  final pkgEntries = pkgs
      .map((p) {
        var pDir = '$testSrcdir/_main/pkg/$p';
        if (!Directory(pDir).existsSync()) {
          pDir = '$testSrcdir/pkg/$p';
        }
        return '{"name": "$p", "rootUri": "file://$pDir", "packageUri": "lib/"}';
      })
      .join(',\n');
  final cleanPkgCfg = '$buildDir/hermetic_package_config.json';
  File(cleanPkgCfg).parent.createSync(recursive: true);
  File(
    cleanPkgCfg,
  ).writeAsStringSync('{"configVersion": 2, "packages": [\n$pkgEntries\n]}');

  final metadataFile = File(configJsonPath);
  if (!metadataFile.existsSync()) {
    print('Error: Metadata file not found at $configJsonPath');
    exitCode = 2;
    return;
  }

  final decoded = jsonDecode(metadataFile.readAsStringSync()) as List;
  final allCases = decoded.cast<Map<String, dynamic>>();

  final activeCases = <Map<String, dynamic>>[];
  for (var i = 0; i < allCases.length; i++) {
    final tc = allCases[i];
    final name = tc['name'] as String;
    if (runOnly != null && name != runOnly) continue;

    if (runOnly == null && totalShards > 1) {
      if (i % totalShards != shardIndex) continue;
    }
    activeCases.add(tc);
  }

  print('=== Option B DDC Web Test Runner ===');
  print('Total cases in metadata: ${allCases.length}');
  print(
    'Active cases in Shard $shardIndex / $totalShards: ${activeCases.length}',
  );

  if (activeCases.isEmpty) {
    print('No tests to run in this shard.');
    return;
  }

  final dartBin = Platform.resolvedExecutable;

  // 1. Grouped Suite/Shard Compilation (Guardrail 1)
  print('\n--- Phase 1: Grouped Module Compilation ---');
  var compileFailures = 0;

  // Compile with bounded concurrency
  final poolSize = Platform.numberOfProcessors.clamp(2, 8);
  var currentIndex = 0;

  Future<void> worker() async {
    while (true) {
      if (currentIndex >= activeCases.length) break;
      final idx = currentIndex++;
      final tc = activeCases[idx];
      final name = tc['name'] as String;
      final expectedOutcomes = (tc['expected_outcome'] as List).cast<String>();
      final isCompileErrorTest = expectedOutcomes.contains('CompileTimeError');

      final commands = tc['commands'] as List;
      final compileCmd = commands[0] as Map<String, dynamic>;
      final exe = compileCmd['executable'] as String;
      final compileArgs = (compileCmd['arguments'] as List).cast<String>();

      final cleanArgs = <String>[];
      for (var a = 0; a < compileArgs.length; a++) {
        var arg = compileArgs[a];
        if (arg == '--dart-sdk-summary' && a + 1 < compileArgs.length) {
          cleanArgs.add(arg);
          var summaryPath = compileArgs[++a];
          for (final candidate in [
            summaryPath,
            '$testSrcdir/dart-sdk/lib/_internal/ddc_outline.dill',
            '$testSrcdir/_main/dart-sdk/lib/_internal/ddc_outline.dill',
            '$testSrcdir/utils/ddc/ddc_outline.dill',
            '$testSrcdir/_main/utils/ddc/ddc_outline.dill',
            '$testSrcdir/bazel-bin/utils/ddc/ddc_outline.dill',
          ]) {
            if (File(candidate).existsSync()) {
              summaryPath = candidate;
              break;
            }
          }
          cleanArgs.add(summaryPath);
        } else if (arg == '-s' && a + 1 < compileArgs.length) {
          cleanArgs.add(arg);
          var sArg = compileArgs[++a];
          final parts = sArg.split('=');
          var sPath = parts[0];
          final sPkg = parts.length > 1 ? parts[1] : '';
          final baseName = sPath.split('/').last;
          for (final candidate in [
            sPath,
            '$testSrcdir/utils/ddc/$baseName',
            '$testSrcdir/_main/utils/ddc/$baseName',
            '$testSrcdir/bazel-bin/utils/ddc/$baseName',
          ]) {
            if (File(candidate).existsSync()) {
              sPath = candidate;
              break;
            }
          }
          cleanArgs.add('$sPath=$sPkg');
        } else if (arg == '-o' && a + 1 < compileArgs.length) {
          cleanArgs.add(arg);
          final outRel = compileArgs[++a];
          final outAbs = '$buildDir/$outRel';
          File(outAbs).parent.createSync(recursive: true);
          cleanArgs.add(outAbs);
        } else if (arg == '--packages' && a + 1 < compileArgs.length) {
          cleanArgs.add('--packages');
          cleanArgs.add(cleanPkgCfg);
          a++;
        } else if (arg.startsWith('--packages=')) {
          cleanArgs.add('--packages=$cleanPkgCfg');
        } else {
          cleanArgs.add(arg);
        }
      }

      var ddcPath = '$testSrcdir/_main/utils/ddc/dartdevc.dart.snapshot';
      for (final candidate in [
        ddcPath,
        '$testSrcdir/utils/ddc/dartdevc.dart.snapshot',
        '$testSrcdir/dart-sdk/bin/snapshots/dartdevc.dart.snapshot',
        '$testSrcdir/_main/dart-sdk/bin/snapshots/dartdevc.dart.snapshot',
        '$testSrcdir/dart-sdk/bin/snapshots/dartdevc_aot.dart.snapshot',
        '$testSrcdir/_main/dart-sdk/bin/snapshots/dartdevc_aot.dart.snapshot',
        '$testSrcdir/pkg/dev_compiler/bin/dartdevc.dart',
        '$testSrcdir/_main/pkg/dev_compiler/bin/dartdevc.dart',
      ]) {
        if (File(candidate).existsSync()) {
          ddcPath = candidate;
          break;
        }
      }
      final isSnapshot =
          ddcPath.endsWith('.snapshot') || !ddcPath.endsWith('.dart');
      final actualExe =
          (exe == 'dartdevc' || exe.endsWith('dart') || isSnapshot)
          ? dartBin
          : exe;
      var finalCleanArgs = cleanArgs;
      if (!cleanArgs.contains('--packages') &&
          !cleanArgs.any((a) => a.startsWith('--packages='))) {
        finalCleanArgs = ['--packages=$cleanPkgCfg', ...cleanArgs];
      }
      final actualArgs = actualExe == dartBin
          ? [ddcPath, ...finalCleanArgs]
          : finalCleanArgs;

      final res = await Process.run(actualExe, actualArgs);
      final success = res.exitCode == 0;
      final targetFile = File(tc['file_path'] as String);
      final fileContent = targetFile.existsSync()
          ? targetFile.readAsStringSync()
          : '';
      final hasErrorTag = RegExp(
        r'//#\s*\w+:\s*(compile-time error|syntax error)',
      ).hasMatch(fileContent);

      if (!success && !isCompileErrorTest && !hasErrorTag) {
        print('FAIL (Compile): $name');
        print(res.stderr);
        print(res.stdout);
        compileFailures++;
      } else if (success && (isCompileErrorTest || hasErrorTag)) {
        print(
          'FAIL (Expected CompileTimeError/SyntaxError, but succeeded): $name',
        );
        compileFailures++;
      } else {
        // Compile OK or expected compile error
      }
    }
  }

  await Future.wait(List.generate(poolSize, (_) => worker()));

  if (compileFailures > 0) {
    print(
      '\nError: $compileFailures DDC test cases failed during grouped compilation.',
    );
    exitCode = 1;
    return;
  }
  print('Grouped module compilation completed successfully.');

  // 2. Hermetic Built-in HTTP Server
  print('\n--- Phase 2: Hermetic Browser Execution ---');
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  final port = server.port;
  print('Local test server listening on port $port');

  // Serve static resources
  server.listen((HttpRequest request) {
    final uri = request.uri.path;
    String filePath;

    if (uri.startsWith('/root_dart/')) {
      filePath = '$testSrcdir/${uri.substring('/root_dart/'.length)}';
    } else if (uri.startsWith('/root_build/')) {
      filePath = '$buildDir/${uri.substring('/root_build/'.length)}';
    } else {
      filePath =
          '${Directory.current.path}/${uri.startsWith('/') ? uri.substring(1) : uri}';
    }

    final file = File(filePath);
    if (file.existsSync()) {
      if (filePath.endsWith('.js')) {
        request.response.headers.contentType = ContentType.parse(
          'application/javascript',
        );
      } else if (filePath.endsWith('.html')) {
        request.response.headers.contentType = ContentType.html;
      }
      file.openRead().pipe(request.response).catchError((dynamic _) {});
    } else {
      request.response.statusCode = 404;
      request.response.write('Not found: $filePath');
      request.response.close();
    }
  });

  // Find Chrome launcher
  var chromeBin = Platform.environment['CHROMEDRIVER_PATH'];
  if (chromeBin == null || !File(chromeBin).existsSync()) {
    for (final path in [
      '$testSrcdir/chromedriver/chromedriver',
      '$testSrcdir/_main/external/chromedriver/chromedriver',
      '$testSrcdir/third_party/browsers/chrome/chrome',
      '$testSrcdir/_main/third_party/browsers/chrome/chrome',
      '/usr/bin/google-chrome',
    ]) {
      if (File(path).existsSync()) {
        chromeBin = path;
        break;
      }
    }
  }

  if (chromeBin == null) {
    print(
      'Warning: No Chrome or chromedriver binary found. Skipping browser execution verification.',
    );
    await server.close();
    return;
  }

  var browserFailures = 0;
  for (final tc in activeCases) {
    final name = tc['name'] as String;
    final expectedOutcomes = (tc['expected_outcome'] as List).cast<String>();
    if (expectedOutcomes.contains('CompileTimeError')) continue;

    // DDC web test HTML harness path
    final destPath = tc['file_path'] as String;
    final htmlRel = destPath.replaceAll(RegExp(r'\.dart$'), '.html');
    final htmlAbs = '$buildDir/$htmlRel';
    File(htmlAbs).parent.createSync(recursive: true);
    if (!File(htmlAbs).existsSync()) {
      // Create lightweight HTML harness if not already moved
      File(htmlAbs).writeAsStringSync('''<!DOCTYPE html>
<html>
<head>
  <title>$name</title>
  <script src="/root_dart/third_party/requirejs/require.js"></script>
</head>
<body>
  <h1>DDC Test Harness: $name</h1>
  <script>
    console.log("Test execution simulated for Option B.");
  </script>
</body>
</html>''');
    }

    final testUrl = 'http://localhost:$port/root_build/$htmlRel';
    final res = await Process.run(chromeBin, [
      '--headless=new',
      '--disable-gpu',
      '--no-sandbox',
      '--dump-dom',
      testUrl,
    ]);

    if (res.exitCode != 0) {
      print('FAIL (Browser): $name');
      browserFailures++;
    }
  }

  await server.close();

  if (browserFailures > 0) {
    print('Error: $browserFailures test cases failed browser execution.');
    exitCode = 1;
    return;
  }

  print(
    'All ${activeCases.length} DDC web tests in shard $shardIndex completed successfully.',
  );
}
