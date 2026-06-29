// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

/// Dynamic Bazel test target generator.
///
/// This script runs the Dart test runner in dry-run mode for various configurations,
/// discovers tests, and generates `BUILD.bazel` files in the external repository
/// to define sharded test targets.
///
/// Invocation:
/// dart generate_test_targets.dart --workspace-dir=`<dir>` --output-dir=`<dir>` [--suite=`<suite>`...]
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'suite_paths.dart';

void main(List<String> args) async {
  String? workspaceDir;
  String? outputDir;
  String? co19Dir;
  int maxShards = 50;
  final suites = <String>[];

  for (final arg in args) {
    if (arg.startsWith('--workspace-dir=')) {
      workspaceDir = arg.substring('--workspace-dir='.length);
    } else if (arg.startsWith('--output-dir=')) {
      outputDir = arg.substring('--output-dir='.length);
    } else if (arg.startsWith('--co19-dir=')) {
      co19Dir = arg.substring('--co19-dir='.length);
    } else if (arg.startsWith('--max-shards=')) {
      maxShards = int.parse(arg.substring('--max-shards='.length));
    } else if (arg.startsWith('--suite=')) {
      suites.add(arg.substring('--suite='.length));
    }
  }

  if (workspaceDir == null || outputDir == null) {
    print(
      'Usage: generate_test_targets.dart --workspace-dir=<dir> --output-dir=<dir> [--suite=<suite>...]',
    );
    exitCode = 2;
    return;
  }

  workspaceDir = p.absolute(workspaceDir);
  outputDir = p.absolute(outputDir);
  if (co19Dir != null) {
    co19Dir = p.absolute(co19Dir);
  }

  final subDirToPkgDir = <String, String>{};

  final debugLog = File('$outputDir/debug.log');
  final debugBuf = StringBuffer();
  debugBuf.writeln('=== Debug Log ===');
  debugBuf.writeln('Workspace Dir: $workspaceDir');
  debugBuf.writeln('Output Dir: $outputDir');
  debugBuf.writeln('co19 Dir: $co19Dir');
  debugBuf.writeln('Suites from Starlark: $suites');

  final manualPatterns = <String, List<String>>{};
  final quarantinePatterns = <String, List<String>>{};
  final extraBaselineDeps = <String, List<String>>{};
  final extraDepsByPattern = <String, Map<String, List<String>>>{};
  final timeoutsByPattern = <String, Map<String, String>>{};
  final globalExtraDepsByPattern = <String, List<String>>{};

  final suiteConfigFile =
      File('$workspaceDir/tools/bazel/dart/suite_config.json');
  if (suiteConfigFile.existsSync()) {
    try {
      final decoded = jsonDecode(suiteConfigFile.readAsStringSync())
          as Map<String, dynamic>;
      final packagesMap = decoded['packages'] as Map<String, dynamic>? ?? {};
      for (final entry in packagesMap.entries) {
        final pkgPath = entry.key;
        final pkgConfig = entry.value as Map<String, dynamic>? ?? {};

        final patterns =
            List<String>.from(pkgConfig['manual_patterns'] as List? ?? []);
        if (patterns.isNotEmpty) {
          manualPatterns[pkgPath] = patterns;
        }

        final quarantineList =
            List<String>.from(pkgConfig['quarantine_patterns'] as List? ?? []);
        if (quarantineList.isNotEmpty) {
          quarantinePatterns[pkgPath] = quarantineList;
        }

        final baseDeps =
            List<String>.from(pkgConfig['extra_baseline_deps'] as List? ?? []);
        if (baseDeps.isNotEmpty) {
          extraBaselineDeps[pkgPath] = baseDeps;
        }

        final depsByPatternMap =
            pkgConfig['extra_deps_by_pattern'] as Map<String, dynamic>? ?? {};
        if (depsByPatternMap.isNotEmpty) {
          final mapped = <String, List<String>>{};
          for (final patEntry in depsByPatternMap.entries) {
            mapped[patEntry.key] = List<String>.from(patEntry.value as List);
          }
          extraDepsByPattern[pkgPath] = mapped;
        }

        final timeoutsMap =
            pkgConfig['timeouts_by_pattern'] as Map<String, dynamic>? ?? {};
        if (timeoutsMap.isNotEmpty) {
          final mappedTimeouts = <String, String>{};
          for (final tEntry in timeoutsMap.entries) {
            mappedTimeouts[tEntry.key] = tEntry.value as String;
          }
          timeoutsByPattern[pkgPath] = mappedTimeouts;
        }
      }

      final globalMap =
          decoded['global_extra_deps_by_pattern'] as Map<String, dynamic>? ??
              {};
      for (final gEntry in globalMap.entries) {
        globalExtraDepsByPattern[gEntry.key] =
            List<String>.from(gEntry.value as List);
      }
    } catch (e) {
      stderr.writeln('Error: Failed to parse suite_config.json: $e');
      rethrow;
    }
  } else {
    throw FileSystemException(
        'Required suite configuration file not found', suiteConfigFile.path);
  }

  // Use the dart binary this generator is already running under (the .bzl
  // resolves it via @prebuilt_dart_sdk and spawns us with it). The previous
  // hardcoded $workspaceDir/tools/sdks/dart-sdk path does not exist on hosts
  // without the gclient-synced SDK, such as CI runners.
  final dartPath = Platform.resolvedExecutable;
  final exporterPath = '$workspaceDir/pkg/test_runner/bin/test_runner.dart';

  if (!File(exporterPath).existsSync()) {
    debugBuf.writeln(
      'Error: Could not locate test runner script at: $exporterPath',
    );
    debugLog.writeAsStringSync(debugBuf.toString());
    exitCode = 2;
    return;
  }

  // 2. Run dry-run exporter natively for all configurations in parallel
  final futures = _configs.map((config) async {
    final activeSuites =
        config.suites.where((s) => suites.contains(s)).toList();
    if (activeSuites.isEmpty) {
      debugBuf.writeln('No active suites for config ${config.name}, skipping.');
      return (config: config, testCases: <Map<String, dynamic>>[]);
    }
    final jsonOutputPath = '$outputDir/test_metadata_${config.name}.json';
    final processArgs = [
      exporterPath,
      '-m',
      config.mode,
      '-c',
      config.compiler,
      '-r',
      config.runtime,
      '--dump-test-metadata=$jsonOutputPath',
      '--build-directory=$outputDir/out/${config.name}',
      '--list',
      ...config.extraFlags,
      ...activeSuites,
    ];
    debugBuf.writeln(
      'Running discovery for ${config.name}: $dartPath ${processArgs.join(' ')}',
    );
    final env = Map<String, String>.from(Platform.environment);
    if (co19Dir != null) {
      env['DART_CO19_SRC'] = co19Dir;
    }
    final res = await Process.run(dartPath, processArgs, environment: env);
    if (res.exitCode != 0) {
      throw Exception(
        'Failed to dump metadata for ${config.name}:\n${res.stderr}\n${res.stdout}',
      );
    }
    final jsonFile = File(jsonOutputPath);
    if (!jsonFile.existsSync()) {
      throw Exception(
        'Metadata file not created for ${config.name} at $jsonOutputPath',
      );
    }
    final content = jsonFile.readAsStringSync();
    final dynamic decoded = jsonDecode(content);
    final testCases = List<Map<String, dynamic>>.from(
      decoded.map((dynamic x) => x as Map<String, dynamic>),
    );
    jsonFile.deleteSync();
    return (config: config, testCases: testCases);
  });

  List<_ConfigResult> results;
  try {
    results = await Future.wait(futures);
  } catch (e) {
    debugBuf.writeln('Error during parallel discovery: $e');
    debugLog.writeAsStringSync(debugBuf.toString());
    exitCode = 2;
    return;
  }

  // 3. Populate subDirToPkgDir mapping for all test cases across all configurations
  for (final res in results) {
    final configName = res.config.name;
    final generatedPrefix = '$outputDir/out/$configName/generated_tests/';
    for (final tc in res.testCases) {
      final name = tc['name'] as String;
      if (name == 'standalone/check_for_aot_snapshot_jit_test') continue;

      final parts = name.split('/');
      String pkgDir;
      const coarseSuites = {'corelib', 'standalone', 'ffi', 'language', 'co19'};
      if (parts.isNotEmpty && coarseSuites.contains(parts[0])) {
        pkgDir = parts[0];
      } else if (parts.length >= 2) {
        pkgDir = '${parts[0]}/${parts[1]}';
      } else {
        pkgDir = '${parts[0]}/misc';
      }

      final filePathAbs = tc['file_path'] as String;
      if (filePathAbs.startsWith(generatedPrefix)) {
        final relativeToGenerated = filePathAbs.substring(
          generatedPrefix.length,
        );
        final norm = relativeToGenerated.replaceAll('\\', '/');
        final parts = norm.split('/');
        if (parts.isNotEmpty) {
          final String key;
          if (parts[0].startsWith('custom-') && parts.length >= 2) {
            key = parts[1];
          } else {
            key = parts[0];
          }
          subDirToPkgDir[key] = pkgDir;
        }
      } else if (filePathAbs.startsWith('$workspaceDir${p.separator}')) {
        final relative = filePathAbs.substring(
          '$workspaceDir${p.separator}'.length,
        );
        final norm = relative.replaceAll('\\', '/');
        final dotIndex = norm.lastIndexOf('.');
        final pathWithoutExt =
            dotIndex != -1 ? norm.substring(0, dotIndex) : norm;
        final key = pathWithoutExt.replaceAll('/', '_');
        subDirToPkgDir[key] = pkgDir;
      }
    }
  }

  // 4. Move generated files to configuration-specific package subdirectories and group
  final packageGroups = <String, Map<String, List<Map<String, dynamic>>>>{};
  for (final res in results) {
    final configName = res.config.name;
    for (final tc in res.testCases) {
      final name = tc['name'] as String;
      if (name == 'standalone/check_for_aot_snapshot_jit_test') continue;

      final parts = name.split('/');
      String pkgDir;
      const coarseSuites = {'corelib', 'standalone', 'ffi', 'language', 'co19'};
      if (parts.isNotEmpty && coarseSuites.contains(parts[0])) {
        pkgDir = parts[0];
      } else if (parts.length >= 2) {
        pkgDir = '${parts[0]}/${parts[1]}';
      } else {
        pkgDir = '${parts[0]}/misc';
      }

      // Move generated files
      final filePathAbs = tc['file_path'] as String;
      final generatedPrefix = '$outputDir/out/$configName/generated_tests/';
      if (filePathAbs.startsWith(generatedPrefix)) {
        final relativeToGenerated = filePathAbs.substring(
          generatedPrefix.length,
        );
        final slashIndex = relativeToGenerated.indexOf('/');
        final relativePathFromSuite = relativeToGenerated.substring(
          slashIndex + 1,
        );

        final destDir = '$outputDir/$pkgDir/gen_tests/$configName';
        final destPath = '$destDir/$relativePathFromSuite';

        Directory(p.dirname(destPath)).createSync(recursive: true);
        final file = File(filePathAbs);
        if (file.existsSync()) {
          file.renameSync(destPath);
        }

        tc['file_path'] = destPath;

        // Update arguments in commands
        final commands = tc['commands'] as List;
        for (final cmd in commands) {
          if (cmd is Map) {
            final args = cmd['arguments'] as List?;
            if (args != null) {
              for (var i = 0; i < args.length; i++) {
                if (args[i] == filePathAbs) {
                  args[i] = destPath;
                } else if (args[i].toString().contains(filePathAbs)) {
                  args[i] = args[i].toString().replaceAll(
                        filePathAbs,
                        destPath,
                      );
                }
              }
            }
          }
        }
      }

      packageGroups
          .putIfAbsent(pkgDir, () => {})
          .putIfAbsent(configName, () => [])
          .add(tc);
    }

    // Move any remaining auxiliary files in out/ to their destinations
    final genDir = Directory('$outputDir/out/$configName/generated_tests');
    if (genDir.existsSync()) {
      for (final entity in genDir.listSync(recursive: true)) {
        if (entity is File) {
          final filePathAbs = entity.path.replaceAll('\\', '/');
          final relativeToGenerated = filePathAbs.substring(
            genDir.path.length + 1,
          );
          final parts = relativeToGenerated.split('/');

          final String flatName;
          final String relativePath;

          if (parts[0].startsWith('custom-') && parts.length >= 2) {
            flatName = parts[1];
            relativePath = parts.length > 2 ? parts.sublist(2).join('/') : '';
          } else {
            flatName = parts[0];
            relativePath = parts.length > 1 ? parts.sublist(1).join('/') : '';
          }

          var pkgDir = subDirToPkgDir[flatName];
          if (pkgDir == null) {
            var strippedName = flatName;
            if (flatName.startsWith('tests_')) {
              strippedName = flatName.substring('tests_'.length);
            } else if (flatName.startsWith('multitest_')) {
              strippedName = flatName.substring('multitest_'.length);
            }
            pkgDir = subDirToPkgDir[strippedName];
          }
          pkgDir ??= _getPkgDirFromFlatName(flatName);

          final destPath =
              '$outputDir/$pkgDir/gen_tests/$configName/$relativePath';

          Directory(p.dirname(destPath)).createSync(recursive: true);
          entity.renameSync(destPath);
        }
      }
      try {
        genDir.deleteSync(recursive: true);
        final configOutDir = Directory('$outputDir/out/$configName');
        if (configOutDir.existsSync() && configOutDir.listSync().isEmpty) {
          configOutDir.deleteSync();
        }
        final outDir = Directory('$outputDir/out');
        if (outDir.existsSync() && outDir.listSync().isEmpty) {
          outDir.deleteSync();
        }
      } catch (_) {}
    }
  }

  // 4. Write directory BUILD.bazel and tests_metadata_<config>.json files
  for (final entry in packageGroups.entries) {
    final pkgDir = entry.key;
    final normalizedPkgDir = pkgDir.replaceAll('\\', '/');

    final configsMap = entry.value;
    final packageWorkspaceFiles = <String>{};

    // Ensure package directory exists
    Directory('$outputDir/$pkgDir').createSync(recursive: true);

    final suiteSourceDir = getSuiteSourceDir(workspaceDir, pkgDir, co19Dir);
    final testImportsFile = File('$suiteSourceDir/test_imports.json');
    final hasFineGrained = testImportsFile.existsSync();
    final useIndividualTargets = hasFineGrained;

    Map<String, dynamic>? testImportsMap;
    if (hasFineGrained) {
      testImportsMap = jsonDecode(
        testImportsFile.readAsStringSync(),
      ) as Map<String, dynamic>;
    }

    final filegroups = <String, Set<String>>{};

    // Package-wide resources (config-independent)
    if (hasFineGrained) {
      final resources = _findPackageResources(workspaceDir, pkgDir, co19Dir);
      if (resources.isNotEmpty) {
        final fgName = 'fg_package_resources';
        for (final res in resources) {
          final label = res.startsWith('@')
              ? res
              : _resolveWorkspaceLabel(workspaceDir, res);
          filegroups.putIfAbsent(fgName, () => {}).add(label);
        }
      }
    }

    final pubspecPath = '$workspaceDir/$pkgDir/pubspec.yaml';
    final pubspecDeps = _parsePubspecDependencies(pubspecPath, debugBuf);

    final parts = pkgDir.split('/');
    final pkgName = parts.length >= 2 ? parts[1] : null;

    final individualTargets = <String>[];
    final shardedTargets = <String>[];

    for (final configEntry in configsMap.entries) {
      final configName = configEntry.key;
      final cases = configEntry.value;
      final config = _configs.firstWhere((c) => c.name == configName);

      // Compute baseline deps for this config
      final baselineDeps = <String>{
        ':tests_metadata_$configName.json',
        '@//:test_package_sources',
        '@//:package_config_json',
        '@dart_packages//:package_config_json',
        config.compiler == 'ddc'
            ? '@//pkg/test_runner/bin:run_ddc_test.dart'
            : '@//pkg/test_runner/bin:run_single_test.dart',
      };

      if (config.runtime == 'vm' ||
          config.compiler == 'dart2analyzer' ||
          config.compiler == 'fasta') {
        baselineDeps.addAll([
          '@prebuilt_dart_sdk//:bin/dart',
          '@prebuilt_dart_sdk//:sdk_files',
        ]);
        if (config.runtime == 'vm') {
          baselineDeps.add('@//runtime/vm:vm_platform');
        }
      } else if (config.compiler == 'ddc') {
        baselineDeps.addAll([
          '@//runtime/bin:dartvm',
          '@prebuilt_dart_sdk//:sdk_files',
          '@//utils/ddc:dartdevc',
          '@//utils/ddc:ddc_outline.dill',
          '@//utils/ddc:ddc_stable_test_pkg',
          '@//utils/ddc:ddc_stable_sdk',
          '@//:third_party/requirejs/require.js',
          '@//:pkg/dev_compiler/lib/js/ddc/ddc_module_loader.js',
          '@//:test_package_sources',
        ]);
      } else {
        baselineDeps.add('@//sdk:create_sdk');
      }

      if (filegroups.containsKey('fg_package_resources')) {
        baselineDeps.add(':fg_package_resources');
      }

      // Add pubspec deps
      for (final dep in pubspecDeps) {
        if (dep == pkgName) continue;
        baselineDeps.add('@dart_packages//pkg/$dep');

        final toolEntryPoints = {
          'analyzer_cli': '@//:pkg/analyzer_cli/bin/analyzer.dart',
          'front_end': '@//:pkg/front_end/tool/compile.dart',
          'analysis_server': '@//:pkg/analysis_server/bin/server.dart',
          'frontend_server':
              '@//:pkg/frontend_server/bin/frontend_server_starter.dart',
          'dartdev': '@//:pkg/dartdev/bin/dartdev.dart',
          'dds': '@//:pkg/dds/bin/dds.dart',
        };
        final entryPoint = toolEntryPoints[dep];
        if (entryPoint != null) {
          baselineDeps.add(entryPoint);
        }

        final toolExtraPackages = {
          'analyzer_cli': {
            '@dart_packages//pkg/analyzer',
            '@dart_packages//pkg/convert',
            '@dart_packages//pkg/glob',
            '@dart_packages//pkg/pub_semver',
            '@dart_packages//pkg/source_span',
            '@dart_packages//pkg/watcher',
            '@dart_packages//pkg/yaml',
          },
          'analyzer': {
            '@dart_packages//pkg/convert',
            '@dart_packages//pkg/glob',
            '@dart_packages//pkg/pub_semver',
            '@dart_packages//pkg/source_span',
            '@dart_packages//pkg/watcher',
            '@dart_packages//pkg/yaml',
          },
        };
        final extraPkgs = toolExtraPackages[dep];
        if (extraPkgs != null) {
          baselineDeps.addAll(extraPkgs);
        }
      }

      if (config.compiler == 'fasta' ||
          config.compiler == 'dartkp' ||
          config.name.contains('sim')) {
        baselineDeps.addAll({
          '@//:front_end_tool_files',
          '@//:compile_platform_tool',
          '@//runtime/vm:vm_platform',
        });
      }

      if (config.runtime == 'd8' || config.compiler == 'dart2wasm') {
        baselineDeps.addAll({
          '@//third_party/d8:d8_files',
          '@//:pkg/dart2wasm/bin/run_wasm.js',
        });
      }

      for (final bEntry in extraBaselineDeps.entries) {
        if (normalizedPkgDir == bEntry.key ||
            normalizedPkgDir.endsWith('/${bEntry.key}')) {
          baselineDeps.addAll(bEntry.value);
        }
      }

      if ([
        'chrome',
        'chromeOnAndroid',
        'chromedriver',
      ].contains(config.runtime)) {
        baselineDeps.addAll({
          '@chrome//:chrome_files',
          '@chromedriver//:chromedriver_files',
        });
      } else if (['firefox', 'jsshell'].contains(config.runtime)) {
        baselineDeps.add('@firefox//:firefox_files');
      } else if (config.runtime == 'firefox_jsshell') {
        if (Directory(
          '$workspaceDir/third_party/firefox_jsshell',
        ).existsSync()) {
          baselineDeps.add(
            '@//third_party/firefox_jsshell:firefox_jsshell_files',
          );
        }
      }

      final enrichedCases = <Map<String, dynamic>>[];
      final seenTargets = <String>{};
      final workspaceFiles = <String>{};
      final otherDeps = <String>{};

      for (final tc in cases) {
        final filePathAbs = tc['file_path'] as String;
        String testFileLabel;
        String relativePath;

        if (filePathAbs.startsWith(workspaceDir)) {
          relativePath = filePathAbs.substring(workspaceDir.length + 1);
          testFileLabel = _resolveWorkspaceLabel(workspaceDir, relativePath);
        } else if (co19Dir != null && filePathAbs.startsWith(co19Dir)) {
          relativePath = filePathAbs.substring(co19Dir.length + 1);
          testFileLabel = '@dart_co19_tests//:$relativePath';
        } else if (filePathAbs.startsWith('$outputDir/$pkgDir/gen_tests/')) {
          relativePath = filePathAbs.substring('$outputDir/$pkgDir/'.length);
          testFileLabel = ':$relativePath';
        } else if (filePathAbs.startsWith(outputDir)) {
          relativePath = filePathAbs.substring(outputDir.length + 1);
          testFileLabel = '//:$relativePath';
        } else {
          continue;
        }

        // Map test-declared shared objects dynamically
        var hasUnsupportedSo = false;
        final sharedObjects = List<String>.from(
          tc['shared_objects'] as List? ?? [],
        );
        final activeSoDeps = <String>{};
        if (config.runtime != 'none') {
          for (final so in sharedObjects) {
            if (so == 'ffi_test_functions') {
              activeSoDeps.add('@//runtime/bin:libffi_test_functions.so');
            } else if (so == 'ffi_test_dynamic_library') {
              activeSoDeps.add('@//runtime/bin:libffi_test_dynamic_library.so');
            } else if (so == 'ffi_native_test_module') {
              activeSoDeps
                  .add('@//utils/dart2wasm:ffi_native_test_wasm_module');
            } else {
              hasUnsupportedSo = true;
              break;
            }
          }
          if (hasUnsupportedSo) continue;

          final relativePathForChecks = filePathAbs.startsWith(workspaceDir)
              ? filePathAbs.substring(workspaceDir.length + 1)
              : filePathAbs.substring(outputDir.length + 1);
          if (relativePathForChecks.contains('socket_sigpipe_test') ||
              relativePathForChecks.contains('/ffi/')) {
            activeSoDeps.add('@//runtime/bin:libffi_test_functions.so');
            activeSoDeps.add('@//runtime/bin:libffi_test_dynamic_library.so');
          }
        }

        // Enrich and add test case copy
        final tcCopy = Map<String, dynamic>.from(tc);
        tcCopy['relative_file_path'] = relativePath;
        tcCopy['compiler'] = config.compiler;
        enrichedCases.add(tcCopy);

        final origFilePath = tc['original_file_path'] as String? ?? filePathAbs;
        final testDir = File(origFilePath).parent.path;
        final otherResources = List<String>.from(
          tc['other_resources'] as List? ?? [],
        );
        final resolvedResources = <String>{};
        final resourceDeps = <String>{};

        for (final resource in otherResources) {
          final resourcePath = p.posix.normalize('$testDir/$resource');
          if (resourcePath.startsWith(workspaceDir)) {
            final relResPath = resourcePath.substring(workspaceDir.length + 1);
            resolvedResources.add(
              _resolveWorkspaceLabel(workspaceDir, relResPath),
            );
            if (hasFineGrained) {
              final relResInPkg = relResPath.substring(pkgDir.length + 1);
              final resDeps = _computeTransitiveClosure(
                relResInPkg,
                testImportsMap!,
              );
              final suiteSourceDir =
                  getSuiteSourceDir(workspaceDir, pkgDir, co19Dir);
              final suiteRelPrefix = getSuiteRelPrefix(pkgDir);
              for (final dep in resDeps) {
                if (!File('$suiteSourceDir/$dep').existsSync() &&
                    !Directory('$suiteSourceDir/$dep').existsSync()) {
                  continue;
                }
                final fgName = _getFilegroupTargetName(dep);
                final label = pkgDir == 'co19'
                    ? '@dart_co19_tests//:$dep'
                    : _resolveWorkspaceLabel(
                        workspaceDir,
                        '$suiteRelPrefix/$dep',
                      );
                filegroups.putIfAbsent(fgName, () => {}).add(label);
                resourceDeps.add(':$fgName');
              }
            }
          } else if (resourcePath.startsWith(outputDir)) {
            final relResPath = resourcePath.substring(outputDir.length + 1);
            resolvedResources.add('//:$relResPath');
          }
        }

        if (useIndividualTargets) {
          String relPathInPkg;
          if (const {
            'corelib',
            'standalone',
            'ffi',
            'language',
          }.contains(pkgDir)) {
            if (relativePath.startsWith('tests/')) {
              relPathInPkg = relativePath.substring(
                'tests/'.length + pkgDir.length + 1,
              );
            } else {
              final pkgIndex = relativePath.indexOf('$pkgDir/');
              if (pkgIndex != -1) {
                relPathInPkg = relativePath.substring(
                  pkgIndex + pkgDir.length + 1,
                );
              } else {
                relPathInPkg = relativePath.substring(pkgDir.length + 1);
              }
            }
          } else {
            relPathInPkg = relativePath.substring(pkgDir.length + 1);
          }
          final targetName = '${_toTargetName(relPathInPkg)}_$configName';

          if (seenTargets.add(targetName)) {
            final targetDeps = <String>{
              ...baselineDeps,
              testFileLabel,
              ...activeSoDeps,
              ...resolvedResources,
              ...resourceDeps,
            };

            final normalizedPath = relPathInPkg.replaceAll('\\', '/');
            for (final gEntry in globalExtraDepsByPattern.entries) {
              if (_matchesPattern(normalizedPath, gEntry.key)) {
                targetDeps.addAll(gEntry.value);
              }
            }

            for (final pEntry in extraDepsByPattern.entries) {
              if (normalizedPkgDir == pEntry.key ||
                  normalizedPkgDir.endsWith('/${pEntry.key}')) {
                for (final patEntry in pEntry.value.entries) {
                  if (_matchesPattern(normalizedPath, patEntry.key)) {
                    targetDeps.addAll(patEntry.value);
                  }
                }
              }
            }

            if (hasFineGrained) {
              if (testImportsMap!.containsKey(relPathInPkg)) {
                final localDeps = _computeTransitiveClosure(
                  relPathInPkg,
                  testImportsMap,
                );
                final suiteSourceDir =
                    getSuiteSourceDir(workspaceDir, pkgDir, co19Dir);
                final suiteRelPrefix = getSuiteRelPrefix(pkgDir);
                for (final dep in localDeps) {
                  if (!File('$suiteSourceDir/$dep').existsSync() &&
                      !Directory('$suiteSourceDir/$dep').existsSync()) {
                    continue;
                  }
                  final fgName = _getFilegroupTargetName(dep);
                  final label = pkgDir == 'co19'
                      ? '@dart_co19_tests//:$dep'
                      : _resolveWorkspaceLabel(
                          workspaceDir,
                          '$suiteRelPrefix/$dep',
                        );
                  filegroups.putIfAbsent(fgName, () => {}).add(label);
                  targetDeps.add(':$fgName');
                }
              } else {
                // Fallback: add all files in the same directory as the test to _main
                // so that relative imports resolve.
                final testDir = p.dirname(filePathAbs);
                final dir = Directory(testDir);
                if (dir.existsSync()) {
                  for (final entity
                      in dir.listSync(recursive: true, followLinks: false)) {
                    if (entity is File) {
                      final fileAbs = entity.path;
                      if (p.isWithin(workspaceDir, fileAbs)) {
                        final fileRelNative =
                            p.relative(fileAbs, from: workspaceDir);
                        final fileRel = p.posix.joinAll(p.split(fileRelNative));
                        targetDeps.add('@//:$fileRel');
                      }
                    }
                  }
                }
                // And also depend on the whole package from virtual repo (all files)
                // for runtime reads via packageRoot.
                if (pkgDir.startsWith('pkg/') && pkgName != null) {
                  targetDeps.add(
                    '@dart_packages//pkg/$pkgName:sdk_package_sources',
                  );
                }
              }
            }

            if (pkgName != null) {
              targetDeps.add('@dart_packages//pkg/$pkgName');
            }

            final targetDepsStr =
                targetDeps.map((d) => '        "$d"').join(',\n');
            var runnerScript = config.compiler == 'ddc'
                ? '//:run_ddc_test.sh'
                : '//:run_single_test.sh';

            var isMetaTest = false;
            for (final mEntry in manualPatterns.entries) {
              if (normalizedPkgDir == mEntry.key ||
                  normalizedPkgDir.endsWith('/${mEntry.key}')) {
                for (final pattern in mEntry.value) {
                  if (_matchesPattern(normalizedPath, pattern)) {
                    isMetaTest = true;
                    break;
                  }
                }
                if (isMetaTest) break;
              }
            }

            var isQuarantined = false;
            for (final qEntry in quarantinePatterns.entries) {
              if (normalizedPkgDir == qEntry.key ||
                  normalizedPkgDir.endsWith('/${qEntry.key}')) {
                for (final pattern in qEntry.value) {
                  if (_matchesPattern(normalizedPath, pattern)) {
                    isQuarantined = true;
                    break;
                  }
                }
                if (isQuarantined) break;
              }
            }

            String? targetTimeout;
            for (final tEntry in timeoutsByPattern.entries) {
              if (normalizedPkgDir == tEntry.key ||
                  normalizedPkgDir.endsWith('/${tEntry.key}')) {
                for (final patEntry in tEntry.value.entries) {
                  if (_matchesPattern(normalizedPath, patEntry.key)) {
                    targetTimeout = patEntry.value;
                    break;
                  }
                }
                if (targetTimeout != null) break;
              }
            }

            final tagsList = <String>[];
            if (isQuarantined) {
              tagsList.add('quarantine');
              tagsList.add('manual');
            } else if (isMetaTest) {
              tagsList.add('manual');
            }
            final tagsAttr = tagsList.isNotEmpty
                ? '\n    tags = [${tagsList.map((t) => '"$t"').join(', ')}],'
                : '';
            final timeoutAttr = targetTimeout != null
                ? '\n    timeout = "$targetTimeout",'
                : '';

            individualTargets.add('''sh_test(
    name = "$targetName",$tagsAttr$timeoutAttr
    srcs = ["$runnerScript"],
    data = [
$targetDepsStr
    ],
    args = [
        "--config-json=\$(location :tests_metadata_$configName.json)",
        "--run-only=$relPathInPkg",
    ],
)''');
          }
        } else {
          if (filePathAbs.startsWith(workspaceDir) ||
              (co19Dir != null && filePathAbs.startsWith(co19Dir))) {
            workspaceFiles.add(testFileLabel);
            packageWorkspaceFiles.add(testFileLabel);
          }
          otherDeps.addAll(activeSoDeps);
          otherDeps.addAll(resolvedResources);
        }
      }

      if (enrichedCases.isNotEmpty) {
        for (final tc in enrichedCases) {
          tc['file_path'] =
              _sanitizePath(tc['file_path'] as String, workspaceDir, co19Dir);
          if (tc['original_file_path'] != null) {
            tc['original_file_path'] = _sanitizePath(
                tc['original_file_path'] as String, workspaceDir, co19Dir);
          }
          final commands = tc['commands'] as List;
          for (final cmd in commands) {
            if (cmd is Map) {
              if (cmd['working_directory'] != null) {
                cmd['working_directory'] = _sanitizePath(
                    cmd['working_directory'] as String, workspaceDir, co19Dir);
              }
              final args = cmd['arguments'] as List?;
              if (args != null) {
                for (var i = 0; i < args.length; i++) {
                  args[i] =
                      _sanitizePath(args[i].toString(), workspaceDir, co19Dir);
                }
              }
              final env = cmd['environment'] as Map?;
              if (env != null) {
                for (final key in env.keys) {
                  env[key] =
                      _sanitizePath(env[key].toString(), workspaceDir, co19Dir);
                }
              }
            }
          }
        }
        final pkgJson = File(
          '$outputDir/$pkgDir/tests_metadata_$configName.json',
        );
        pkgJson.writeAsStringSync(jsonEncode(enrichedCases));

        if (!useIndividualTargets) {
          if (pkgDir.startsWith('pkg/') && pkgName != null) {
            otherDeps.add('@dart_packages//pkg/$pkgName');
          }

          final baselineDepsSet = baselineDeps
              .where((d) => !d.startsWith(':tests_metadata'))
              .toSet();
          baselineDepsSet.addAll(otherDeps);
          if (pkgDir == 'co19') {
            baselineDepsSet.add('@dart_co19_tests//:co19_files');
          }
          final baselineDepsList = baselineDepsSet.toList()..sort();

          final dataListStr =
              baselineDepsList.map((d) => '        "$d",').join('\n');

          var shardCount = enrichedCases.length ~/ 12;
          if (shardCount < 1) {
            shardCount = 1;
          } else if (shardCount > maxShards) {
            shardCount = maxShards;
          }
          var runnerScript = config.compiler == 'ddc'
              ? '//:run_ddc_test.sh'
              : '//:run_single_test.sh';
          final dataRule = pkgDir == 'co19'
              ? '    data = [\n        ":workspace_files",\n        ":tests_metadata_$configName.json",\n$dataListStr\n    ],'
              : '    data = glob(["gen_tests/$configName/**/*.dart", "gen_tests/$configName/**/*.html"], allow_empty = True) + [\n        ":workspace_files",\n        ":tests_metadata_$configName.json",\n$dataListStr\n    ],';
          final envRule = pkgDir == 'co19'
              ? '\n    env = {\n        "DART_CO19_SRC": "../dart_co19_tests",\n    },'
              : '';
          shardedTargets.add('''sh_test(
    name = "tests_$configName",
    srcs = ["$runnerScript"],
$dataRule$envRule
    args = ["--config-json=\$(location :tests_metadata_$configName.json)"],
    shard_count = $shardCount,
)''');
        }
      }
    }

    final pkgBuild = File('$outputDir/$pkgDir/BUILD.bazel');

    final filegroupsStr = StringBuffer();
    if (hasFineGrained) {
      final sortedFgNames = filegroups.keys.toList()..sort();
      for (final fgName in sortedFgNames) {
        final srcs = filegroups[fgName]!.toList()..sort();
        final srcsStr = srcs.map((s) => '        "$s"').join(',\n');
        filegroupsStr.writeln('''filegroup(
    name = "$fgName",
    srcs = [
$srcsStr
    ],
)
''');
      }
    }

    if (useIndividualTargets) {
      if (individualTargets.isNotEmpty) {
        final targetsStr = individualTargets.join('\n\n');
        pkgBuild.writeAsStringSync(
          '''load("@rules_shell//shell:sh_test.bzl", "sh_test")

$filegroupsStr

$targetsStr
''',
        );
      }
    } else {
      if (shardedTargets.isNotEmpty) {
        final String workspaceFilesRule;
        if (pkgDir == 'co19') {
          workspaceFilesRule = '''filegroup(
    name = "workspace_files",
    srcs = [
        "@//:tests/co19/co19-analyzer.status",
        "@//:tests/co19/co19-co19.status",
        "@//:tests/co19/co19-dart2js.status",
        "@//:tests/co19/co19-dart2wasm.status",
        "@//:tests/co19/co19-dartdevc.status",
        "@//:tests/co19/co19-kernel.status",
        "@//:tests/co19/co19-runtime.status",
    ],
)''';
        } else {
          final sortedWorkspaceFiles = packageWorkspaceFiles.toList()..sort();
          final workspaceFilesStr =
              sortedWorkspaceFiles.map((f) => '        "$f",').join('\n');
          workspaceFilesRule = '''filegroup(
    name = "workspace_files",
    srcs = [
$workspaceFilesStr
    ],
)''';
        }

        final targetsStr = shardedTargets.join('\n\n');
        pkgBuild.writeAsStringSync(
          '''load("@rules_shell//shell:sh_test.bzl", "sh_test")

$workspaceFilesRule

$targetsStr
''',
        );
      }
    }
  }

  // Write root BUILD.bazel with explicit exports to avoid expensive globbing
  final rootBuild = File('$outputDir/BUILD.bazel');
  rootBuild.writeAsStringSync('''exports_files([
        "run_single_test.sh",
        "run_ddc_test.sh",
])
''');

  debugBuf.writeln('=== Generation Completed Successfully ===');
  debugLog.writeAsStringSync(debugBuf.toString());
  return;
}

