#!/usr/bin/env dart
// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';
import 'package:args/args.dart';

/// Exports Core Dart SDK changes from a Bazel development branch back to a clean,
/// upstream-ready branch tracking the main SDK branch.
///
/// This script automates the process of extracting your validated fixes from the
/// Bazel migration sandbox, surgically filtering out all Bazel-specific configuration
/// files, and preparing them for upstream submission.
///
/// It performs the following steps:
///
/// 1. Parses and validates CLI arguments (base branch, target branch name, specific commit, etc.).
/// 2. Verifies that the local Git working tree is clean (required for `git am` to apply patches).
/// 3. Generates a filtered patch stream using `git format-patch` with native Git pathspec
///    exclusions. This surgically strips out:
///    - `tools/bazel/` (Bazel bridge and migration tooling)
///    - `*.bzl` (Starlark build files)
///    - `BUILD.bazel` (Bazel build definitions)
///    - `WORKSPACE` / `MODULE.bazel` (Bazel workspace configs)
/// 4. Supports two modes of operation:
///    - **Branch Export (Default):** Exports all commits on the current branch since the
///      configured base branch (defaulting to `bazel-fork/main`). Empty commits (e.g.,
///      Bazel-only changes) are naturally and silently dropped from the exported history.
///    - **Single Commit Export (`--commit`):** "Peels off" a single specific commit from
///      your history and exports only that change, bypassing all other commits.
/// 5. Creates a new target branch starting directly from the clean Core SDK base
///    (defaulting to `origin/main`).
/// 6. Applies the filtered patches using `git am`, which automatically recreates the
///    commits one-by-one, preserving the original author, date, and commit messages.
/// 7. Optionally triggers `git cl upload` automatically if the `--upload` flag is passed,
///    inheriting the terminal's standard input/output so you can interactively enter
///    descriptions or reviewers.
///
/// Usage:
/// ```bash
/// dart tools/bazel/bridge/export.dart [options]
/// ```
void main(List<String> args) async {
  final parser = ArgParser()
    ..addOption(
      'base',
      abbr: 'b',
      help:
          'The Bazel integration base branch to compare against (used when not exporting a specific commit).',
      defaultsTo: 'bazel-fork/main',
    )
    ..addOption(
      'commit',
      abbr: 'c',
      help:
          'A specific commit hash to export. If provided, only this commit is exported.',
    )
    ..addOption(
      'target-base',
      help: 'The Core SDK base branch to branch off.',
      defaultsTo: 'origin/main',
    )
    ..addOption(
      'name',
      abbr: 'n',
      help:
          'The name of the exported branch to create. Defaults to export-<timestamp>.',
    )
    ..addFlag(
      'upload',
      abbr: 'u',
      help: 'Automatically run "git cl upload" after successful export.',
      defaultsTo: false,
      negatable: false,
    )
    ..addFlag(
      'verbose',
      abbr: 'v',
      help: 'Enable verbose logging.',
      defaultsTo: false,
    )
    ..addFlag(
      'help',
      abbr: 'h',
      help: 'Show this help message.',
      negatable: false,
    );

  late final ArgResults results;
  try {
    results = parser.parse(args);
  } catch (e) {
    print('Error parsing arguments: $e');
    _printUsage(parser);
    exit(1);
  }

  if (results['help'] as bool) {
    _printUsage(parser);
    return;
  }

  final base = results['base'] as String;
  final commit = results['commit'] as String?;
  final targetBase = results['target-base'] as String;
  final upload = results['upload'] as bool;
  final verbose = results['verbose'] as bool;

  final timestamp = DateTime.now().millisecondsSinceEpoch;
  final branchName = results['name'] as String? ?? 'export-$timestamp';

  print('🚀 Starting Bazel-to-Core export bridge...');
  if (verbose) {
    print('Settings:');
    if (commit != null) {
      print('  Exporting Commit:   $commit');
    } else {
      print('  Bazel Base Branch:  $base');
    }
    print('  Core Target Base:   $targetBase');
    print('  New Branch Name:    $branchName');
    print('  Auto-Upload:        $upload');
  }

  // 1. Verify Git is clean
  if (!await _isGitClean()) {
    print(
        '❌ Error: Git working tree is not clean. Please commit or stash your changes before exporting.');
    exit(1);
  }

  // 2. Generate the filtered patch
  final range = commit != null ? '$commit~1..$commit' : '$base..HEAD';
  print('📦 Generating filtered patch for $range...');

  final excludes = [
    ':(exclude)tools/bazel',
    ':(exclude)*.bzl',
    ':(exclude)BUILD.bazel',
    ':(exclude)WORKSPACE',
    ':(exclude)MODULE.bazel',
  ];

  final patchFile =
      File('${Directory.systemTemp.path}/export_$timestamp.patch');
  if (verbose) {
    print('Temporary patch file: ${patchFile.path}');
  }

  final formatPatchArgs = [
    'format-patch',
    '--stdout',
    range,
    '--',
    '.',
    ...excludes,
  ];

  if (verbose) {
    print('Running: git ${formatPatchArgs.join(' ')}');
  }

  final patchResult = await Process.run('git', formatPatchArgs);
  if (patchResult.exitCode != 0) {
    print('❌ Error generating patch:\n${patchResult.stderr}');
    exit(1);
  }

  final patchContent = patchResult.stdout as String;
  if (patchContent.trim().isEmpty) {
    print('ℹ️ No Core SDK changes detected for $range. Nothing to export.');
    exit(0);
  }

  patchFile.writeAsStringSync(patchContent);
  print(
      '✅ Filtered patch generated successfully (${patchFile.lengthSync()} bytes).');

  // Remember the current branch so we can return to it if needed
  final currentBranch = await _getCurrentBranch();
  if (verbose) {
    print('Active branch: $currentBranch');
  }

  // 3. Create the new target branch off targetBase
  print('🌱 Creating new branch $branchName off $targetBase...');
  final checkoutResult = await Process.run('git', [
    'checkout',
    '-b',
    branchName,
    targetBase,
  ]);

  if (checkoutResult.exitCode != 0) {
    print('❌ Error creating branch:\n${checkoutResult.stderr}');
    _cleanup(patchFile);
    exit(1);
  }

  // 4. Apply the patch using git am
  print('📥 Applying filtered patch via git am...');
  final amResult = await Process.run('git', ['am', patchFile.path]);

  if (amResult.exitCode != 0) {
    print(
        '❌ Error applying patch via git am:\n${amResult.stdout}\n${amResult.stderr}');
    print('\n⚠️ Git is in the middle of an "am" session. You can:');
    print('  1. Resolve conflicts, git add, and run "git am --continue"');
    print('  2. Abort the export and return to your branch by running:');
    print('     git am --abort');
    print('     git checkout $currentBranch');
    print('     git branch -D $branchName');
    _cleanup(patchFile);
    exit(1);
  }

  print('🎉 Export completed successfully!');
  print(
      'New branch $branchName contains the core SDK changes, cleanly separated.');

  _cleanup(patchFile);

  // 5. Optionally upload to Gerrit
  if (upload) {
    print('\n📤 Uploading to Gerrit via git cl upload...');
    final process = await Process.start(
      'git',
      ['cl', 'upload'],
      mode: ProcessStartMode.inheritStdio,
    );
    final exitCode = await process.exitCode;
    if (exitCode != 0) {
      print('❌ Error: git cl upload failed with exit code $exitCode');
      exit(exitCode);
    }
    print('🎉 Upload completed successfully!');
  } else {
    print('\nTo upload to Gerrit, run:');
    print('  git cl upload');
  }
}

void _printUsage(ArgParser parser) {
  print('Usage: dart export.dart [options]');
  print(parser.usage);
}

void _cleanup(File file) {
  if (file.existsSync()) {
    try {
      file.deleteSync();
    } catch (_) {}
  }
}

Future<bool> _isGitClean() async {
  final result = await Process.run('git', ['status', '--porcelain', '-uno']);
  return result.exitCode == 0 && (result.stdout as String).trim().isEmpty;
}

Future<String> _getCurrentBranch() async {
  final result = await Process.run('git', ['branch', '--show-current']);
  return (result.stdout as String).trim();
}
