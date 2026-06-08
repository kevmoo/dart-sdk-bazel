#!/usr/bin/env dart
// Copyright (c) 2026, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:io';
import 'package:args/args.dart';

/// Imports an upstream Gerrit CL or GitHub PR into the local Bazel workspace.
///
/// This script automates the developer workflow for testing upstream changes
/// under the Bazel build system. It performs the following steps:
///
/// 1. Parses and validates CLI arguments (Gerrit CL number or PR URL, base branch, etc.).
/// 2. Verifies that the local Git working tree is clean to prevent overwriting unstaged work.
/// 3. Resolves the latest patchset or ref for the specified CL/PR.
///    - For Gerrit: Queries the Gerrit REST API to find the fetch ref (e.g., refs/changes/...).
///    - For GitHub: Translates the PR URL to its merge ref (e.g., refs/pull/.../head).
/// 4. Creates a new local feature branch (named `gerrit-<cl>` or `github-<pr>`) starting
///    from the configured Bazel integration base branch (defaulting to `bazel-fork/main`).
/// 5. Fetches the remote ref from the upstream repository and cherry-picks/applies
///    the changes onto the new feature branch.
/// 6. Automatically runs `gclient sync` using the `depot_tools` in the environment
///    to ensure all Dart SDK dependencies are synchronized and up-to-date.
///
/// Usage:
/// ```bash
/// dart tools/bazel/bridge/import.dart <cl-number-or-pr-url> [options]
/// ```
void main(List<String> args) async {
  final parser = ArgParser()
    ..addOption(
      'base',
      abbr: 'b',
      help: 'Base branch to branch off.',
      defaultsTo: 'bazel-fork/main',
    )
    ..addOption('name',
        abbr: 'n', help: 'Explicit name for the created branch.')
    ..addOption('patchset',
        abbr: 'p', help: 'Specific Gerrit patchset to import.')
    ..addFlag('sync',
        help: 'Whether to run gclient sync after importing.', defaultsTo: true)
    ..addFlag('verbose', abbr: 'v', help: 'Verbose output.', defaultsTo: false)
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show this help.');

  final ArgResults results;
  try {
    results = parser.parse(args);
  } catch (e) {
    stderr.writeln('Error: $e');
    printUsage(parser);
    exit(1);
  }

  if (results['help'] as bool) {
    printUsage(parser);
    exit(0);
  }

  if (results.rest.isEmpty) {
    stderr
        .writeln('Error: Missing change identifier (Gerrit CL or GitHub PR).');
    printUsage(parser);
    exit(1);
  }

  final changeIdentifier = results.rest.first;
  final baseBranch = results['base'] as String;
  final explicitName = results['name'] as String?;
  final patchsetOpt = results['patchset'] as String?;
  final shouldSync = results['sync'] as bool;
  final verbose = results['verbose'] as bool;

  // 1. Verify git state is clean
  if (!await isGitClean()) {
    stderr.writeln(
        'Error: Git working directory is not clean. Commit or stash your changes.');
    exit(1);
  }

  // 2. Parse change identifier
  final ChangeInfo changeInfo;
  try {
    changeInfo = parseChangeIdentifier(changeIdentifier, patchsetOpt);
  } catch (e) {
    stderr.writeln('Error parsing change identifier: $e');
    exit(1);
  }

  if (verbose) {
    print('Detected change: $changeInfo');
  }

  // 3. Resolve latest patchset if Gerrit and not specified
  String targetRef = changeInfo.ref;
  String branchName = explicitName ?? changeInfo.defaultBranchName;

  if (changeInfo.type == ChangeType.gerrit && changeInfo.patchset == null) {
    print('Resolving latest patchset for Gerrit CL ${changeInfo.id}...');
    final latestPatchset = await resolveLatestGerritPatchset(changeInfo.id);
    if (latestPatchset == null) {
      stderr.writeln(
          'Error: Could not resolve latest patchset for CL ${changeInfo.id}.');
      exit(1);
    }
    print('Latest patchset is $latestPatchset');
    targetRef = changeInfo.getRefForPatchset(latestPatchset);
    branchName =
        explicitName ?? changeInfo.getBranchNameForPatchset(latestPatchset);
  }

  print('Importing target ref: $targetRef');
  print('Creating branch: $branchName off $baseBranch');

  // 4. Fetch the ref
  print('Fetching ref $targetRef from origin...');
  if (!await gitFetch('origin', targetRef, verbose)) {
    // Try upstream if origin fails (Gerrit might be on upstream)
    print('Fetch from origin failed, trying upstream...');
    if (!await gitFetch('upstream', targetRef, verbose)) {
      stderr.writeln(
          'Error: Failed to fetch ref $targetRef from origin or upstream.');
      exit(1);
    }
  }

  // 5. Create branch and checkout
  if (!await gitCheckoutAndBranch(branchName, baseBranch, verbose)) {
    stderr.writeln('Error: Failed to create branch $branchName.');
    exit(1);
  }

  // 6. Apply the change (cherry-pick range from merge-base to FETCH_HEAD)
  print('Applying change...');
  final mergeBaseResult =
      await Process.run('git', ['merge-base', baseBranch, 'FETCH_HEAD']);
  if (mergeBaseResult.exitCode != 0) {
    stderr.writeln('Error: Failed to find merge base.');
    exit(1);
  }
  final mergeBase = (mergeBaseResult.stdout as String).trim();

  final countResult = await Process.run(
      'git', ['rev-list', '--count', '$mergeBase..FETCH_HEAD']);
  final count = int.tryParse((countResult.stdout as String).trim()) ?? 0;
  if (count == 0) {
    print('ℹ️ No new commits to apply.');
    exit(0);
  }

  final applySuccess = await gitCherryPick(
      count == 1 ? 'FETCH_HEAD' : '$mergeBase..FETCH_HEAD', verbose);
  if (!applySuccess) {
    stderr.writeln('Error: Failed to apply change. There might be conflicts.');
    stderr.writeln(
        'You are now on branch $branchName. Please resolve conflicts manually:\n'
        '  1. Resolve conflicts in files, git add them, and run "git cherry-pick --continue"\n'
        '  2. Or abort the import by running "git cherry-pick --abort"');
    exit(2); // Exit code 2 for conflicts
  }

  // 7. Detect BUILD.gn changes and warn
  final modifiedFiles = await gitGetModifiedFiles(baseBranch, 'HEAD');
  final hasBuildGnChanges =
      modifiedFiles.any((f) => f.endsWith('BUILD.gn') || f.endsWith('.gni'));
  if (hasBuildGnChanges) {
    stderr.writeln(
        '\n⚠️  WARNING: BUILD.gn or .gni files were modified in this patch.');
    stderr.writeln(
        'Bazel builds may fail until you manually update the corresponding BUILD.bazel files');
    stderr.writeln('or run tools/bazel/translate_gn_desc.py.');
  }

  // 8. Run gclient sync if DEPS changed
  // 8. Run gclient sync if requested
  if (shouldSync) {
    final hasDepsChanges = modifiedFiles.any((f) => f == 'DEPS');
    if (hasDepsChanges) {
      print('\nDEPS file was modified. Running gclient sync...');
    } else {
      print('\nRunning gclient sync to ensure environment is aligned...');
    }

    final syncSuccess = await runGclientSync(verbose);
    if (!syncSuccess) {
      stderr.writeln('Error: gclient sync failed.');
      exit(3); // Exit code 3 for sync failure
    }
  }

  print('\nSuccessfully imported change to branch $branchName! 🎉');
}