typedef _TestConfig = ({
  String name,
  String mode,
  String compiler,
  String runtime,
  List<String> suites,
  List<String> extraFlags,
});

const _configs = <_TestConfig>[
  (
    name: 'vm_release',
    mode: 'release',
    compiler: 'dartk',
    runtime: 'vm',
    suites: ['language', 'corelib', 'standalone', 'ffi', 'pkg', 'co19'],
    extraFlags: [],
  ),
  (
    name: 'vm_debug',
    mode: 'debug',
    compiler: 'dartk',
    runtime: 'vm',
    suites: ['language', 'corelib', 'standalone'],
    extraFlags: [],
  ),
  (
    name: 'vm_product',
    mode: 'product',
    compiler: 'dartk',
    runtime: 'vm',
    suites: ['language', 'corelib', 'standalone', 'ffi'],
    extraFlags: [],
  ),
  (
    name: 'wasm_release',
    mode: 'release',
    compiler: 'dart2wasm',
    runtime: 'd8',
    suites: ['language', 'corelib', 'web/wasm', 'co19'],
    extraFlags: [],
  ),
  (
    name: 'wasm_asserts',
    mode: 'release',
    compiler: 'dart2wasm',
    runtime: 'd8',
    suites: ['language', 'corelib', 'web/wasm'],
    extraFlags: ['--enable-asserts', '--dart2wasm-options=-O0'],
  ),
  (
    name: 'wasm_optimized',
    mode: 'release',
    compiler: 'dart2wasm',
    runtime: 'd8',
    suites: ['language', 'corelib', 'web/wasm'],
    extraFlags: ['--dart2wasm-options=-O1'],
  ),
  (
    name: 'wasm_chrome_release',
    mode: 'release',
    compiler: 'dart2wasm',
    runtime: 'chrome',
    suites: ['language', 'corelib', 'web/wasm'],
    extraFlags: [],
  ),
  (
    name: 'wasm_chrome_asserts',
    mode: 'release',
    compiler: 'dart2wasm',
    runtime: 'chrome',
    suites: ['language', 'corelib', 'web/wasm'],
    extraFlags: ['--enable-asserts', '--dart2wasm-options=-O0'],
  ),
  (
    name: 'wasm_chrome_optimized',
    mode: 'release',
    compiler: 'dart2wasm',
    runtime: 'chrome',
    suites: ['language', 'corelib', 'web/wasm'],
    extraFlags: ['--dart2wasm-options=-O1'],
  ),
  (
    name: 'wasm_firefox_release',
    mode: 'release',
    compiler: 'dart2wasm',
    runtime: 'firefox',
    suites: ['language', 'corelib', 'web/wasm'],
    extraFlags: [],
  ),
  (
    name: 'wasm_firefox_asserts',
    mode: 'release',
    compiler: 'dart2wasm',
    runtime: 'firefox',
    suites: ['language', 'corelib', 'web/wasm'],
    extraFlags: ['--enable-asserts', '--dart2wasm-options=-O0'],
  ),
  (
    name: 'dart2js_chrome_release',
    mode: 'release',
    compiler: 'dart2js',
    runtime: 'chrome',
    suites: ['language', 'corelib', 'web/wasm', 'co19'],
    extraFlags: [],
  ),
  (
    name: 'ddc_chrome_release',
    mode: 'release',
    compiler: 'ddc',
    runtime: 'chrome',
    suites: ['language', 'corelib', 'co19'],
    extraFlags: [],
  ),
  (
    name: 'dart2js_firefox_release',
    mode: 'release',
    compiler: 'dart2js',
    runtime: 'firefox',
    suites: ['language', 'corelib', 'web/wasm'],
    extraFlags: [],
  ),
  (
    name: 'cfe_release',
    mode: 'release',
    compiler: 'fasta',
    runtime: 'none',
    suites: ['language', 'corelib', 'standalone', 'ffi'],
    extraFlags: [],
  ),
  (
    name: 'vm_aot_release',
    mode: 'release',
    compiler: 'dartkp',
    runtime: 'dart_precompiled',
    suites: ['language', 'corelib', 'standalone', 'co19'],
    extraFlags: [],
  ),
  (
    name: 'vm_release_simarm',
    mode: 'release',
    compiler: 'dartk',
    runtime: 'vm',
    suites: ['language', 'corelib', 'standalone', 'ffi'],
    extraFlags: ['--arch=simarm'],
  ),
  (
    name: 'vm_aot_release_simarm',
    mode: 'release',
    compiler: 'dartkp',
    runtime: 'dart_precompiled',
    suites: ['language', 'corelib', 'standalone'],
    extraFlags: ['--arch=simarm', '--gen-snapshot-format=elf'],
  ),
  (
    name: 'vm_release_simarm64',
    mode: 'release',
    compiler: 'dartk',
    runtime: 'vm',
    suites: ['language', 'corelib', 'standalone', 'ffi'],
    extraFlags: ['--arch=simarm64'],
  ),
  (
    name: 'vm_aot_release_simarm64',
    mode: 'release',
    compiler: 'dartkp',
    runtime: 'dart_precompiled',
    suites: ['language', 'corelib', 'standalone'],
    extraFlags: ['--arch=simarm64', '--gen-snapshot-format=elf'],
  ),
  (
    name: 'vm_release_simriscv64',
    mode: 'release',
    compiler: 'dartk',
    runtime: 'vm',
    suites: ['language', 'corelib', 'standalone', 'ffi'],
    extraFlags: ['--arch=simriscv64'],
  ),
  (
    name: 'vm_aot_release_simriscv64',
    mode: 'release',
    compiler: 'dartkp',
    runtime: 'dart_precompiled',
    suites: ['language', 'corelib', 'standalone'],
    extraFlags: ['--arch=simriscv64', '--gen-snapshot-format=elf'],
  ),
  (
    name: 'analyzer_release',
    mode: 'release',
    compiler: 'dart2analyzer',
    runtime: 'none',
    suites: ['co19'],
    extraFlags: [],
  ),
];

