// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

late final String packageName;
late final String packageDir;

// Direct dependencies: file -> set of local files it imports/exports/parts
final Map<String, Set<String>> directDeps = {};

void main(List<String> args) {
  if (args.isEmpty) {
    print('Usage: dart gen_test_imports.dart <package-dir>');
    exit(1);
  }

  packageDir = args[0].replaceAll('\\', '/');
  final dir = Directory(packageDir);
  if (!dir.existsSync()) {
    print('Error: Package directory does not exist: $packageDir');
    exit(1);
  }

  // Find package name from pubspec.yaml
  final pubspecFile = File('${dir.path}/pubspec.yaml');
  if (!pubspecFile.existsSync()) {
    print('Error: pubspec.yaml not found in $packageDir');
    exit(1);
  }

  final pubspecContent = pubspecFile.readAsStringSync();
  final nameMatch =
      RegExp(r'^name:\s*(\w+)', multiLine: true).firstMatch(pubspecContent);
  if (nameMatch == null) {
    print('Error: Could not find package name in pubspec.yaml');
    exit(1);
  }
  packageName = nameMatch.group(1)!;
  print('Scanning package $packageName in $packageDir...');

  final testDir = Directory('${dir.path}/test');
  if (!testDir.existsSync()) {
    print('No test directory found. Nothing to do.');
    return;
  }

  // 1. Find all test files
  final testFiles = <String>[];
  _findDartFiles(testDir, testFiles);

  // 2. Build direct dependency graph starting from test files
  for (final testFile in testFiles) {
    final relPath = _toRelative(testFile);
    _processFile(relPath);
  }

  // 3. Sort keys and target lists of directDeps alphabetically, omitting empty lists
  final sortedMapping = <String, List<String>>{};
  final sortedKeys = directDeps.keys.toList()..sort();
  for (final key in sortedKeys) {
    final deps = directDeps[key]!;
    if (deps.isEmpty) {
      continue; // Optimization: skip empty lists to minimize JSON size
    }
    final sortedDeps = deps.toList()..sort();
    sortedMapping[key] = sortedDeps;
  }

  // 4. Write JSON output
  final outputFile = File('${dir.path}/test_imports.json');
  final jsonString = JsonEncoder.withIndent('  ').convert(sortedMapping);
  outputFile.writeAsStringSync('$jsonString\n');
  print('Wrote ${sortedMapping.length} test mappings to ${outputFile.path}');
}

void _findDartFiles(Directory dir, List<String> results) {
  for (final entity in dir.listSync(recursive: true)) {
    if (entity is File && entity.path.endsWith('.dart')) {
      results.add(entity.path);
    }
  }
}

String _toRelative(String absolutePath) {
  final rel = p.relative(absolutePath, from: packageDir);
  return p.posix.joinAll(p.split(rel));
}

void _processFile(String relPath) {
  if (directDeps.containsKey(relPath)) return;

  final file = File('$packageDir/$relPath');
  if (!file.existsSync()) {
    directDeps[relPath] = {};
    return;
  }

  final content = file.readAsStringSync();
  final stripped = stripComments(content);
  final imports = _extractImportsAndParts(stripped);

  final resolved = <String>{};
  final fileDir = _getDirectory(relPath);

  for (final imp in imports) {
    final norm = _normalizePath(fileDir, imp);
    if (norm.isNotEmpty) {
      if (File('$packageDir/$norm').existsSync()) {
        resolved.add(norm);
      }
    }
  }

  directDeps[relPath] = resolved;

  // Recursively process imported files
  for (final dep in resolved) {
    _processFile(dep);
  }
}

String _getDirectory(String filePath) {
  final dirname = p.posix.dirname(filePath);
  return (dirname == '.' || dirname.isEmpty) ? '' : dirname;
}

String _normalizePath(String basePath, String relativePath) {
  if (relativePath.startsWith('package:')) {
    if (relativePath.startsWith('package:$packageName/')) {
      return p.posix
          .join('lib', relativePath.substring('package:$packageName/'.length));
    }
    return '';
  }
  if (relativePath.startsWith('dart:') || relativePath.contains(':')) {
    return '';
  }
  return p.posix.normalize(p.posix.join(basePath, relativePath));
}

List<String> _extractImportsAndParts(String content) {
  final relations = <String>[];
  // Match all import, export, and part directives up to the ending semicolon.
  final statementRegex = RegExp(r'''\b(?:import|export|part)\s+([\s\S]*?);''');
  final quoteRegex = RegExp(r'''['"]([^'"]+)['"]''');

  for (final match in statementRegex.allMatches(content)) {
    final statement = match.group(0)!;
    // Exclude 'part of' statements
    if (RegExp(r'^\s*part\s+of\b').hasMatch(statement)) continue;

    final directiveContent = match.group(1)!;
    for (final quoteMatch in quoteRegex.allMatches(directiveContent)) {
      relations.add(quoteMatch.group(1)!);
    }
  }
  return relations;
}

String stripComments(String code) {
  final sb = StringBuffer();
  int i = 0;
  final len = code.length;
  while (i < len) {
    if (code.startsWith('//', i)) {
      i += 2;
      while (i < len && code[i] != '\n') {
        i++;
      }
    } else if (code.startsWith('/*', i)) {
      int nestLevel = 1;
      i += 2;
      while (i < len && nestLevel > 0) {
        if (code.startsWith('/*', i)) {
          nestLevel++;
          i += 2;
        } else if (code.startsWith('*/', i)) {
          nestLevel--;
          i += 2;
        } else {
          i++;
        }
      }
    } else {
      final c = code[i];
      if (c == "'" || c == '"') {
        final quote = c;
        sb.write(c);
        i++;
        bool isTriple = false;
        if (i + 1 < len && code[i] == quote && code[i + 1] == quote) {
          isTriple = true;
          sb.write(quote);
          sb.write(quote);
          i += 2;
        }

        while (i < len) {
          if (code[i] == '\\') {
            sb.write(code[i]);
            if (i + 1 < len) {
              sb.write(code[i + 1]);
              i += 2;
            } else {
              i++;
            }
          } else if (isTriple) {
            if (code.startsWith(quote * 3, i)) {
              sb.write(quote * 3);
              i += 3;
              break;
            } else {
              sb.write(code[i]);
              i++;
            }
          } else {
            if (code[i] == quote) {
              sb.write(quote);
              i++;
              break;
            } else {
              sb.write(code[i]);
              i++;
            }
          }
        }
      } else {
        sb.write(c);
        i++;
      }
    }
  }
  return sb.toString();
}
