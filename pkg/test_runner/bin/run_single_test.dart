// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

final String exeExt = Platform.isWindows ? '.exe' : '';

/// A standalone zero-dependency runner that executes a list of test configurations,
/// handles sharding, and maps process exit codes to expectations.
void main(List<String> args) async {
  // Advertise sharding support to Bazel if requested
  final shardStatusFile = Platform.environment['TEST_SHARD_STATUS_FILE'];
  if (shardStatusFile != null && shardStatusFile.isNotEmpty) {
    try {
      File(shardStatusFile).createSync(recursive: true);
    } catch (e) {
      print('Warning: Failed to touch TEST_SHARD_STATUS_FILE: $e');
    }
  }

  String? configPath;
  String? runOnly;
  for (var i = 0; i < args.length; i++) {
    if (args[i].startsWith('--config-json=')) {
      configPath = args[i].substring('--config-json='.length);
    } else if (args[i].startsWith('--run-only=')) {
      runOnly = args[i].substring('--run-only='.length);
    }
  }

  if (configPath == null) {
    print(
      'Usage: run_single_test.dart --config-json=<path-to-test-metadata-json>',
    );
    exit(2);
  }

  final file = File(configPath);
  if (!await file.exists()) {
    print('Error: Config file not found: $configPath');
    exit(2);
  }

  final content = await file.readAsString();
  final dynamic decoded = jsonDecode(content);
  var testCases = <Map<String, dynamic>>[];
  if (decoded is List) {
    testCases = List<Map<String, dynamic>>.from(
      decoded.map((x) => x as Map<String, dynamic>),
    );
  } else {
    testCases = [decoded as Map<String, dynamic>];
  }

  if (runOnly != null) {
    final runOnlyNonNull = runOnly;
    testCases = testCases.where((tc) {
      final filePath =
          tc['relative_file_path'] as String? ?? tc['file_path'] as String;
      return filePath == runOnlyNonNull ||
          filePath.endsWith(runOnlyNonNull) ||
          runOnlyNonNull.endsWith(filePath);
    }).toList();
  }

  // 1. Support Bazel test filtering (--test_filter or TESTBRIDGE_TEST_ONLY)
  final testFilter = Platform.environment['TESTBRIDGE_TEST_ONLY'];
  if (testFilter != null && testFilter.isNotEmpty) {
    final filterRegExp = RegExp(
      testFilter.replaceAll('*', '.*'),
      caseSensitive: false,
    );
    testCases = testCases.where((tc) {
      final name = tc['name'] as String;
      final filePath = tc['file_path'] as String;
      return name.contains(filterRegExp) || filePath.contains(filterRegExp);
    }).toList();
  }

  // 2. Support Bazel test sharding (TEST_TOTAL_SHARDS / TEST_SHARD_INDEX)
  final totalShardsStr = Platform.environment['TEST_TOTAL_SHARDS'];
  final shardIndexStr = Platform.environment['TEST_SHARD_INDEX'];
  if (totalShardsStr != null && shardIndexStr != null) {
    final totalShards = int.tryParse(totalShardsStr) ?? 1;
    final shardIndex = int.tryParse(shardIndexStr) ?? 0;
    final shardedTests = <Map<String, dynamic>>[];
    for (var i = 0; i < testCases.length; i++) {
      if (i % totalShards == shardIndex) {
        shardedTests.add(testCases[i]);
      }
    }
    testCases = shardedTests;
  }

  if (testCases.isEmpty) {
    print(
      'No tests to run (either empty metadata or filtered out by shard/test_filter).',
    );
    exit(0);
  }

  print('Executing ${testCases.length} test cases...');

  final failedTests = <String>[];
  for (var i = 0; i < testCases.length; i++) {
    final tc = testCases[i];
    final name = tc['name'] as String;
    print('\n[${i + 1}/${testCases.length}] Starting: $name');
    final success = await _runTestCase(tc);
    if (!success) {
      failedTests.add(name);
    }
  }

  print(
    '\n======================================================================',
  );
  print('TEST SUMMARY');
  print(
    '======================================================================',
  );
  print('Total tests:  ${testCases.length}');
  print('Passed:       ${testCases.length - failedTests.length}');
  print('Failed:       ${failedTests.length}');
  if (failedTests.isNotEmpty) {
    print(
      '----------------------------------------------------------------------',
    );
    print('Failed tests list:');
    for (final failName in failedTests) {
      print('  - $failName');
    }
    print(
      '======================================================================',
    );
    exit(1);
  }
  print(
    '======================================================================',
  );
  exit(0);
}