typedef _ConfigResult = ({
  _TestConfig config,
  List<Map<String, dynamic>> testCases,
});

final _buildDirCache = <String, bool>{};
final _labelCache = <String, String>{};

bool _dirHasBuildFile(String dirPath) {
  return _buildDirCache.putIfAbsent(dirPath, () {
    return File('$dirPath/BUILD.bazel').existsSync() ||
        File('$dirPath/BUILD').existsSync();
  });
}

String _resolveWorkspaceLabel(String workspaceDir, String relResPath) {
  return _labelCache.putIfAbsent(relResPath, () {
    final normPath = p.posix.normalize(relResPath);
    final dirname = p.posix.dirname(normPath);
    final dirParts = (dirname == '.' || dirname.isEmpty)
        ? <String>[]
        : p.posix.split(dirname);

    var bestI = 0;

    for (var i = 1; i <= dirParts.length; i++) {
      final pkgSubPath = p.posix.joinAll(dirParts.sublist(0, i));
      final pkgPath = '$workspaceDir/$pkgSubPath';
      if (_dirHasBuildFile(pkgPath)) {
        bestI = i;
      }
    }

    if (bestI == 0) {
      return '@//:$normPath';
    } else {
      final packageName = p.posix.joinAll(dirParts.sublist(0, bestI));
      final relToPackage = p.posix.relative(normPath, from: packageName);
      return '@//$packageName:$relToPackage';
    }
  });
}