void printUsage(ArgParser parser) {
  print(
      'Usage: dart tools/bazel/bridge/import.dart [options] <change-identifier>');
  print(parser.usage);
}

enum ChangeType { gerrit, github }

class ChangeInfo {
  final ChangeType type;
  final String id; // CL number or PR number
  final String? patchset; // Gerrit only

  ChangeInfo({required this.type, required this.id, this.patchset});

  String get ref {
    switch (type) {
      case ChangeType.gerrit:
        final ps = patchset ?? '1'; // Default to 1 if not known yet
        return getRefForPatchset(ps);
      case ChangeType.github:
        return 'refs/pull/$id/head';
    }
  }

  String getRefForPatchset(String ps) {
    final lastTwo = (int.parse(id) % 100).toString().padLeft(2, '0');
    return 'refs/changes/$lastTwo/$id/$ps';
  }

  String get defaultBranchName {
    switch (type) {
      case ChangeType.gerrit:
        return 'gerrit-$id${patchset != null ? "-ps$patchset" : ""}';
      case ChangeType.github:
        return 'github-pr-$id';
    }
  }

  String getBranchNameForPatchset(String ps) {
    return 'gerrit-$id-ps$ps';
  }

  @override
  String toString() => 'Type: $type, ID: $id, Patchset: $patchset';
}

ChangeInfo parseChangeIdentifier(String identifier, String? explicitPatchset) {
  // Gerrit URL: https://dart-review.googlesource.com/c/sdk/+/505900
  // Gerrit URL with patchset: https://dart-review.googlesource.com/c/sdk/+/505900/1
  // GitHub PR URL: https://github.com/dart-lang/sdk/pull/123
  // Gerrit CL number: 505900
  // GitHub PR number: 123 (if we default to Gerrit if it's just a number)

  final gerritUrlRegExp = RegExp(
      r'dart-review\.googlesource\.com/(?:c/sdk/\+/|c/)?(\d+)(?:/(\d+))?');
  final githubUrlRegExp = RegExp(r'github\.com/dart-lang/sdk/pull/(\d+)');
  final numberRegExp = RegExp(r'^\d+$');

  var match = gerritUrlRegExp.firstMatch(identifier);
  if (match != null) {
    final cl = match.group(1)!;
    final ps = match.group(2) ?? explicitPatchset;
    return ChangeInfo(type: ChangeType.gerrit, id: cl, patchset: ps);
  }

  match = githubUrlRegExp.firstMatch(identifier);
  if (match != null) {
    final pr = match.group(1)!;
    return ChangeInfo(type: ChangeType.github, id: pr);
  }

  if (numberRegExp.hasMatch(identifier)) {
    // If it's just a number, default to Gerrit CL
    return ChangeInfo(
        type: ChangeType.gerrit, id: identifier, patchset: explicitPatchset);
  }

  throw FormatException('Invalid change identifier: $identifier');
}