/// Executes a single test case's command chain and returns whether it matched expectations.
Future<bool> _runTestCase(Map<String, dynamic> testCase) async {
  final testName = testCase['name'] as String;
  final filePath = testCase['file_path'] as String;
  final expectedOutcomes = List<String>.from(
    testCase['expected_outcome'] as List,
  );
  final commands = testCase['commands'] as List;

  final runfilesDir =
      Platform.environment['RUNFILES_DIR'] ??
      Platform.environment['TEST_SRCDIR'];
  final resolvedFilePath = runfilesDir != null && runfilesDir.isNotEmpty
      ? _resolvePlaceholders(filePath, runfilesDir)
      : filePath;

  String? analyzerPackagesRoot;
  if (runfilesDir != null && runfilesDir.isNotEmpty) {
    for (final prefix in [
      _getCanonicalRepoName('dart_packages'),
      '+dart_packages_extension+dart_packages',
      'dart_packages',
      '_main',
    ]) {
      final pathToCheck = p.join(runfilesDir, prefix, 'pkg', 'analyzer');
      if (Directory(pathToCheck).existsSync()) {
        analyzerPackagesRoot = '$prefix/pkg';
        break;
      }
    }
  }

  final isStaticErrorTest = testCase['is_static_error_test'] as bool? ?? false;
  final relativeFilePath = testCase['relative_file_path'] as String?;
  final compiler = testCase['compiler'] as String?;

  var expectedErrors = <ExpectedError>[];
  String? expectedSource;

  if (isStaticErrorTest) {
    if (relativeFilePath == null || compiler == null) {
      print(
        'Error: Missing relative_file_path or compiler for static error test.',
      );
      exit(2);
    }

    expectedSource = const {
      'dartk': 'cfe',
      'dart2wasm': 'web',
      'dart2js': 'web',
      'ddc': 'web',
      'fasta': 'cfe',
      'dart2analyzer': 'analyzer',
      'spec_parser': 'spec_parser',
    }[compiler];

    if (expectedSource == null) {
      print('Error: Unsupported compiler for static error test: $compiler');
      exit(2);
    }

    final resolvedTestFile = _Runfiles.resolve('_main/$relativeFilePath');
    final file = File(resolvedTestFile);
    if (!file.existsSync()) {
      print('Error: Test file not found in runfiles: $resolvedTestFile');
      exit(2);
    }

    final source = file.readAsStringSync();
    final allExpected = parseExpectations(source);
    expectedErrors = allExpected
        .where((e) => e.source == expectedSource)
        .toList();

    print(
      'Parsed ${expectedErrors.length} expected errors for $expectedSource',
    );
  }

  print(
    '======================================================================',
  );
  print('Running Test: $testName');
  print('File Path:    $resolvedFilePath');
  print('Expected:     $expectedOutcomes');
  print(
    '======================================================================',
  );

  final dartBinEnv = Platform.environment['DART_BIN'] ?? Platform.executable;
  String? resolvedPlatformCache;
  String getResolvedPlatform() {
    if (resolvedPlatformCache != null) return resolvedPlatformCache!;
    if (compiler == 'dartkp' && dartBinEnv.contains('prebuilt_dart_sdk')) {
      final sdkDir = p.dirname(p.dirname(p.absolute(dartBinEnv)));
      resolvedPlatformCache = p.join(
        sdkDir,
        'lib',
        '_internal',
        'vm_platform.dill',
      );
    } else {
      resolvedPlatformCache = _Runfiles.resolve(
        '_main/runtime/vm/vm_platform.dill',
      );
    }
    return resolvedPlatformCache!;
  }

  var actualOutcome = 'Pass';

  for (var i = 0; i < commands.length; i++) {
    final cmd = commands[i] as Map<String, dynamic>;
    if (!cmd.containsKey('executable')) {
      print(
        'Warning: Command ${i + 1} is not executable directly: ${cmd['displayName'] ?? cmd}',
      );
      continue;
    }

    var executable = cmd['executable'] as String;
    var arguments = List<String>.from(cmd['arguments'] as List);

    if (runfilesDir != null && runfilesDir.isNotEmpty) {
      executable = _resolvePlaceholders(executable, runfilesDir);
      arguments = arguments
          .map((arg) => _resolvePlaceholders(arg, runfilesDir))
          .toList();
    }

    final normalizedExe = executable.replaceAll('\\', '/');

    if (compiler == 'fasta') {
      final compileScript = _Runfiles.resolve(
        '_main/pkg/front_end/tool/compile.dart',
      );
      arguments.insert(0, compileScript);
    }

    arguments = arguments.map((arg) {
      if (arg.startsWith('--packages=')) {
        final resolvedPkg = _getRewrittenPackageConfig();
        return '--packages=$resolvedPkg';
      }
      return arg;
    }).toList();

    for (var j = 0; j < arguments.length; j++) {
      if (arguments[j] == '--platform' && j + 1 < arguments.length) {
        arguments[j + 1] = getResolvedPlatform();
      } else if (arguments[j].startsWith('--platform=')) {
        arguments[j] = '--platform=${getResolvedPlatform()}';
      }
    }
    final testSrcdir = Platform.environment['TEST_SRCDIR'];

    if (normalizedExe == 'pkg/dart2wasm/tool/compile_benchmark' &&
        testSrcdir != null) {
      var resolvedRuntime = _Runfiles.resolve(
        '_main/sdk/dart-sdk/bin/dartaotruntime$exeExt',
      );
      var resolvedSnapshot = _Runfiles.resolve(
        '_main/sdk/dart-sdk/bin/snapshots/dart2wasm_product.snapshot',
      );
      var resolvedPlatform = _Runfiles.resolve(
        '_main/sdk/dart-sdk/lib/_internal/dart2wasm_platform.dill',
      );
      var resolvedWasmOpt = _Runfiles.resolve(
        '_main/sdk/dart-sdk/bin/utils/wasm-opt$exeExt',
      );

      if (!File(resolvedRuntime).existsSync()) {
        resolvedRuntime = _Runfiles.resolve(
          '_main/tools/sdks/dart-sdk/bin/dartaotruntime$exeExt',
        );
        resolvedSnapshot = _Runfiles.resolve(
          '_main/tools/sdks/dart-sdk/bin/snapshots/dart2wasm_product.snapshot',
        );
        resolvedPlatform = _Runfiles.resolve(
          '_main/tools/sdks/dart-sdk/lib/_internal/dart2wasm_platform.dill',
        );
        resolvedWasmOpt = _Runfiles.resolve(
          '_main/tools/sdks/dart-sdk/bin/utils/wasm-opt$exeExt',
        );
      }

      // Check if we need to run the opt phase (if optimization is enabled and we have wasm-opt)
      var hasOptimization = false;
      for (final arg in arguments) {
        if (arg == '-O1' || arg == '-O2' || arg == '-O3' || arg == '-O4') {
          hasOptimization = true;
        } else if (arg == '-O0') {
          hasOptimization = false;
        }
        if (arg.startsWith('--optimization-level=')) {
          final level = arg.substring('--optimization-level='.length);
          if (level != '0') {
            hasOptimization = true;
          } else {
            hasOptimization = false;
          }
        }
      }

      final hasWasmOpt = File(resolvedWasmOpt).existsSync();
      final isOptPhase = arguments.contains('--phases=opt');

      if (hasOptimization && hasWasmOpt && !isOptPhase) {
        final optArgs = <String>[];
        String? wasmFile;
        for (final arg in arguments) {
          if (arg.endsWith('.dart')) {
            continue;
          }
          if (arg.endsWith('.wasm')) {
            wasmFile = arg;
            continue;
          }
          optArgs.add(arg);
        }
        if (wasmFile != null) {
          optArgs.add('--phases=opt');
          optArgs.add(wasmFile);
          optArgs.add(wasmFile);

          final optCmd = {
            'executable': 'pkg/dart2wasm/tool/compile_benchmark',
            'arguments': optArgs,
            if (cmd['working_directory'] != null)
              'working_directory': cmd['working_directory'],
            if (cmd['environment'] != null) 'environment': cmd['environment'],
          };
          commands.insert(i + 1, optCmd);
        }
      }

      executable = resolvedRuntime;
      final newArgs = [
        resolvedSnapshot,
        '--platform=$resolvedPlatform',
        if (hasWasmOpt) '--wasm-opt=$resolvedWasmOpt',
      ];
      for (final arg in arguments) {
        if (arg.startsWith('--extra-compiler-option=')) {
          newArgs.add(arg.substring('--extra-compiler-option='.length));
        } else {
          newArgs.add(arg);
        }
      }
      arguments = newArgs;
    } else if (normalizedExe == 'pkg/dart2wasm/tool/run_benchmark' &&
        testSrcdir != null) {
      String osDir;
      if (Platform.isLinux) {
        osDir = 'linux/x64';
      } else if (Platform.isMacOS) {
        final isArm64 =
            Platform.version.contains('arm64') ||
            Platform.version.contains('aarch64');
        final arm64D8 = _Runfiles.resolve(
          '_main/third_party/d8/macos/arm64/d8',
        );
        if (isArm64 && File(arm64D8).existsSync()) {
          osDir = 'macos/arm64';
        } else {
          osDir = 'macos/x64';
        }
      } else if (Platform.isWindows) {
        osDir = 'windows/x64';
      } else {
        throw UnsupportedError('Unsupported OS: ${Platform.operatingSystem}');
      }
      executable = _Runfiles.resolve('_main/third_party/d8/$osDir/d8$exeExt');
      final runWasmJs = _Runfiles.resolve(
        '_main/pkg/dart2wasm/bin/run_wasm.js',
      );

      var shellOptions = <String>[];
      String? wasmFile;
      var extraWasmFiles = <String>[];

      for (final arg in arguments) {
        if (arg == '--d8') continue;
        if (arg.startsWith('--shell-option=')) {
          shellOptions.add(arg.substring('--shell-option='.length));
        } else if (arg.endsWith('.wasm')) {
          if (wasmFile == null) {
            wasmFile = arg;
          } else {
            var resolvedArg = arg;
            final match = RegExp(r'^out/[^/]+/wasm/(.+)$').firstMatch(arg);
            if (match != null) {
              final wasmName = match[1]!;
              resolvedArg = _Runfiles.resolve(
                '_main/utils/dart2wasm/wasm/$wasmName',
              );
            }
            extraWasmFiles.add(resolvedArg);
          }
        }
      }

      if (wasmFile != null) {
        final mjsFile = wasmFile.replaceAll(RegExp(r'\.wasm$'), '.mjs');
        final newArgs = [
          ...shellOptions,
          runWasmJs,
          '--',
          mjsFile,
          wasmFile,
          ...extraWasmFiles,
        ];
        arguments = newArgs;
      }
    } else if (normalizedExe == 'out/ReleaseX64/dart' ||
        normalizedExe.endsWith('/dart') ||
        normalizedExe.endsWith('/dartaotruntime') ||
        normalizedExe.endsWith('/gen_snapshot') ||
        normalizedExe.endsWith('pkg/vm/tool/gen_kernel')) {
      if (normalizedExe == 'out/ReleaseX64/dart' ||
          normalizedExe.endsWith('/dart')) {
        executable = dartBinEnv;
      } else if (normalizedExe.endsWith('/dartaotruntime')) {
        final sdkBinDir = p.dirname(dartBinEnv);
        executable = p.join(sdkBinDir, 'dartaotruntime$exeExt');
      } else if (normalizedExe.endsWith('/gen_snapshot')) {
        final sdkBinDir = p.dirname(dartBinEnv);
        executable = p.join(sdkBinDir, 'utils', 'gen_snapshot$exeExt');
      } else {
        // Must be pkg/vm/tool/gen_kernel
        final sdkBinDir = p.dirname(dartBinEnv);
        final snapshot = p.join(
          sdkBinDir,
          'snapshots',
          'gen_kernel_aot.dart.snapshot',
        );
        if (File(snapshot).existsSync()) {
          executable = p.join(sdkBinDir, 'dartaotruntime$exeExt');
          arguments = [snapshot, ...arguments];
        } else {
          final genKernelDart = _Runfiles.resolve(
            '_main/pkg/vm/bin/gen_kernel.dart',
          );
          executable = dartBinEnv;
          arguments = [genKernelDart, ...arguments];
        }
      }
    } else if (testSrcdir != null &&
        (normalizedExe == 'third_party/d8/linux/x64/d8' ||
            normalizedExe.endsWith('/d8') ||
            normalizedExe.endsWith('/d8.exe'))) {
      String osDir;
      if (Platform.isLinux) {
        osDir = 'linux/x64';
      } else if (Platform.isMacOS) {
        final isArm64 =
            Platform.version.contains('arm64') ||
            Platform.version.contains('aarch64');
        final arm64D8 = _Runfiles.resolve(
          '_main/third_party/d8/macos/arm64/d8',
        );
        if (isArm64 && File(arm64D8).existsSync()) {
          osDir = 'macos/arm64';
        } else {
          osDir = 'macos/x64';
        }
      } else if (Platform.isWindows) {
        osDir = 'windows/x64';
      } else {
        throw UnsupportedError('Unsupported OS: ${Platform.operatingSystem}');
      }
      executable = _Runfiles.resolve('_main/third_party/d8/$osDir/d8$exeExt');
    } else if (testSrcdir != null &&
        (normalizedExe == '/usr/bin/google-chrome' ||
            normalizedExe.endsWith('/google-chrome') ||
            normalizedExe.endsWith('/chrome.exe') ||
            normalizedExe.contains('/Google Chrome.app/'))) {
      var resolvedChrome = _Runfiles.resolve('chrome/chrome$exeExt');
      if (!File(resolvedChrome).existsSync()) {
        if (Platform.isMacOS) {
          resolvedChrome = _Runfiles.resolve(
            'chrome/Google Chrome for Testing.app/Contents/MacOS/Google Chrome for Testing',
          );
        }
        if (!File(resolvedChrome).existsSync()) {
          resolvedChrome = _Runfiles.resolve(
            '_main/third_party/browsers/chrome/chrome$exeExt',
          );
        }
      }
      if (File(resolvedChrome).existsSync()) {
        executable = resolvedChrome;
      }
    } else if (testSrcdir != null &&
        (normalizedExe == '/usr/bin/firefox' ||
            normalizedExe.endsWith('/firefox') ||
            normalizedExe.endsWith('/firefox.exe') ||
            normalizedExe.contains('/Firefox.app/'))) {
      var resolvedFirefox = _Runfiles.resolve('firefox/firefox$exeExt');
      if (!File(resolvedFirefox).existsSync()) {
        resolvedFirefox = _Runfiles.resolve(
          '_main/third_party/browsers/firefox/firefox$exeExt',
        );
      }
      if (File(resolvedFirefox).existsSync()) {
        executable = resolvedFirefox;
      }
    }
    var workingDirectory = cmd['working_directory'] as String?;
    var environment = cmd['environment'] != null
        ? Map<String, String>.from(cmd['environment'] as Map)
        : null;

    if (runfilesDir != null && runfilesDir.isNotEmpty) {
      if (workingDirectory != null) {
        workingDirectory = _resolvePlaceholders(workingDirectory, runfilesDir);
      }
      if (environment != null) {
        final newEnv = <String, String>{};
        for (final entry in environment.entries) {
          newEnv[entry.key] = _resolvePlaceholders(entry.value, runfilesDir);
        }
        environment = newEnv;
      }
    }
    if (analyzerPackagesRoot != null) {
      environment ??= <String, String>{};
      environment['ANALYZER_PACKAGES_ROOT'] = analyzerPackagesRoot;
    }

    final testTmpdir = Platform.environment['TEST_TMPDIR'];
    if (testTmpdir != null) {
      arguments = arguments
          .map((arg) => _rewriteSandboxPath(arg, testTmpdir))
          .toList();
      if (workingDirectory != null) {
        workingDirectory = _rewriteSandboxPath(workingDirectory, testTmpdir);
      }
      if (environment != null) {
        final newEnv = <String, String>{};
        for (final entry in environment.entries) {
          newEnv[entry.key] = _rewriteSandboxPath(entry.value, testTmpdir);
        }
        environment = newEnv;
      }
    }

    final exeName = p.basename(executable);
    if (exeName == 'dart' ||
        exeName == 'dart.exe' ||
        exeName == 'dartvm' ||
        exeName == 'dartvm.exe') {
      var scriptIndex = -1;
      for (var j = 0; j < arguments.length; j++) {
        final arg = arguments[j];
        if (!arg.startsWith('-') &&
            (arg.endsWith('.dart') ||
                arg.endsWith('.dill') ||
                arg.endsWith('.snapshot'))) {
          scriptIndex = j;
          break;
        }
      }
      if (scriptIndex != -1) {
        final scriptPath = arguments[scriptIndex];
        final normalizedScript = scriptPath.replaceAll('\\', '/');
        final runfilesScriptPath =
            (normalizedScript.startsWith('_main/') ||
                normalizedScript.startsWith('@') ||
                normalizedScript.startsWith('external/') ||
                p.isAbsolute(scriptPath))
            ? scriptPath
            : '_main/$scriptPath';
        final resolvedScript = p.isAbsolute(scriptPath)
            ? scriptPath
            : _Runfiles.resolve(runfilesScriptPath);
        arguments[scriptIndex] = resolvedScript;

        final resolvedPkg = _getRewrittenPackageConfig();
        final packagesIndex = arguments.indexWhere(
          (arg) => arg.startsWith('--packages='),
        );
        if (packagesIndex != -1) {
          arguments[packagesIndex] = '--packages=$resolvedPkg';
        } else {
          final pkgIndex = arguments.indexOf('--packages');
          if (pkgIndex != -1 && pkgIndex + 1 < arguments.length) {
            arguments[pkgIndex + 1] = resolvedPkg;
          } else {
            arguments.insert(scriptIndex, '--packages=$resolvedPkg');
          }
        }
      }
    }

    print(
      '\n[Command ${i + 1}/${commands.length}]: $executable ${arguments.join(' ')}',
    );
    if (workingDirectory != null) {
      print('Working Directory: $workingDirectory');
    }
    if (environment != null) {
      print('Environment Overrides: $environment');
    }

    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment,
    );

    final stdoutBuffer = StringBuffer();
    final stderrBuffer = StringBuffer();

    final stdoutFuture = process.stdout.transform(utf8.decoder).forEach((data) {
      stdoutBuffer.write(data);
      stdout.write(data);
    });

    final stderrFuture = process.stderr.transform(utf8.decoder).forEach((data) {
      stderrBuffer.write(data);
      stderr.write(data);
    });

    await Future.wait([stdoutFuture, stderrFuture]);

    final exitCode = await process.exitCode;
    print('[Command ${i + 1} exited with code $exitCode]');

    if (isStaticErrorTest) {
      final combinedOutput = stdoutBuffer.toString() + stderrBuffer.toString();
      final actualErrors = parseCompilerErrors(
        combinedOutput,
        expectedSource!,
        relativeFilePath!,
      );

      print('\n--- Static Error Verification ---');
      print('Expected errors: ${expectedErrors.length}');
      for (var e in expectedErrors) {
        print('  - Expected at line ${e.line}, col ${e.column}: ${e.message}');
      }
      print('Actual errors parsed: ${actualErrors.length}');
      for (var e in actualErrors) {
        print('  - Actual at line ${e.line}, col ${e.column}: ${e.message}');
      }

      final validation = validateErrors(expectedErrors, actualErrors);
      if (validation == null) {
        actualOutcome = 'Pass';
        print(
          'RESULT: Static error verification succeeded (all expectations met).',
        );
        if (exitCode != 0) {
          break; // Break command loop as this was an expected failure
        }
      } else {
        actualOutcome = 'CompileTimeError';
        print('RESULT: Static error verification failed:\n$validation');
        break; // Fail and break command loop
      }
    } else {
      if (exitCode != 0) {
        // Map non-zero exit codes to test Expectations
        if (exitCode == 254) {
          actualOutcome = 'CompileTimeError';
        } else if (exitCode == 252) {
          actualOutcome = 'DartkCrash';
        } else if (exitCode < 0 || exitCode == 253) {
          actualOutcome = 'Crash';
        } else {
          actualOutcome = 'RuntimeError';
        }
        print('\nCommand failed. Resolved actual test outcome: $actualOutcome');
        break;
      }
    }
  }

  print('\nTest execution finished.');
  print('Actual Outcome:    $actualOutcome');
  print('Expected Outcomes: $expectedOutcomes');

  var matched = expectedOutcomes.contains(actualOutcome);
  if (!matched) {
    // Handle expectation grouping and "missing error" outcomes
    matched = expectedOutcomes.any((exp) {
      if (exp == 'Fail') {
        return const {
          'RuntimeError',
          'CompileTimeError',
          'SyntaxError',
          'MissingRuntimeError',
          'MissingCompileTimeError',
          'MissingStaticWarning',
          'StaticWarning',
          'NonUtf8Output',
          'TruncatedOutput',
        }.contains(actualOutcome);
      }
      if (exp == 'Crash') {
        return actualOutcome == 'DartkCrash';
      }
      if (exp == 'Skip') {
        return actualOutcome == 'ExtraSlow' || actualOutcome == 'SkipSlow';
      }
      if (actualOutcome == 'Pass') {
        return exp == 'MissingCompileTimeError' || exp == 'MissingRuntimeError';
      }
      return false;
    });
  }

  if (matched) {
    print('RESULT: SUCCESS (Outcome matches expectations)');
    return true;
  } else {
    print(
      'RESULT: FAILURE (Outcome $actualOutcome does NOT match expectations)',
    );
    return false;
  }
}