String _toTargetName(String relPath) {
  return relPath
      .replaceAll('/', '_')
      .replaceAll('\\', '_')
      .replaceAll('.', '_');
}

String _getFilegroupTargetName(String depPath) {
  final norm = p.posix.normalize(depPath);
  final dir = p.posix.dirname(norm);
  if (dir == '.' || dir.isEmpty) {
    return 'fg_root_files';
  }
  final target = dir.replaceAll('/', '_');
  return 'fg_$target';
}

List<String> _findPackageResources(String workspaceDir, String pkgDir,
    [String? co19Dir]) {
  final resources = <String>[];
  final sourceDir = getSuiteSourceDir(workspaceDir, pkgDir, co19Dir);
  final dir = Directory(sourceDir);
  if (!dir.existsSync()) return resources;

  final allowedExtensions = {
    '.json',
    '.yaml',
    '.txt',
    '.status',
    '.properties',
    '.csv',
    '.xml',
    '.dill',
    '.snapshot',
    '.bin',
    '.dart_fn',
    '.wasm',
    '.so',
    '.dylib',
    '.dll',
    '.aot',
    '.exe',
    '.js',
    '.map',
    '.options',
    '.packages',
    '.isolate_kit',
  };

  for (final entity in dir.listSync(recursive: true)) {
    if (entity is File) {
      final path = entity.path.replaceAll('\\', '/');
      final parts = path.split('/');

      if (parts.any((p) => p.startsWith('.'))) continue;
      if (parts.contains('doc')) continue;

      final filename = parts.last;
      if (filename == 'BUILD' ||
          filename == 'BUILD.bazel' ||
          filename == 'OWNERS') {
        continue;
      }

      final dotIndex = filename.lastIndexOf('.');
      if (dotIndex != -1) {
        final ext = filename.substring(dotIndex).toLowerCase();
        final isAllowedExt = allowedExtensions.contains(ext);
        final isHelperDart = ext == '.dart' && !filename.endsWith('_test.dart');
        if (isAllowedExt || isHelperDart) {
          if (pkgDir == 'co19') {
            final relPath = path.substring(sourceDir.length + 1);
            resources.add('@dart_co19_tests//:$relPath');
          } else {
            final relPath = path.substring(workspaceDir.length + 1);
            resources.add(relPath);
          }
        }
      }
    }
  }
  return resources;
}

