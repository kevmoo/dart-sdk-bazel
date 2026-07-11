// Copyright (c) 2026, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';

/// Runs a CLI entrypoint inside [runZonedGuarded], silently trapping and
/// ignoring [FileSystemException]s caused by broken pipes (OS error 32 / EPIPE)
/// when the process output is piped to downstream utilities like `head` or `grep`.
void runCli(void Function() entrypoint) {
  runZonedGuarded(entrypoint, (error, stack) {
    if (error is FileSystemException &&
        (error.osError?.errorCode == 32 ||
            error.message.contains('Broken pipe'))) {
      return; // Ignore broken pipe when downstream consumer closes early
    }
    stderr.writeln('Unhandled error: $error\n$stack');
    exit(1);
  });
}

/// Runs a Git command and returns its trimmed stdout if successful, or `null` if failed.
Future<String?> runGit(List<String> args) async {
  try {
    final res = await Process.run('git', args);
    if (res.exitCode == 0) {
      return res.stdout.toString().trim();
    }
  } catch (_) {}
  return null;
}

/// Checks if the Git working directory is completely clean without untracked files.
Future<bool> isGitClean() async {
  final out = await runGit(['status', '--porcelain', '-uno']);
  return out != null && out.isEmpty;
}

/// Finds the merge base commit SHA between [ref1] and [ref2].
Future<String?> getGitMergeBase(String ref1, String ref2) async {
  final base = await runGit(['merge-base', ref1, ref2]);
  return (base != null && base.isNotEmpty) ? base : null;
}

/// Converts Windows backslashes (`\`) to POSIX forward slashes (`/`).
String toPosixPath(String path) => path.replaceAll('\\', '/');

/// Formats [data] as indented JSON (`  ` by default).
String formatJson(Object? data, {String indent = '  '}) =>
    JsonEncoder.withIndent(indent).convert(data);

/// Formats and writes [data] as indented JSON to [path], creating parent directories automatically.
void writeJsonFile(String path, Object? data, {String indent = '  '}) {
  final file = File(path);
  file.parent.createSync(recursive: true);
  file.writeAsStringSync('${formatJson(data, indent: indent)}\n');
}

/// Recursively lists all Dart source files (`.dart`) within [dir].
List<File> findDartFiles(Directory dir) {
  if (!dir.existsSync()) return [];
  return dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();
}

/// Parses [args] using [parser]. Handles `--help` by printing usage and exiting `0`,
/// and catches parse errors by printing to `stderr` and exiting `1`.
ArgResults parseArgsOrExit(ArgParser parser, List<String> args) {
  try {
    final results = parser.parse(args);
    if (results['help'] as bool? ?? false) {
      print(parser.usage);
      exit(0);
    }
    return results;
  } catch (e) {
    stderr.writeln('Error: $e\n');
    print(parser.usage);
    exit(1);
  }
}