String _rewriteSandboxPath(String arg, String testTmpdir) {
  if (arg.startsWith('-D') && arg.contains('=')) {
    final index = arg.indexOf('=');
    final name = arg.substring(0, index);
    final value = arg.substring(index + 1);
    return '$name=${_rewriteSandboxPathRaw(value, testTmpdir)}';
  }
  if (arg.startsWith('--') && arg.contains('=')) {
    final index = arg.indexOf('=');
    final name = arg.substring(0, index);
    final value = arg.substring(index + 1);
    return '$name=${_rewriteSandboxPathRaw(value, testTmpdir)}';
  }
  return _rewriteSandboxPathRaw(arg, testTmpdir);
}

String _rewriteSandboxPathRaw(String path, String testTmpdir) {
  if (!path.contains('/generated_compilations/') &&
      !path.contains('/generated_tests/')) {
    return path;
  }

  final match = RegExp(
    r'/out/([^/]+)/generated_(compilations|tests)/',
  ).firstMatch(path);
  if (match != null) {
    final configName = match[1]!;
    final outConfigIndex = path.indexOf('/out/$configName/');
    final relativePart = path.substring(
      outConfigIndex + '/out/$configName/'.length,
    );
    final rewritten = '$testTmpdir/out_$configName/$relativePart';
    Directory(File(rewritten).parent.path).createSync(recursive: true);
    return rewritten;
  }

  return path;
}