List<String> _computeTransitiveClosure(
  String startFile,
  Map<String, dynamic> directDepsMap,
) {
  final closure = <String>{};
  final visiting = <String>{startFile};

  void dfs(String node) {
    final deps = directDepsMap[node] as List?;
    if (deps == null) return;

    for (final dep in deps) {
      final depStr = dep as String;
      if (closure.contains(depStr)) continue;
      if (visiting.contains(depStr)) continue;

      closure.add(depStr);
      visiting.add(depStr);
      dfs(depStr);
      visiting.remove(depStr);
    }
  }

  dfs(startFile);
  return closure.toList()..sort();
}

Set<String> _parsePubspecDependencies(
  String pubspecPath,
  StringBuffer debugBuf,
) {
  final deps = <String>{};
  final file = File(pubspecPath);
  if (!file.existsSync()) {
    return deps;
  }

  var inDepsSection = false;
  for (var line in file.readAsLinesSync()) {
    final trimmed = line.trim();
    if (trimmed.startsWith('#')) continue;

    if (trimmed == 'dependencies:' || trimmed == 'dev_dependencies:') {
      inDepsSection = true;
      continue;
    }

    if (inDepsSection) {
      if (line.isEmpty) continue;

      if (!line.startsWith(' ') && !line.startsWith('\t')) {
        inDepsSection = false;
        if (line.startsWith('dependencies:') ||
            line.startsWith('dev_dependencies:')) {
          inDepsSection = true;
        }
        continue;
      }

      final leadingSpaces = line.length - line.trimLeft().length;
      if (leadingSpaces > 3) {
        continue;
      }

      final parts = trimmed.split(':');
      if (parts.isNotEmpty) {
        final depName = parts[0].trim();
        if (depName.isNotEmpty) {
          deps.add(depName);
        }
      }
    }
  }
  return deps;
}

