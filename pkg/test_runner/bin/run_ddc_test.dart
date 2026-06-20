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

String toPosix(String path) => path.replaceAll('\\', '/');

String toJsPath(String path) {
  final posix = toPosix(path);
  if (posix.endsWith('.dart')) {
    return '${posix.substring(0, posix.length - 5)}.js';
  }
  return posix.endsWith('.js') ? posix : '$posix.js';
}

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

  var totalShards =
      int.tryParse(Platform.environment['TEST_TOTAL_SHARDS'] ?? '1') ?? 1;
  var shardIndex =
      int.tryParse(Platform.environment['TEST_SHARD_INDEX'] ?? '0') ?? 0;
  if (totalShards < 1) totalShards = 1;
  if (shardIndex < 0 || shardIndex >= totalShards) {
    shardIndex = 0;
  }
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
  final packages = pkgs.map((p) {
    var pDir = '$testSrcdir/_main/pkg/$p';
    if (!Directory(pDir).existsSync()) {
      pDir = '$testSrcdir/pkg/$p';
    }
    return {
      'name': p,
      'rootUri': Uri.directory(pDir).toString(),
      'packageUri': 'lib/',
    };
  }).toList();
  final cleanPkgCfg = '$buildDir/hermetic_package_config.json';
  await File(cleanPkgCfg).parent.create(recursive: true);
  await File(
    cleanPkgCfg,
  ).writeAsString(jsonEncode({'configVersion': 2, 'packages': packages}));

  final metadataFile = File(configJsonPath);
  if (!await metadataFile.exists()) {
    print('Error: Metadata file not found at $configJsonPath');
    exitCode = 2;
    return;
  }

  final decoded = jsonDecode(await metadataFile.readAsString()) as List;
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

  var ddcPath = '$testSrcdir/_main/utils/ddc/dartdevc.dart.snapshot';
  var ddcFound = false;
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
    if (await File(candidate).exists()) {
      ddcPath = candidate;
      ddcFound = true;
      break;
    }
  }
  if (!ddcFound) {
    print('Error: Could not find dartdevc snapshot or source file.');
    exitCode = 2;
    return;
  }

  Future<void> worker() async {
    while (true) {
      if (currentIndex >= activeCases.length) break;
      final idx = currentIndex++;
      final tc = activeCases[idx];
      final name = tc['name'] as String;
      final expectedOutcomes = (tc['expected_outcome'] as List).cast<String>();
      final isCompileErrorTest = expectedOutcomes.contains('CompileTimeError');

      final commands = tc['commands'] as List;
      if (commands.isEmpty) {
        print('FAIL (Compile): $name - No commands found in metadata.');
        compileFailures++;
        continue;
      }
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
          final relPath = tc['relative_file_path'] as String? ?? outRel;
          final normRel = toJsPath(relPath);
          final outAbs = '$buildDir/$normRel';
          await File(outAbs).parent.create(recursive: true);
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

      final isDdc =
          exe == 'dartdevc' || exe.endsWith('dartdevc') || exe.endsWith('dart');
      final actualExe = isDdc ? dartBin : exe;
      var finalCleanArgs = cleanArgs;
      if (!cleanArgs.contains('--packages') &&
          !cleanArgs.any((a) => a.startsWith('--packages='))) {
        finalCleanArgs = ['--packages=$cleanPkgCfg', ...cleanArgs];
      }
      final actualArgs = isDdc ? [ddcPath, ...finalCleanArgs] : finalCleanArgs;

      final res = await Process.run(actualExe, actualArgs);
      final success = res.exitCode == 0;
      var targetFile = File(tc['file_path'] as String);
      if (!await targetFile.exists()) {
        targetFile = File('$testSrcdir/_main/${tc['file_path']}');
      }
      if (!await targetFile.exists()) {
        targetFile = File('$testSrcdir/${tc['file_path']}');
      }
      final fileContent = await targetFile.exists()
          ? await targetFile.readAsString()
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

  final reportedResults = <String, String>{};
  final completer = Completer<void>();

  // Serve static resources and reporting callbacks
  server.listen((HttpRequest request) async {
    final uri = request.uri.path;
    if (uri.contains('..') || uri.contains('%2e') || uri.contains('%2E')) {
      request.response.statusCode = 400;
      request.response.write('Bad Request: Path traversal not allowed');
      try {
        await request.response.close();
      } catch (_) {}
      return;
    }

    if (uri == '/report_result') {
      final query = request.uri.queryParameters;
      final testName = query['test'] ?? 'unknown';
      final status = query['status'] ?? 'FAIL';
      final err = query['err'];
      reportedResults[testName] = status;
      if (status != 'PASS') {
        print('FAIL (Runtime): $testName ${err != null ? "- $err" : ""}');
      }
      request.response.statusCode = 200;
      request.response.write('OK');
      try {
        await request.response.close();
      } catch (_) {}
      return;
    } else if (uri == '/shard_complete') {
      request.response.statusCode = 200;
      request.response.write('DONE');
      try {
        await request.response.close();
      } catch (_) {}
      if (!completer.isCompleted) completer.complete();
      return;
    }

    String filePath;

    if (uri.startsWith('/root_dart/')) {
      filePath = '$testSrcdir/${uri.substring('/root_dart/'.length)}';
    } else if (uri.startsWith('/root_build/')) {
      filePath = '$buildDir/${uri.substring('/root_build/'.length)}';
    } else {
      filePath =
          '${Directory.current.path}/${uri.startsWith("/") ? uri.substring(1) : uri}';
    }

    var file = File(filePath);
    if (!await file.exists() && uri.startsWith('/root_dart/')) {
      file = File('$testSrcdir/_main/${uri.substring("/root_dart/".length)}');
      if (await file.exists()) filePath = file.path;
    }
    if (await file.exists()) {
      if (uri.endsWith('.js') || filePath.endsWith('.js')) {
        request.response.headers.contentType = ContentType(
          'application',
          'javascript',
          charset: 'utf-8',
        );
      } else if (uri.endsWith('.html') || filePath.endsWith('.html')) {
        request.response.headers.contentType = ContentType.html;
      }
      try {
        final bytes = await file.readAsBytes();
        request.response.contentLength = bytes.length;
        request.response.add(bytes);
        await request.response.close();
      } catch (_) {
        try {
          await request.response.close();
        } catch (_) {}
      }
    } else {
      request.response.statusCode = 404;
      request.response.write('Not found: $filePath');
      try {
        await request.response.close();
      } catch (_) {}
    }
  });

  // Find Chrome launcher
  var chromeBin =
      Platform.environment['CHROME_PATH'] ?? Platform.environment['CHROME_BIN'];
  if (chromeBin == null || !await File(chromeBin).exists()) {
    for (final path in [
      '$testSrcdir/third_party/browsers/chrome/chrome',
      '$testSrcdir/_main/third_party/browsers/chrome/chrome',
      '/usr/bin/google-chrome',
    ]) {
      if (await File(path).exists()) {
        chromeBin = path;
        break;
      }
    }
  }

  if (chromeBin == null) {
    print(
      'Warning: No Chrome browser binary found. Skipping browser execution verification.',
    );
    await server.close();
    return;
  }

  final validTestCases = <Map<String, dynamic>>[];
  for (final tc in activeCases) {
    final expectedOutcomes = (tc['expected_outcome'] as List).cast<String>();
    if (expectedOutcomes.contains('CompileTimeError')) continue;
    final relPath = tc['relative_file_path'] as String? ?? tc['name'] as String;
    final normRel = toJsPath(relPath);
    if (await File('$buildDir/$normRel').exists()) {
      validTestCases.add(tc);
    }
  }

  if (validTestCases.isEmpty) {
    print('No runtime browser tests to execute in this shard.');
    await server.close();
    return;
  }

  final testModEntries = validTestCases
      .map((tc) {
        final relPath =
            tc['relative_file_path'] as String? ?? tc['name'] as String;
        final modName = toPosix(relPath.replaceAll('.dart', ''));
        final name = tc['name'] as String;
        return jsonEncode({'name': name, 'module': modName});
      })
      .join(',\n');

  final shardHtml = '$buildDir/shard_runner.html';
  await File(shardHtml).parent.create(recursive: true);
  await File(shardHtml).writeAsString('''<!DOCTYPE html>
<html>
<head>
  <title>DDC Batch Execution Engine</title>
  <script>
    function safeEncode(str) {
      try {
        return encodeURIComponent(str);
      } catch (_) {
        var s = "";
        var sStr = "" + str;
        for (var i = 0; i < sStr.length; i++) {
          var c = sStr.charCodeAt(i);
          if (c >= 0xD800 && c <= 0xDFFF) s += "_";
          else s += sStr.charAt(i);
        }
        return encodeURIComponent(s);
      }
    }
    window.onerror = function(msg, url, line) {
      fetch("/report_result?test=WINDOW_ONERROR&status=FAIL&err=" + safeEncode(msg + " at " + url + ":" + line));
    };
    var require = {
      baseUrl: "/root_build",
      paths: {
        "dart_sdk": "/root_dart/utils/ddc/stable/sdk/amd/dart_sdk",
        "expect": "/root_dart/utils/ddc/stable/pkg/amd/expect",
        "js": "/root_dart/utils/ddc/stable/pkg/amd/js",
        "meta": "/root_dart/utils/ddc/stable/pkg/amd/meta"
      },
      waitSeconds: 30
    };
    var testCases = [
$testModEntries
    ];
    var currentIndex = 0;

    function reportResult(testName, status, err) {
      var url = "/report_result?test=" + safeEncode(testName) + "&status=" + status;
      if (err) url += "&err=" + safeEncode("" + err);
      return fetch(url);
    }

    function runNextTest() {
      if (currentIndex >= testCases.length) {
        fetch("/shard_complete");
        return;
      }
      var tc = testCases[currentIndex++];
      var modName = tc.module;
      var testName = tc.name;

      require([modName, "dart_sdk"], function(mod, sdk) {
        try {
          var modKeys = Object.keys(mod);
          var modKey = modKeys[0];
          mod[modKey].main();
          reportResult(testName, "PASS", null).then(runNextTest);
        } catch (e) {
          reportResult(testName, "FAIL", "" + e).then(runNextTest);
        }
      }, function(err) {
        reportResult(testName, "FAIL", "RequireJS Load Error: " + err).then(runNextTest);
      });
    }
  </script>
  <script src="/root_dart/third_party/requirejs/require.js" onload="runNextTest()"></script>
</head>
<body>
  <h1>DDC Shard Batch Execution Engine</h1>
</body>
</html>''');

  final chromeProcess = await Process.start(chromeBin, [
    '--headless=new',
    '--disable-gpu',
    '--no-sandbox',
    '--enable-logging=stderr',
    '--v=1',
    'http://localhost:$port/root_build/shard_runner.html',
  ]);
  chromeProcess.stdout.drain();
  chromeProcess.stderr.transform(utf8.decoder).listen((msg) {
    final trimmed = msg.trim();
    if (trimmed.isNotEmpty &&
        (trimmed.contains('CONSOLE') ||
            trimmed.contains('Error') ||
            trimmed.contains('RequireJS') ||
            trimmed.contains('FAIL'))) {
      print('CHROME CONSOLE: $trimmed');
    }
  });

  try {
    await completer.future.timeout(const Duration(seconds: 120));
  } catch (_) {
    print('Error: Shard browser execution timed out after 120 seconds.');
    exitCode = 1;
    return;
  } finally {
    chromeProcess.kill();
    await server.close(force: true);
  }

  var runtimeFailures = 0;
  for (final tc in validTestCases) {
    final name = tc['name'] as String;
    final actualStatus = reportedResults[name];
    final expected = (tc['expected_outcome'] as List? ?? ['Pass'])
        .cast<String>();
    final dartFile = tc['file_path'] as String?;
    var hasRuntimeErrorTag = false;
    if (dartFile != null && await File(dartFile).exists()) {
      final content = await File(dartFile).readAsString();
      hasRuntimeErrorTag = RegExp(r'//#.*runtime error').hasMatch(content);
    }
    final isExpectedFail =
        expected.contains('RuntimeError') ||
        expected.contains('Fail') ||
        hasRuntimeErrorTag;

    if (actualStatus != 'PASS' && !isExpectedFail) {
      if (actualStatus == null) print('FAIL (Missing Runtime Outcome): $name');
      runtimeFailures++;
    } else if (actualStatus == 'PASS' && isExpectedFail) {
      print('FAIL (Expected RuntimeError/Fail, but succeeded): $name');
      runtimeFailures++;
    }
  }

  if (runtimeFailures > 0) {
    print(
      '\nError: $runtimeFailures test cases failed browser runtime execution.',
    );
    exitCode = 1;
    return;
  }

  print(
    'All ${validTestCases.length} real RequireJS browser tests in shard $shardIndex executed and passed successfully!',
  );
}