String? _rewrittenPackageConfig;

String _getRewrittenPackageConfig() {
  return _rewrittenPackageConfig ??= _rewritePackageConfig();
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

String _rewritePackageConfig() {
  final dartPackagesRepo = _getCanonicalRepoName('dart_packages');
  var originalPath = _Runfiles.resolve(
    '$dartPackagesRepo/.dart_tool/package_config.json',
  );
  if (!File(originalPath).existsSync()) {
    originalPath = _Runfiles.resolve('$dartPackagesRepo/package_config.json');
  }
  if (!File(originalPath).existsSync()) {
    originalPath = _Runfiles.resolve('_main/.dart_tool/package_config.json');
  }
  if (!File(originalPath).existsSync()) {
    originalPath = _Runfiles.resolve('_main/package_config.json');
  }
  final file = File(originalPath);
  if (!file.existsSync()) {
    return originalPath;
  }

  final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final packages = json['packages'] as List<dynamic>;
  final newPackages = <Map<String, dynamic>>[];

  for (final pkg in packages) {
    final map = Map<String, dynamic>.from(pkg as Map);
    final pkgName = map['name'] as String?;
    final rootUri = map['rootUri'] as String;
    var relativePath = rootUri;
    while (relativePath.startsWith('../')) {
      relativePath = relativePath.substring(3);
    }
    if (relativePath != rootUri) {
      final String runfilesPath;
      if (relativePath.startsWith('external/')) {
        final parts = relativePath.substring('external/'.length).split('/');
        final apparentRepoName = parts[0];
        final canonicalRepoName = _getCanonicalRepoName(apparentRepoName);
        runfilesPath = [canonicalRepoName, ...parts.sublist(1)].join('/');
      } else {
        runfilesPath = '_main/$relativePath';
      }
      final physicalPath = _Runfiles.resolve(runfilesPath, pkgName: pkgName);
      final uri = Uri.directory(p.absolute(physicalPath));
      map['rootUri'] = uri.toString();
    }
    newPackages.add(map);
  }

  json['packages'] = newPackages;

  final tempDir = Directory.systemTemp.createTempSync('dart_package_config');
  final tempFile = File('${tempDir.path}/package_config.json');
  tempFile.writeAsStringSync(jsonEncode(json));

  return tempFile.path;
}

abstract final class _Runfiles {
  static Map<String, String>? _manifest;

  static String resolve(String relativePath, {String? pkgName}) {
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
      if (pkgName != null && pkgName.isNotEmpty) {
        for (final prefix in [
          '_main',
          _getCanonicalRepoName('dart_packages'),
          '+dart_packages_extension+dart_packages',
          'dart_packages',
        ]) {
          final pkgAltPath = p.join(runfilesDir, prefix, 'pkg', pkgName);
          final libType = FileSystemEntity.typeSync(p.join(pkgAltPath, 'lib'));
          if (libType != FileSystemEntityType.notFound) {
            return pkgAltPath;
          }
          final pkgType = FileSystemEntity.typeSync(pkgAltPath);
          if (pkgType == FileSystemEntityType.directory) {
            return pkgAltPath;
          }
        }
      }
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
      final primary = File(p.join(runfilesDir, normalizedPath));
      if (primary.existsSync() || Directory(primary.path).existsSync()) {
        return primary.path;
      }
      return primary.path;
    }

    return relativePath;
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
}

final _cfeErrorRegexp = RegExp(
  r"^(?:([^:\n\r]+):(\d+):(\d+): )?(Error|Warning): (.*)$",
  multiLine: true,
);

final _webErrorRegexp = RegExp(
  r"^([^:\n\r]+):(\d+):(\d+): (Error|Warning): (.*)$",
  multiLine: true,
);

class ExpectedError {
  final String source;
  final int line;
  final int column;
  final String message;

  ExpectedError(this.source, this.line, this.column, this.message);
}

class ActualError {
  final String source;
  final int line;
  final int column;
  final String message;

  ActualError(this.source, this.line, this.column, this.message);
}

List<ExpectedError> parseExpectations(String sourceContent) {
  sourceContent = sourceContent.replaceAll('\r', '');
  final lines = sourceContent.split('\n');
  var expectedErrors = <ExpectedError>[];

  var lastRealLine = -1;

  final caretRegex = RegExp(r"^\s*//\s*(\^+)\s*$");
  final explicitRegex = RegExp(
    r"^\s*//\s*\[\s*error (?:line\s+(\d+)\s*,)?\s*column\s+(\d+)\s*(?:,\s*"
    r"length\s+(\d+)\s*)?\]\s*$",
  );
  final messageRegex = RegExp(r"^\s*// \[([^\]]+)\]\s*(.*)");

  for (var i = 0; i < lines.length; i++) {
    final lineText = lines[i];

    // Check if it's a caret marker
    if (caretRegex.firstMatch(lineText) != null) {
      if (lastRealLine == -1) continue;
      final column = lineText.indexOf('^') + 1;

      // Peek next lines for messages
      var j = i + 1;
      while (j < lines.length) {
        final nextLine = lines[j].replaceAll('\r', '');
        if (messageRegex.firstMatch(nextLine) case var msgMatch?) {
          final source = msgMatch[1]!.split(' ')[0];
          final message = msgMatch[2]!.trim();
          expectedErrors.add(
            ExpectedError(source, lastRealLine + 1, column, message),
          );
          j++;
        } else {
          break;
        }
      }
      i = j - 1;
      continue;
    }

    // Check if it's an explicit marker
    if (explicitRegex.firstMatch(lineText) case var match?) {
      final lineCapture = match[1];
      final column = int.parse(match[2]!);
      final targetLine = lineCapture != null
          ? int.parse(lineCapture)
          : lastRealLine + 1;

      // Peek next lines for messages
      var j = i + 1;
      while (j < lines.length) {
        final nextLine = lines[j].replaceAll('\r', '');
        if (messageRegex.firstMatch(nextLine) case var msgMatch?) {
          final source = msgMatch[1]!.split(' ')[0];
          final message = msgMatch[2]!.trim();
          expectedErrors.add(
            ExpectedError(source, targetLine, column, message),
          );
          j++;
        } else {
          break;
        }
      }
      i = j - 1;
      continue;
    }

    // If it's a regular comment line, don't update lastRealLine
    if (lineText.trim().startsWith('//')) {
      continue;
    }

    // It's a real code line
    lastRealLine = i;
  }

  return expectedErrors;
}

List<ActualError> parseCompilerErrors(
  String output,
  String expectedSource,
  String testPath,
) {
  output = output.replaceAll('\r', '');
  var errors = <ActualError>[];
  final regExp = expectedSource == 'web' ? _webErrorRegexp : _cfeErrorRegexp;

  ActualError? previousError;
  for (var match in regExp.allMatches(output)) {
    var path = match[1];
    var line = match[2] != null ? int.parse(match[2]!) : null;
    var column = match[3] != null ? int.parse(match[3]!) : null;
    var severity = match[4];
    var message = match[5];

    if (path == null) {
      if (severity == 'Context' && previousError != null) {
        path = previousError.source;
        line = previousError.line;
        column = previousError.column;
      } else {
        continue;
      }
    }

    // Skip errors in other files
    if (!path.endsWith(testPath)) {
      continue;
    }

    var error = ActualError(
      severity == "Context" ? "context" : expectedSource,
      line ?? 0,
      column ?? 0,
      message!.trim(),
    );

    errors.add(error);
    previousError = error;
  }
  return errors;
}

String? validateErrors(List<ExpectedError> expected, List<ActualError> actual) {
  var unmatchedExpected = <ExpectedError>[...expected];
  var unmatchedActual = <ActualError>[...actual];

  var buffer = StringBuffer();

  for (final exp in expected) {
    ActualError? match;
    for (final act in unmatchedActual) {
      if (act.line == exp.line) {
        if (act.message.contains(exp.message) ||
            exp.message.contains(act.message)) {
          if ((act.column - exp.column).abs() <= 2) {
            match = act;
            break;
          }
        }
      }
    }

    if (match != null) {
      unmatchedExpected.remove(exp);
      unmatchedActual.remove(match);
    }
  }

  if (unmatchedExpected.isEmpty && unmatchedActual.isEmpty) {
    return null;
  }

  if (unmatchedExpected.isNotEmpty) {
    buffer.writeln('Missing expected errors:');
    for (final exp in unmatchedExpected) {
      buffer.writeln('  - Line ${exp.line}, Col ${exp.column}: ${exp.message}');
    }
  }
  if (unmatchedActual.isNotEmpty) {
    buffer.writeln('Unexpected actual errors (or mismatched):');
    for (final act in unmatchedActual) {
      buffer.writeln('  - Line ${act.line}, Col ${act.column}: ${act.message}');
    }
  }

  return buffer.toString();
}

String _resolvePlaceholders(String path, String runfilesDir) {
  final normalizedRunfiles = runfilesDir.replaceAll('\\', '/');
  var result = path;
  if (result.contains(r'$SDK_ROOT')) {
    var sdkRoot = p.posix.join(normalizedRunfiles, '_main');
    if (!Directory(sdkRoot).existsSync()) {
      sdkRoot = p.posix.join(normalizedRunfiles, 'dart_sdk');
    }
    result = result.replaceAll(r'$SDK_ROOT', sdkRoot);
  }
  if (result.contains(r'$CO19_ROOT')) {
    String? co19Root;
    for (final prefix in [
      _getCanonicalRepoName('dart_co19_tests'),
      '+third_party_extension+dart_co19_tests',
      'dart_co19_tests',
    ]) {
      final pathToCheck = p.posix.join(normalizedRunfiles, prefix);
      if (Directory(pathToCheck).existsSync()) {
        co19Root = pathToCheck;
        break;
      }
    }
    co19Root ??= p.posix.join(normalizedRunfiles, 'dart_co19_tests');
    result = result.replaceAll(r'$CO19_ROOT', co19Root);
  }
  return result;
}