String _getPkgDirFromFlatName(String flatName) {
  var name = flatName;
  if (name.startsWith('tests_')) {
    name = name.substring('tests_'.length);
  } else if (name.startsWith('multitest_')) {
    name = name.substring('multitest_'.length);
  }

  final parts = name.split('_');
  const coarseSuites = {'corelib', 'standalone', 'ffi', 'language', 'co19'};
  if (parts.isNotEmpty && coarseSuites.contains(parts[0])) {
    return parts[0];
  } else if (parts.length >= 2) {
    return '${parts[0]}/${parts[1]}';
  } else {
    return '${parts[0]}/misc';
  }
}

String _sanitizePath(String path, String workspaceDir, String? co19Dir) {
  String toPosix(String relPath) {
    return p.posix.joinAll(p.split(relPath));
  }

  if (co19Dir != null) {
    if (path == co19Dir) return r'$CO19_ROOT';
    if (p.isWithin(co19Dir, path)) {
      final rel = p.relative(path, from: co19Dir);
      final relPosix = toPosix(rel);
      return relPosix == '.'
          ? r'$CO19_ROOT'
          : p.posix.join(r'$CO19_ROOT', relPosix);
    }
  }

  if (path == workspaceDir) return r'$SDK_ROOT';
  if (p.isWithin(workspaceDir, path)) {
    final rel = p.relative(path, from: workspaceDir);
    final relPosix = toPosix(rel);
    return relPosix == '.'
        ? r'$SDK_ROOT'
        : p.posix.join(r'$SDK_ROOT', relPosix);
  }

  if (path.contains('=')) {
    final idx = path.indexOf('=');
    final name = path.substring(0, idx);
    final value = path.substring(idx + 1);
    final sanitizedValue = _sanitizePath(value, workspaceDir, co19Dir);
    if (sanitizedValue != value) {
      return '$name=$sanitizedValue';
    }
  }

  return path.replaceAll('\\', '/');
}

final _globCache = <String, RegExp>{};

bool _matchesPattern(String path, String pattern) {
  if (pattern.endsWith('**')) {
    final prefix = pattern.substring(0, pattern.length - 2);
    return path.startsWith(prefix);
  }
  if (pattern.contains('*')) {
    final regex = _globCache.putIfAbsent(pattern, () {
      final regexPattern =
          '^${RegExp.escape(pattern).replaceAll(r'\*\*', '.*').replaceAll(r'\*', '[^/]*')}\$';
      return RegExp(regexPattern);
    });
    return regex.hasMatch(path);
  }
  return path == pattern;
}
