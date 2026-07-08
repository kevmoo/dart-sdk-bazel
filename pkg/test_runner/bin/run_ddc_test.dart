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

import 'package:path/path.dart' as p;

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
  final packages = pkgs
      .map((pkg) {
        final pDir = _Runfiles.resolvePackage(pkg);
        if (pDir == null) return null;
        return {
          'name': pkg,
          'rootUri': Uri.directory(pDir).toString(),
          'packageUri': 'lib/',
        };
      })
      .whereType<Map<String, String>>()
      .toList();
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

  var ddcPath = '';
  var ddcFound = false;
  final candidates = [
    _Runfiles.resolve('_main/utils/ddc/dartdevc.dart.snapshot'),
    _Runfiles.resolve('_main/dart-sdk/bin/snapshots/dartdevc.dart.snapshot'),
    _Runfiles.resolve(
      '_main/dart-sdk/bin/snapshots/dartdevc_aot.dart.snapshot',
    ),
    _Runfiles.resolve('_main/pkg/dev_compiler/bin/dartdevc.dart'),
    p.join(testSrcdir, '_main/utils/ddc/dartdevc.dart.snapshot'),
    p.join(testSrcdir, 'dart_sdk/utils/ddc/dartdevc.dart.snapshot'),
    p.join(testSrcdir, 'utils/ddc/dartdevc.dart.snapshot'),
    p.join(testSrcdir, 'dart-sdk/bin/snapshots/dartdevc.dart.snapshot'),
    p.join(testSrcdir, '_main/dart-sdk/bin/snapshots/dartdevc.dart.snapshot'),
    p.join(testSrcdir, 'pkg/dev_compiler/bin/dartdevc.dart'),
    p.join(testSrcdir, '_main/pkg/dev_compiler/bin/dartdevc.dart'),
  ];
  for (final candidate in candidates) {
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
        if (arg.contains(r'$SDK_ROOT')) {
          var sdkRoot = p.join(testSrcdir, '_main');
          if (!Directory(sdkRoot).existsSync()) {
            sdkRoot = p.join(testSrcdir, 'dart_sdk');
          }
          arg = arg.replaceAll(r'$SDK_ROOT', sdkRoot);
        }
        arg = _resolveCo19Root(arg, testSrcdir);
        if (arg == '--dart-sdk-summary' && a + 1 < compileArgs.length) {
          cleanArgs.add(arg);
          var summaryPath = compileArgs[++a];
          for (final candidate in [
            summaryPath,
            p.join(
              testSrcdir,
              'dart-sdk',
              'lib',
              '_internal',
              'ddc_outline.dill',
            ),
            p.join(
              testSrcdir,
              '_main',
              'dart-sdk',
              'lib',
              '_internal',
              'ddc_outline.dill',
            ),
            p.join(testSrcdir, 'utils', 'ddc', 'ddc_outline.dill'),
            p.join(testSrcdir, '_main', 'utils', 'ddc', 'ddc_outline.dill'),
            p.join(testSrcdir, 'bazel-bin', 'utils', 'ddc', 'ddc_outline.dill'),
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
      var actualArgs = finalCleanArgs;
      if (isDdc) {
        var found = false;
        actualArgs = List<String>.from(finalCleanArgs);
        for (var i = 0; i < actualArgs.length; i++) {
          final arg = actualArgs[i];
          if (arg.endsWith('dartdevc.dart') || arg.endsWith('dartdevc')) {
            actualArgs[i] = ddcPath;
            found = true;
            break;
          }
        }
        if (!found) {
          actualArgs.insert(0, ddcPath);
        }
      }

      final res = await Process.run(actualExe, actualArgs);
      final success = res.exitCode == 0;
      var filePath = tc['file_path'] as String;
      filePath = _resolveCo19Root(filePath, testSrcdir);
      var targetFile = File(filePath);
      if (!p.isAbsolute(filePath)) {
        if (!await targetFile.exists()) {
          targetFile = File(p.join(testSrcdir, '_main', filePath));
        }
        if (!await targetFile.exists()) {
          targetFile = File(p.join(testSrcdir, filePath));
        }
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

Map<String, String>? _repoMappingCache;

String _getCanonicalRepoName(String apparentName) {
  if (_repoMappingCache != null) {
    return _repoMappingCache![apparentName] ??
        '+${apparentName}_extension+$apparentName';
  }
  final cache = <String, String>{};
  final runfilesDir =
      Platform.environment['RUNFILES_DIR'] ??
      Platform.environment['TEST_SRCDIR'];
  if (runfilesDir != null && runfilesDir.isNotEmpty) {
    final mappingFile = File(p.join(runfilesDir, '_repo_mapping'));
    if (mappingFile.existsSync()) {
      try {
        for (final line in mappingFile.readAsLinesSync()) {
          final parts = line.trim().split(',');
          if (parts.length >= 3) {
            final source = parts[0];
            final apparent = parts[1];
            final canonical = parts[2];
            if (source.isEmpty || source == '_main') {
              cache[apparent] = canonical;
            }
          }
        }
      } catch (_) {}
    }
  }
  _repoMappingCache = cache;
  return cache[apparentName] ?? '+${apparentName}_extension+$apparentName';
}

abstract final class _Runfiles {
  static Map<String, String>? _manifest;
  static final Map<String, String?> _pkgCache = {};

  static String resolve(String relativePath) {
    final normalizedPath = relativePath.replaceAll('\\', '/');

    final manifestFile = Platform.environment['RUNFILES_MANIFEST_FILE'];
    if (manifestFile != null && manifestFile.isNotEmpty) {
      _manifest ??= _loadManifest(manifestFile);
      final resolved = _manifest![normalizedPath];
      if (resolved != null) {
        return resolved;
      }
    }

    final runfilesDir =
        Platform.environment['RUNFILES_DIR'] ??
        Platform.environment['TEST_SRCDIR'];
    if (runfilesDir != null && runfilesDir.isNotEmpty) {
      if (normalizedPath.startsWith('_main/')) {
        final subPath = normalizedPath.substring('_main/'.length);
        for (final prefix in [
          _getCanonicalRepoName('dart_packages'),
          _getCanonicalRepoName('third_party'),
          '+dart_packages_extension+dart_packages',
          '+third_party_extension+third_party',
          'dart_packages',
          'third_party',
        ]) {
          final altPath = p.join(runfilesDir, prefix, subPath);
          final libType = FileSystemEntity.typeSync(p.join(altPath, 'lib'));
          if (libType != FileSystemEntityType.notFound) {
            return altPath;
          }
          final altType = FileSystemEntity.typeSync(altPath);
          if (altType != FileSystemEntityType.notFound) {
            return altPath;
          }
        }
      }
      return p.join(runfilesDir, normalizedPath);
    }

    return relativePath;
  }

  static String? resolvePackage(String pkgName) {
    if (pkgName.isEmpty) return null;

    final manifestFile = Platform.environment['RUNFILES_MANIFEST_FILE'];
    if (manifestFile != null && manifestFile.isNotEmpty) {
      _manifest ??= _loadManifest(manifestFile);
      final resolvedPkg = _resolvePkgFromManifest(pkgName);
      if (resolvedPkg != null) {
        return resolvedPkg;
      }
    }

    final runfilesDir =
        Platform.environment['RUNFILES_DIR'] ??
        Platform.environment['TEST_SRCDIR'];
    if (runfilesDir != null && runfilesDir.isNotEmpty) {
      final resolvedPkg = _findPackageInRunfiles(runfilesDir, pkgName);
      if (resolvedPkg != null) {
        return resolvedPkg;
      }
    }

    return null;
  }

  static Map<String, String> _loadManifest(String path) {
    final map = <String, String>{};
    final file = File(path);
    if (file.existsSync()) {
      for (final line in file.readAsLinesSync()) {
        final trimmed = line.trim();
        if (trimmed.isEmpty) continue;
        final spaceIndex = trimmed.indexOf(' ');
        if (spaceIndex != -1) {
          final manifestPath = trimmed.substring(0, spaceIndex);
          final physicalPath = trimmed.substring(spaceIndex + 1);
          map[manifestPath] = physicalPath;
        }
      }
    }
    return map;
  }

  static String? _resolvePkgFromManifest(String pkgName) {
    if (_manifest == null) return null;
    if (_pkgCache.containsKey(pkgName)) {
      return _pkgCache[pkgName];
    }
    for (final entry in _manifest!.entries) {
      final logicalPath = entry.key;
      final physicalPath = entry.value;
      final physicalPathNormalized = physicalPath.replaceAll('\\', '/');
      final parts = logicalPath.split('/');
      for (var i = 0; i < parts.length - 1; i++) {
        if (parts[i] == pkgName && parts[i + 1] == 'lib') {
          final logicalPkgRoot = parts.sublist(0, i + 1).join('/');
          final suffix = logicalPath.substring(logicalPkgRoot.length);
          if (physicalPathNormalized.endsWith(suffix)) {
            final result = physicalPath.substring(
              0,
              physicalPath.length - suffix.length,
            );
            _pkgCache[pkgName] = result;
            return result;
          }
        }
      }
    }
    _pkgCache[pkgName] = null;
    return null;
  }

  static String? _findPackageInRunfiles(String runfilesDir, String pkgName) {
    for (final prefix in [
      _getCanonicalRepoName('dart_packages'),
      '+dart_packages_extension+dart_packages',
      'dart_packages',
      '_main',
    ]) {
      // 1. Check standard SDK pkg/
      final sdkPkgPath = p.join(runfilesDir, prefix, 'pkg', pkgName);
      if (Directory(p.join(sdkPkgPath, 'lib')).existsSync()) {
        return sdkPkgPath;
      }

      // 2. Check third_party/pkg/
      final tpPkgPath = p.join(runfilesDir, prefix, 'third_party/pkg', pkgName);
      if (Directory(p.join(tpPkgPath, 'lib')).existsSync()) {
        return tpPkgPath;
      }
    }

    return null;
  }
}

String _resolveCo19Root(String path, String testSrcdir) {
  if (!path.contains(r'$CO19_ROOT')) return path;
  var co19Root = p.join(testSrcdir, 'dart_co19_tests');
  for (final prefix in [
    '+third_party_extension+dart_co19_tests',
    'dart_co19_tests',
    '_main/external/+third_party_extension+dart_co19_tests',
  ]) {
    final pathToCheck = p.join(testSrcdir, prefix);
    if (Directory(pathToCheck).existsSync()) {
      co19Root = pathToCheck;
      break;
    }
  }
  return path.replaceAll(r'$CO19_ROOT', co19Root);
}