Future<bool> isGitClean() async {
  final result = await Process.run('git', ['status', '--porcelain', '-uno']);
  return result.exitCode == 0 && (result.stdout as String).trim().isEmpty;
}

Future<String?> resolveLatestGerritPatchset(String clId) async {
  final lastTwo = (int.parse(clId) % 100).toString().padLeft(2, '0');
  final refPattern = 'refs/changes/$lastTwo/$clId/*';

  // Try upstream first, then origin
  for (final remote in ['upstream', 'origin']) {
    final result = await Process.run('git', ['ls-remote', remote, refPattern]);
    if (result.exitCode == 0) {
      final stdout = result.stdout as String;
      if (stdout.isEmpty) continue;

      int maxPatchset = 0;
      final lines = stdout.split('\n');
      for (final line in lines) {
        if (line.isEmpty) continue;
        final parts = line.split('\t');
        if (parts.length < 2) continue;
        final ref = parts[1];
        final segments = ref.split('/');
        if (segments.length == 5) {
          final psStr = segments[4];
          final ps = int.tryParse(psStr);
          if (ps != null && ps > maxPatchset) {
            maxPatchset = ps;
          }
        }
      }
      if (maxPatchset > 0) {
        return maxPatchset.toString();
      }
    }
  }
  return null;
}

Future<bool> gitFetch(String remote, String ref, bool verbose) async {
  final args = ['fetch', remote, ref];
  if (verbose) {
    print('Running: git ${args.join(' ')}');
  }
  final result =
      await Process.start('git', args, mode: ProcessStartMode.inheritStdio);
  final exitCode = await result.exitCode;
  return exitCode == 0;
}

Future<bool> gitCheckoutAndBranch(
    String branchName, String? baseBranch, bool verbose) async {
  // Check if branch already exists locally
  final checkResult = await Process.run(
      'git', ['show-ref', '--verify', 'refs/heads/$branchName']);
  if (checkResult.exitCode == 0) {
    stderr.writeln('Error: Branch $branchName already exists.');
    return false;
  }

  final args = ['checkout', '-b', branchName];
  if (baseBranch != null) {
    args.add(baseBranch);
  }

  if (verbose) {
    print('Running: git ${args.join(' ')}');
  }
  final result = await Process.run('git', args);
  if (verbose && (result.stdout as String).isNotEmpty) {
    print(result.stdout);
  }
  if (result.exitCode != 0) {
    stderr.writeln(result.stderr);
  }
  return result.exitCode == 0;
}

Future<bool> gitCherryPick(String ref, bool verbose) async {
  final args = ['cherry-pick', ref];
  if (verbose) {
    print('Running: git ${args.join(' ')}');
  }
  final result =
      await Process.start('git', args, mode: ProcessStartMode.inheritStdio);
  final exitCode = await result.exitCode;
  return exitCode == 0;
}

Future<List<String>> gitGetModifiedFiles(String base, String head) async {
  final result =
      await Process.run('git', ['diff', '--name-only', '$base...$head']);
  if (result.exitCode != 0) {
    return [];
  }
  return (result.stdout as String)
      .split('\n')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList();
}

Future<bool> runGclientSync(bool verbose) async {
  if (verbose) {
    print('Running: gclient sync');
  }
  try {
    // Use inheritStdio when verbose to let the OS handle streaming,
    // otherwise use normal and drain streams to prevent hangs.
    // runInShell is required on Windows because gclient is a batch file.
    final result = await Process.start(
      'gclient',
      ['sync'],
      environment: Platform.environment,
      runInShell: Platform.isWindows,
      mode: verbose ? ProcessStartMode.inheritStdio : ProcessStartMode.normal,
    );

    // Set up stream capture futures immediately if not verbose
    Future<List<int>>? stderrFuture;
    Future<void>? stdoutFuture;
    if (!verbose) {
      stderrFuture =
          result.stderr.fold<List<int>>([], (buf, chunk) => buf..addAll(chunk));
      stdoutFuture = result.stdout.drain();
    }

    final exitCode = await result.exitCode;

    // Always await stream futures to prevent background dangling streams
    List<int> stderrBytes = [];
    if (!verbose && stderrFuture != null) {
      stderrBytes = await stderrFuture;
    }
    if (!verbose && stdoutFuture != null) {
      await stdoutFuture;
    }

    if (exitCode != 0) {
      if (stderrBytes.isNotEmpty) {
        stderr.writeln('\n❌ gclient sync failed with the following error:');
        stderr.add(stderrBytes);
        stderr.writeln();
      }
      return false;
    }
    return true;
  } on ProcessException catch (e) {
    stderr.writeln(
        'Error: Failed to execute "gclient". Make sure depot_tools is in your PATH.');
    if (verbose) {
      stderr.writeln('Details: $e');
    }
    return false;
  }
}
